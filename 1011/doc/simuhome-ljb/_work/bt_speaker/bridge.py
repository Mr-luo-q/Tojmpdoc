r"""把本机的蓝牙音箱通过 MQTT discovery 接进 HA，命令走 MQTT。

机制照 simuhome_mqtt_publisher 那一套来：

  discovery   homeassistant/switch/bt_speaker/config   retained，HA 自动建实体
  state       bt_speaker/v1/state                      ON / OFF，retained
  command     bt_speaker/v1/set                        ON / OFF
  say         bt_speaker/v1/say                        文本 → Windows TTS → 播出去
  status      bt_speaker/v1/status                     online / offline（LWT 维护）

音箱这一侧：Windows 负责 A2DP 配对，本服务负责"把声音播出去"。
  - 音频走系统当前的默认输出设备。把蓝牙音箱设成默认输出，声音就过去了。
  - audio.dry_run = true 时只打日志不出声，用来先单独验证 MQTT 链路。
  - audio.loop = true 时 ON 会一直循环播放，直到 OFF；默认播一遍就自动回 OFF。

用法：python _work\bt_speaker\bridge.py
"""

from __future__ import annotations

import json
import logging
import subprocess
import sys
import tempfile
import threading
import time
import wave
from pathlib import Path

import paho.mqtt.client as mqtt
import yaml

HERE = Path(__file__).resolve().parent

# --- 主题与 discovery 报文（改契约只改这一段） ---
TOPIC_PREFIX = "bt_speaker/v1"
DISCOVERY_TOPIC = "homeassistant/switch/bt_speaker/config"
VOLUME_DISCOVERY_TOPIC = "homeassistant/number/bt_speaker_volume/config"
DEVICE_IDENTIFIER = "bt_speaker"          # MCP 认领规则靠它推逻辑 id：bt_ → speaker
UNIQUE_ID = "bt_speaker_switch"
VOLUME_UNIQUE_ID = "bt_speaker_volume"
ORIGIN = {"name": "bt-speaker-bridge", "sw": "0.1.0"}


def _shared_block(name: str, model: str) -> dict:
    """两个实体共用的设备块与可用性字段。

    关键：switch 和 number 必须挂同一个 identifiers，HA 才会把它们归到同一台设备，
    MCP 也才会把 power 和 level 两个角色投影成同一台逻辑设备。
    """

    return {
        "availability_topic": f"{TOPIC_PREFIX}/status",
        "payload_available": "online",
        "payload_not_available": "offline",
        "device": {
            # 注意：identifiers 必须是「单个字符串的列表」。
            # 写成 ["a", "b"] 会被 HA 当成两个独立标识，设备会串台。
            "identifiers": [DEVICE_IDENTIFIER],
            "name": name,
            "manufacturer": "local-mqtt-bridge",
            "model": model,
        },
        "origin": ORIGIN,
    }


def discovery_payload(name: str, model: str) -> dict:
    """HA 的 MQTT switch discovery 报文。"""

    return {
        "name": name,
        "unique_id": UNIQUE_ID,
        "state_topic": f"{TOPIC_PREFIX}/state",
        "command_topic": f"{TOPIC_PREFIX}/set",
        "payload_on": "ON",
        "payload_off": "OFF",
        "state_on": "ON",
        "state_off": "OFF",
        "icon": "mdi:speaker",
        **_shared_block(name, model),
    }


def volume_discovery_payload(name: str, model: str) -> dict:
    """HA 的 MQTT number discovery 报文：音量（0~100）。

    为什么要做成 number：MCP 的角色层按 `domain + device_class + 单位 + 属性` 推断角色，
    number 的范围落在 0~100 就会被判成 `level` 角色，于是这台设备自动多出
    `set_percentage` 这个量级动作——不用改 MCP 的任何源码。
    """

    return {
        "name": "音量",
        "unique_id": VOLUME_UNIQUE_ID,
        "state_topic": f"{TOPIC_PREFIX}/volume",
        "command_topic": f"{TOPIC_PREFIX}/volume/set",
        "min": 0,
        "max": 100,
        "step": 1,
        "mode": "slider",
        "unit_of_measurement": "%",
        "icon": "mdi:volume-high",
        **_shared_block(name, model),
    }


def wav_duration(path: Path) -> float:
    """读 WAV 头算时长（秒），用来判断播完没有。"""

    with wave.open(str(path), "rb") as handle:
        return handle.getnframes() / float(handle.getframerate())


