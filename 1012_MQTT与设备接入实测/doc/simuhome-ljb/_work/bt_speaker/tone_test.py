r"""播一段"稳态正弦音"到指定 PortAudio 输出设备，用来做可控的听感测试。

为什么不用 media\announce.wav：那段提示音是衰减音，真正响的只有开头约 1 秒，
音量低的时候很容易被判成"没声音"（`_work\04_蓝牙音箱MQTT桥.md` 10.4 节踩过一次）。
这里改成**幅度恒定、持续若干秒**的正弦音，响不响一目了然，也便于
与此同时用 `meter.py` 读端点峰值做客观对照。

它同时能把系统音量临时调到指定值（用 pycaw），结束后还原，
用来排除"是不是音量太小"这一层。

用法（先 cd 到本目录，或给绝对路径）：
    python tone_test.py                                   # 播到 #4，4 秒，660Hz，30% 幅度
    python tone_test.py --device 10 --seconds 6           # 换一档 Host API
    python tone_test.py --volume 100 --amplitude 0.25     # 临时把系统音量拉到 100%（结束还原）
    python tone_test.py --device 4 --dry-metadata         # 不播，只打印将要用到的设备信息

按名字选设备（不想手查索引时用，矩阵测试就是靠它）：
    python tone_test.py --name btha2dp --rate 48000       # 直通驱动那一档（WDM-KS）
    python tone_test.py --name SAB6 --beeps 2             # 名字含 SAB6，2 声，便于分辨听到了哪一路
    python tone_test.py --name bthhfenum --include-handsfree --beeps 4

`--beeps N` 播 N 声短音（0.4 秒响 + 0.25 秒静），用来让每一路"自报家门"：
听的人只要数听到几声，就知道是哪一路通了，不用记顺序。

依赖：sounddevice、numpy、pycaw（只有 --volume 时才需要）
"""

from __future__ import annotations

import argparse
import sys
import time

import numpy as np
import sounddevice as sd


def device_label(index: int) -> str:
    """取设备名的简短描述，用于日志里确认播到了哪一档。"""

    try:
        info = sd.query_devices(index)
        host = sd.query_hostapis(info["hostapi"])["name"]
        return f"#{index} [{host}] {str(info['name'])[:50]}"
    except Exception as error:  # noqa: BLE001
        return f"#{index}（查询失败：{error}）"


def find_output(substr: str, rate: int, include_handsfree: bool) -> int:
    """按名字子串找第一个"真能打开"的输出设备索引。

    光比名字不够：同一个蓝牙音箱会在 MME / DirectSound / WASAPI / WDM-KS 各出现一次，
    其中有些打不开，所以逐个用 check_output_settings 验。
    免提档（Hands-Free / bthhfenum）默认跳过，除非显式要测它。
    """

    import sounddevice as sd

    usable = []
    for index, device in enumerate(sd.query_devices()):
        if device["max_output_channels"] <= 0:
            continue
        name = str(device["name"])
        if substr.lower() not in name.lower():
            continue
        lowered = name.lower()
        if not include_handsfree and ("hands-free" in lowered or "bthhfenum" in lowered):
            continue
        try:
            sd.check_output_settings(device=index, samplerate=rate, channels=2)
        except Exception:  # noqa: BLE001 - 打不开就换下一个
            continue
        usable.append(index)
    if not usable:
        raise SystemExit(f"没有名字含 {substr!r} 且能打开的 2 声道输出设备（rate={rate}）")
    return usable[0]


def set_volume(percent: int | None) -> int | None:
    """把系统默认输出音量设成 percent%；返回旧值（用于还原）。没装 pycaw 返回 None。"""

    if percent is None:
        return None
    from pycaw.pycaw import AudioUtilities

    endpoint = AudioUtilities.GetSpeakers().EndpointVolume
    old = round(endpoint.GetMasterVolumeLevelScalar() * 100)
    endpoint.SetMasterVolumeLevelScalar(max(0, min(100, percent)) / 100.0, None)
    return old


def restore_volume(old: int | None) -> None:
    """把音量还原成测试前的值。"""

    if old is None:
        return
    from pycaw.pycaw import AudioUtilities

    AudioUtilities.GetSpeakers().EndpointVolume.SetMasterVolumeLevelScalar(
        old / 100.0, None
    )
    print(f"  音量已还原为 {old}%")


def main() -> int:
    """解析参数，生成稳态正弦并播出去；结束后还原音量。"""

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--device", type=int, default=4, help="PortAudio 输出设备索引")
    parser.add_argument("--name", default=None, help="按名字子串选设备（优先于 --device）")
    parser.add_argument(
        "--include-handsfree", action="store_true", help="允许选中免提档（bthhfenum）"
    )
    parser.add_argument("--seconds", type=float, default=4.0, help="时长（秒）")
    parser.add_argument("--freq", type=float, default=660.0, help="音高（Hz）")
    parser.add_argument("--amplitude", type=float, default=0.3, help="幅度 0~1")
    parser.add_argument("--rate", type=int, default=44100, help="采样率")
    parser.add_argument("--beeps", type=int, default=1, help="播几声短音（>1 时方便分辨是哪一路）")
    parser.add_argument("--tag", default="", help="标签，仅用于日志里区分几路测试")
    parser.add_argument("--volume", type=int, default=None, help="临时设系统音量，结束还原")
    parser.add_argument("--dry-metadata", action="store_true", help="只打印设备信息，不播")
    args = parser.parse_args()

    index = args.device
    if args.name:
        index = find_output(args.name, args.rate, args.include_handsfree)
    tag = f"[{args.tag}] " if args.tag else ""
    print(f"{tag}目标设备：{device_label(index)}")
    if args.dry_metadata:
        return 0

    old_volume = set_volume(args.volume)
    if args.volume is not None:
        print(f"  系统音量临时设为 {args.volume}%（原 {old_volume}%）")

    if args.beeps > 1:
        # N 声"哔"：每声 0.4 秒，间隔 0.25 秒；听的人只要数几声就知道是哪一路
        on = int(args.rate * 0.4)
        off = int(args.rate * 0.25)
        pieces = []
        for _ in range(args.beeps):
            pieces.append(np.ones(on))
            pieces.append(np.zeros(off))
        envelope = np.concatenate(pieces)
    else:
        envelope = np.ones(int(args.rate * args.seconds))
    total = len(envelope)
    t = np.arange(total) / args.rate
    # 首尾各 20ms 淡入淡出，避免爆音；中间是恒定幅度，方便判断"到底响不响"
    wave = args.amplitude * np.sin(2 * np.pi * args.freq * t) * envelope
    ramp = max(1, int(args.rate * 0.02))
    wave[:ramp] *= np.linspace(0, 1, ramp)
    wave[-ramp:] *= np.linspace(1, 0, ramp)
    stereo = np.repeat(wave.astype("float32")[:, None], 2, axis=1)

    try:
        started = time.monotonic()
        sd.play(stereo, args.rate, device=index)
        described = (
            f"{args.freq:.0f}Hz 稳态音 {args.seconds:.1f}s"
            if args.beeps <= 1
            else f"{args.beeps} 声 {args.freq:.0f}Hz 短音"
        )
        print(f"  正在播放 {described} ……")
        sd.wait()
        print(f"  播放结束，耗时 {time.monotonic() - started:.2f} 秒")
    finally:
        restore_volume(old_volume)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
