r"""把 announce.wav 播到指定的 PortAudio 输出设备，用来判断哪个 Host API 真能出声。

为什么需要：同一个蓝牙音箱在 PortAudio 里会以四种 Host API 各出现一次
（MME / DirectSound / WASAPI / WDM-KS）。桥的选法是"名字匹配 + 能打开就取第一个"，
所以它锁在索引最小的 MME 那一档。但"能打开"不等于"声音真出得去"，
这里就把同一段音频依次播到几个索引上，用耳朵分辨。

用法（先 cd 到本目录）：
    python play_to.py            # 只列出 SAB6 相关的输出索引
    python play_to.py 4 10 13    # 依次播到这些索引，每播一次停 1 秒
"""

import os
import sys
import time
import wave

import numpy as np
import sounddevice as sd

DEFAULT_PATTERN = "SAB6"  # 默认按这个子串筛设备；用 --name 可以换成别的
MEDIA = "media/announce.wav"


def list_candidates(pattern: str):
    """列出名字里含 pattern 的输出索引，以及各自的 Host API 与可用采样率。"""

    hostapis = {i: api["name"] for i, api in enumerate(sd.query_hostapis())}
    print(f"默认输出索引 = {sd.default.device[1]}")
    print(f"名字含 {pattern!r} 的输出设备：")
    for index, device in enumerate(sd.query_devices()):
        if device["max_output_channels"] <= 0:
            continue
        if pattern.lower() not in str(device["name"]).lower():
            continue
        usable = []
        for rate in (44100, 48000):
            try:
                sd.check_output_settings(device=index, samplerate=rate, channels=2)
                usable.append(rate)
            except Exception:  # noqa: BLE001
                pass
        api = hostapis.get(device["hostapi"], "?")
        print(f"  #{index:<3} [{api}] 可用率={usable or '无'}  {str(device['name'])[:60]}")


def load_audio():
    """把 WAV 读成 (float 采样数组, 采样率)，供 sd.play 使用。"""

    with wave.open(MEDIA, "rb") as handle:
        channels = handle.getnchannels()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    data = np.frombuffer(frames, dtype="<i2").astype("float32") / 32768.0
    return data.reshape(-1, channels), rate


def resample(data, src_rate: int, dst_rate: int):
    """把采样数组线性重采样到目标采样率。

    只用于试播提示音：线性插值够听出"有没有声音"，不做抗混叠。
    加它的原因：WASAPI 那一档只接受设备默认采样率（48000），
    素材是 44100 时会直接报 Invalid sample rate，连试都试不了。
    """

    if src_rate == dst_rate:
        return data
    count = max(1, int(len(data) * dst_rate / src_rate))
    src_x = np.arange(len(data))
    dst_x = np.linspace(0, len(data) - 1, count)
    channels = [
        np.interp(dst_x, src_x, data[:, channel]) for channel in range(data.shape[1])
    ]
    return np.stack(channels, axis=1).astype("float32")


def play(index: int, data, rate: int) -> None:
    """播一次到指定索引并计时；失败只提示不中断，方便一次试多个。

    计时是有用的信号：真的播完 2.5 秒素材，耗时就该在 2.5 秒上下；
    如果瞬间返回，说明设备收下了流却没真的播。
    """

    label = str(sd.query_devices(index)["name"])[:50]
    print(f"\n播到 #{index}  {label} ……", flush=True)
    started = time.monotonic()
    try:
        sd.play(data, rate, device=index)
        sd.wait()
        print(f"  播放调用返回，耗时 {time.monotonic() - started:.2f} 秒")
    except Exception as error:  # noqa: BLE001
        print(f"  失败（{time.monotonic() - started:.2f} 秒）：{type(error).__name__}: {error}")


def main():
    """没有参数就只列设备；有参数就依次播到那些索引。"""

    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    pattern = DEFAULT_PATTERN
    target_rate = None
    for item in sys.argv[1:]:
        if item.startswith("--name="):
            pattern = item.split("=", 1)[1]
        elif item.startswith("--rate="):
            target_rate = int(item.split("=", 1)[1])
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    list_candidates(pattern)
    if not args:
        print("\n（没给索引，只列设备。要试播就带上索引，例如：python play_to.py 4 10 13）")
        return 0

    data, rate = load_audio()
    print(f"\n音频：{MEDIA}  {len(data) / rate:.2f} 秒  采样率 {rate}")
    if target_rate:
        data = resample(data, rate, target_rate)
        print(f"已重采样到 {target_rate} Hz（某些 Host API 只吃设备默认采样率）")
    for raw in args:
        play(int(raw), data, target_rate or rate)
        time.sleep(1.0)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