def make_tone(path: Path, seconds: float = 2.5) -> None:
    """没有素材时生成一段提示音：两个音高的和弦衰减音。"""

    import math
    import struct

    rate = 44100
    frames = bytearray()
    total = int(rate * seconds)
    for index in range(total):
        t = index / rate
        envelope = min(1.0, t * 8) * math.exp(-2.2 * t)
        sample = 0.34 * envelope * (
            math.sin(2 * math.pi * 660 * t) + 0.7 * math.sin(2 * math.pi * 880 * t)
        )
        frames += struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(bytes(frames))


def load_wav(path: Path):
    """把 WAV 读成 (numpy 数组, 采样率)；单声道自动复制成双声道。

    为什么不用 winsound：它的停止标志 SND_PURGE 在现代 Windows 上不受支持
    （Python 文档明写），所以"停止"是空操作。sounddevice 的 sd.stop() 是立即生效的，
    而且能指定用哪个输出设备。
    """

    import numpy as np

    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    if width != 2:
        raise ValueError(f"只支持 16-bit WAV，当前 {width * 8}-bit：{path.name}")
    data = np.frombuffer(frames, dtype="<i2").reshape(-1, channels)
    if channels == 1:
        data = np.repeat(data, 2, axis=1)
    return data, rate


class ClipPlayer:
    """用声卡回调播一段音频，可以随时硬停。

    为什么不用 sd.play() / sd.stop()：实测发现

      · sd.play(data, rate, loop=True) 之后调 sd.stop()，日志显示"已停止播放"，
        但音箱继续响；
      · 每点一次 ON 就再叠一个流，于是越点越停不下来。

    所以改成自己持有 OutputStream、用回调喂数据。停止 = 把 playing 置 False
    并 abort() 这个流，不依赖任何"库里应该会停"的假设。
    """

    def __init__(self, data, rate: int, device: int | None, loop: bool) -> None:
        import sounddevice as sd

        self._sd = sd
        self.data = data
        self.loop = loop
        self.pos = 0
        self.playing = True
        self.stream = sd.OutputStream(
            samplerate=rate,
            channels=int(data.shape[1]),
            device=device,
            dtype="int16",
            callback=self._callback,
        )

    def _callback(self, outdata, frames, time_info, status) -> None:
        """把数据按帧填进输出缓冲；播完非循环内容就停。"""

        if not self.playing:
            raise self._sd.CallbackStop
        total = len(self.data)
        filled = 0
        while filled < frames:
            if self.pos >= total:
                if not self.loop:
                    outdata[filled:] = 0
                    raise self._sd.CallbackStop
                self.pos = 0
            take = min(frames - filled, total - self.pos)
            outdata[filled:filled + take] = self.data[self.pos:self.pos + take]
            filled += take
            self.pos += take

    def start(self) -> None:
        self.stream.start()

    def stop(self) -> None:
        """硬停：先让回调不再喂数据，再直接 abort 掉这个流。"""

        self.playing = False
        for action in (self.stream.abort, self.stream.close):
            try:
                action()
            except Exception as error:  # noqa: BLE001 - 关不干净也不该抛出去
                logging.warning("关闭音频流时出错：%s", error)


class Player:
    """负责把声音送到默认输出设备，并跟踪"还在播 / 播完了"。"""

    def __init__(self, config: dict, on_idle) -> None:
        self.media = (HERE / str(config.get("media") or "media/announce.wav")).resolve()
        self.loop = bool(config.get("loop", False))
        self.dry_run = bool(config.get("dry_run", True))
        self.device_name = str(config.get("device_name") or "").strip()
        self.say_voice_rate = int(config.get("say_voice_rate", 0))
        self._device_index: int | None = None
        self._device_resolved = False
        self._device_retry_after = 0.0
        self._cache: dict[tuple[str, float], tuple] = {}
        self._clip: ClipPlayer | None = None
        self._on_idle = on_idle
        self._token = 0
        self._timer: threading.Timer | None = None
        self._lock = threading.Lock()

    # --- 对外 ---
    def warmup(self) -> None:
        """把设备解析与音频加载提前做掉。

        实测首次调用（PortAudio 枚举设备）要 8~9 秒，放在命令路径上会让
        "按下到出声"慢得离谱，所以启动时先在后台热一遍。
        """

        try:
            self._resolve_device()
            if self.media.exists():
                self._load(self.media)
            logging.info("预热完成：设备与音频都就绪")
        except Exception as error:  # noqa: BLE001 - 预热失败不该拦住服务
            logging.warning("预热失败（不影响后续尝试）：%s", error)

    def play_file(self, path: Path, loop: bool) -> float:
        """播放一个 WAV，返回时长（秒）；dry_run 时只打日志。"""

        duration = wav_duration(path)
        self.stop(notify=False)
        if self.dry_run:
            logging.info("[dry-run] 本应播放 %s（%.1fs，loop=%s）", path, duration, loop)
        else:
            data, rate = self._load(path)
            device = self._resolve_device()
            try:
                clip = ClipPlayer(data, rate, device, loop)
            except Exception as error:  # noqa: BLE001
                if device is None:
                    raise
                logging.warning("指定设备 #%s 播放失败（%s），退回系统默认", device, error)
                clip = ClipPlayer(data, rate, None, loop)
            clip.start()
            with self._lock:
                self._clip = clip
            logging.info(
                "开始播放 %s（%.1fs，loop=%s，device=%s）",
                path.name,
                duration,
                loop,
                clip.stream.device,
            )
        if not loop:
            self._arm(duration)
        return duration

    def stop(self, notify: bool = True) -> None:
        """停止播放。notify=False 用于"即将重新开始播放"的内部调用。"""

        with self._lock:
            self._token += 1
            if self._timer is not None:
                self._timer.cancel()
                self._timer = None
        if not self.dry_run:
            with self._lock:
                clip, self._clip = self._clip, None
            if clip is not None:
                clip.stop()
        if notify:
            logging.info("已停止播放")
            self._on_idle()

    def _resolve_device(self) -> int | None:
        """按 audio.device_name 找输出设备；优先 A2DP（btha2dp），避开免提（bthhfenum）。

        留空则返回 None，表示用系统默认输出。
        """

        if self._device_resolved:
            return self._device_index
        if not self.device_name:
            self._device_resolved = True
            return None
        # 蓝牙设备会掉线又回来。解析失败时不要把"没找到"永久缓存住，
        # 但也不能每次都做一遍慢枚举（PortAudio 枚举一次要好几秒），
        # 所以失败后隔 30 秒再试。
        now = time.time()
        if now < self._device_retry_after:
            return None
        try:
            import sounddevice as sd

            candidates = [
                (index, str(device.get("name", "")))
                for index, device in enumerate(sd.query_devices())
                if device.get("max_output_channels", 0) > 0
                and self.device_name.lower() in str(device.get("name", "")).lower()
            ]
        except Exception as error:  # noqa: BLE001
            logging.warning("枚举音频设备失败，改用系统默认：%s", error)
            self._device_retry_after = now + 30
            return None
        if not candidates:
            logging.warning("没找到叫 %s 的输出设备，先用系统默认（30 秒后再试）", self.device_name)
            self._device_retry_after = now + 30
            return None

        # 关键：光看名字不够。同一个蓝牙音箱会在 MME / DirectSound / WASAPI / WDM-KS
        # 四组各出现一次，其中 WDM-KS 那几个（名字里带 btha2dp 驱动路径的）虽然像正主，
        # 但 PortAudio 打不开，会报 Invalid device [-9996]。所以必须逐个验能不能打开。
        # 免提档（Hands-Free / bthhfenum）是通话用的，音质差，一并排掉。
        usable: list[tuple[int, str]] = []
        for index, name in candidates:
            lowered = name.lower()
            if "hands-free" in lowered or "bthhfenum" in lowered:
                continue
            try:
                import sounddevice as sd

                sd.check_output_settings(device=index, samplerate=44100, channels=2)
            except Exception:  # noqa: BLE001 - 打不开就换下一个
                continue
            usable.append((index, name))
        if not usable:
            logging.warning("名字含 %s 的设备都打不开，先用系统默认（30 秒后再试）", self.device_name)
            self._device_retry_after = now + 30
            return None
        self._device_index = usable[0][0]
        self._device_resolved = True
        logging.info("输出设备锁定为 #%s %s", usable[0][0], usable[0][1][:60])
        return self._device_index

    # --- 内部 ---
    def _load(self, path: Path):
        """带缓存地读 WAV：同一个文件（含修改时间）只读一次。"""

        try:
            key = (str(path), path.stat().st_mtime)
        except OSError:
            return load_wav(path)
        if key not in self._cache:
            self._cache[key] = load_wav(path)
        return self._cache[key]

    def _arm(self, duration: float) -> None:
        """播完自动回空闲。"""

        with self._lock:
            self._token += 1
            token = self._token
            timer = threading.Timer(duration + 0.2, lambda: self._finished(token))
            timer.daemon = True
            self._timer = timer
            timer.start()

    def _finished(self, token: int) -> None:
        with self._lock:
            if token != self._token:
                return
            self._timer = None
        logging.info("播放结束")
        self._on_idle()

    def say(self, text: str) -> None:
        """用 Windows 自带的 SAPI 合成语音再播放，不依赖第三方库。"""

        target = Path(tempfile.gettempdir()) / "bt_speaker_say.wav"
        script = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            f"$s.Rate = {self.say_voice_rate}; "
            f"$s.SetOutputToWaveFile('{target}'); "
            "$s.Speak([Console]::In.ReadToEnd()); $s.Dispose()"
        )
        subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            input=text,
            text=True,
            encoding="utf-8",
            check=True,
            timeout=60,
        )
        self.play_file(target, loop=False)


class Volume:
    """系统默认输出设备的音量（对外 0~100 整数）。

    pycaw 的接口各版本不同，本机实测是 AudioDevice.EndpointVolume，再调
    GetMasterVolumeLevelScalar / SetMasterVolumeLevelScalar（取值 0.0~1.0）。
    dry_run 时不碰系统音量。pycaw 缺失时自动降级成"不暴露音量"，不影响播放。
    """

    def __init__(self, enabled: bool = True, dry_run: bool = False) -> None:
        self.dry_run = dry_run
        self._endpoint = None
        self.enabled = enabled and self._available()

    @staticmethod
    def _available() -> bool:
        try:
            import pycaw.pycaw  # noqa: F401
        except ImportError:
            logging.warning("没装 pycaw，音量实体不可用（pip install pycaw comtypes）")
            return False
        return True

    def _volume(self):
        if self._endpoint is None:
            from pycaw.pycaw import AudioUtilities

            self._endpoint = AudioUtilities.GetSpeakers().EndpointVolume
        return self._endpoint

    def get(self) -> int | None:
        """读当前音量；读不到返回 None。"""

        if not self.enabled:
            return None
        try:
            return round(self._volume().GetMasterVolumeLevelScalar() * 100)
        except Exception as error:  # noqa: BLE001
            logging.warning("读音量失败：%s", error)
            return None

    def set(self, value: int) -> int | None:
        """设音量，返回设进去的值；失败返回 None。"""

        if not self.enabled:
            return None
        value = max(0, min(100, int(value)))
        if self.dry_run:
            logging.info("[dry-run] 本应把音量设为 %d", value)
            return value
        try:
            self._volume().SetMasterVolumeLevelScalar(value / 100.0, None)
            logging.info("音量已设为 %d", value)
            return value
        except Exception as error:  # noqa: BLE001
            logging.error("设音量失败：%s", error)
            return None


class Bridge:
    """MQTT 侧：发 discovery、收命令、回状态。"""

    def __init__(self, config: dict) -> None:
        self.entity_name = str(config.get("name") or "蓝牙音箱")
        self.model = str(config.get("model") or "BT speaker")
        broker = config.get("broker") or {}
        audio = config.get("audio") or {}
        self.player = Player(audio, self._publish_idle)
        self.volume = Volume(
            enabled=bool(audio.get("volume", True)),
            dry_run=bool(audio.get("dry_run", True)),
        )
        self.volume_poll_s = float(audio.get("volume_poll_s", 5))
        self._volume_last: int | None = None
        self.state = "OFF"
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=str(broker.get("client_id") or "bt-speaker-bridge"),
        )
        if broker.get("username"):
            self.client.username_pw_set(broker["username"], broker.get("password") or "")
        self.host = str(broker.get("host") or "127.0.0.1")
        self.port = int(broker.get("port") or 1883)
        self.client.will_set(f"{TOPIC_PREFIX}/status", "offline", retain=True)
        self._ignored = 0

    # --- 对外 ---
    def run(self) -> None:
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.connect(self.host, self.port, keepalive=60)
        logging.info("已连接 broker %s:%s", self.host, self.port)
        if self.volume.enabled:
            threading.Thread(target=self._poll_volume, daemon=True).start()
        threading.Thread(target=self.player.warmup, daemon=True).start()
        self.client.loop_forever()

    # --- 内部 ---
    def _on_connect(self, client, userdata, flags, reason_code, properties=None) -> None:
        client.publish(f"{TOPIC_PREFIX}/status", "online", retain=True)
        client.publish(
            DISCOVERY_TOPIC,
            json.dumps(discovery_payload(self.entity_name, self.model), ensure_ascii=False),
            retain=True,
        )
        if self.volume.enabled:
            client.publish(
                VOLUME_DISCOVERY_TOPIC,
                json.dumps(
                    volume_discovery_payload(self.entity_name, self.model), ensure_ascii=False
                ),
                retain=True,
            )
            client.subscribe(f"{TOPIC_PREFIX}/volume/set")
        client.subscribe(f"{TOPIC_PREFIX}/set")
        client.subscribe(f"{TOPIC_PREFIX}/say")
        client.publish(f"{TOPIC_PREFIX}/state", self.state, retain=True)
        self._publish_volume(force=True)
        logging.info("discovery 已发布：%s", DISCOVERY_TOPIC)

    def _on_message(self, client, userdata, message) -> None:
        # 必须自己校验主题：amqtt 这个 broker 在投递 retained 消息时不按订阅过滤，
        # 只订阅 bt_speaker/v1/set 也会收到整个 broker 的 retained 消息
        # （实测收到 59 条无关的）。HA 那边订阅的是 homeassistant/# 这种宽通配，
        # 所以一直没暴露这个毛病。
        topic = message.topic
        payload = message.payload.decode("utf-8", "replace").strip()
        if topic == f"{TOPIC_PREFIX}/say":
            if not payload:
                return
            logging.info("收到播报请求：%s", payload)
            try:
                self.player.say(payload)
                self._publish("ON")
            except Exception as error:  # noqa: BLE001 - 播报失败不该让服务退出
                logging.error("播报失败：%s", error)
            return

        if topic != f"{TOPIC_PREFIX}/set":
            if topic == f"{TOPIC_PREFIX}/volume/set":
                try:
                    value = int(round(float(payload)))
                except ValueError:
                    logging.warning("音量命令不是数字：%s", payload)
                    return
                if self.volume.set(value) is not None:
                    self._publish_volume(force=True)
                return
            self._ignored += 1
            if self._ignored in (1, 10, 100):
                logging.warning(
                    "已忽略 %d 条非本服务主题的消息（broker 未按订阅过滤），最近一条：%s",
                    self._ignored,
                    topic,
                )
            return

        logging.info("收到命令：%s", payload)
        if payload == "ON":
            try:
                self.player.play_file(self.player.media, self.player.loop)
                self._publish("ON")
            except Exception as error:  # noqa: BLE001
                logging.error("播放失败：%s", error)
        elif payload == "OFF":
            self.player.stop()

    def _publish(self, state: str) -> None:
        self.state = state
        self.client.publish(f"{TOPIC_PREFIX}/state", state, retain=True)

    def _publish_idle(self) -> None:
        """播放结束或被停止时把状态推回 OFF。"""

        self._publish("OFF")

    def _publish_volume(self, force: bool = False) -> None:
        """把当前音量推给 HA；没变就不发。"""

        current = self.volume.get()
        if current is None:
            return
        if not force and current == self._volume_last:
            return
        self._volume_last = current
        self.client.publish(f"{TOPIC_PREFIX}/volume", str(current), retain=True)

    def _poll_volume(self) -> None:
        """定期同步：你在系统里手动改音量，HA 里也跟着变。"""

        while True:
            time.sleep(self.volume_poll_s)
            try:
                self._publish_volume()
            except Exception as error:  # noqa: BLE001
                logging.warning("同步音量失败：%s", error)


def main() -> int:
    # 日志里有中文和 discovery 原文，Windows 默认的 cp936 会编码失败，
    # 一失败 logging 就打出一大段 Message/Arguments 噪声。强制走 UTF-8。
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    config_path = HERE / "config.yaml"
    if len(sys.argv) > 1:
        config_path = Path(sys.argv[1])
    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}

    audio = config.get("audio") or {}
    media = (HERE / str(audio.get("media") or "media/announce.wav")).resolve()
    if not media.exists():
        make_tone(media)
        logging.info("已生成默认提示音 %s（换成你自己的 WAV 也行）", media)

    Bridge(config).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
