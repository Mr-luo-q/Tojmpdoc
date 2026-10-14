r"""找出 sounddevice 里"真能打开"的输出设备，特别是那台蓝牙音箱。

背景：直接拿 sd.query_devices() 里的索引去 sd.play(device=...) 会报
Invalid device [PaErrorCode -9996]——所以索引必须用 check_output_settings 验过。

用法：python _work\bt_speaker\probe_devices.py [名字子串]
"""

import sys

import sounddevice as sd

PATTERN = sys.argv[1] if len(sys.argv) > 1 else "SAB6"


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    hostapis = {index: api["name"] for index, api in enumerate(sd.query_hostapis())}
    default_out = sd.default.device[1]
    print(f"默认输出设备索引 = {default_out}")

    print(f"\n== 名字含 {PATTERN!r} 的输出设备 ==")
    for index, device in enumerate(sd.query_devices()):
        if device["max_output_channels"] <= 0:
            continue
        if PATTERN.lower() not in str(device["name"]).lower():
            continue
        api = hostapis.get(device["hostapi"], "?")
        usable = []
        for rate in (44100, 48000):
            try:
                sd.check_output_settings(device=index, samplerate=rate, channels=2)
                usable.append(rate)
            except Exception:  # noqa: BLE001
                pass
        print(
            f"  #{index:<3} [{api}] ch={device['max_output_channels']} "
            f"default_rate={device['default_samplerate']:.0f} 可用率={usable or '无'}"
        )
        print(f"        {str(device['name'])[:80]}")

    print("\n== 逐个试播（0.4 秒静音）==")
    for index, device in enumerate(sd.query_devices()):
        if device["max_output_channels"] <= 0:
            continue
        if PATTERN.lower() not in str(device["name"]).lower():
            continue
        for rate in (48000, 44100):
            try:
                import numpy as np

                silence = np.zeros((int(rate * 0.4), 2), dtype="<i2")
                sd.play(silence, rate, device=index)
                sd.wait()
                print(f"  #{index} @ {rate} 播放成功")
                break
            except Exception as error:  # noqa: BLE001
                print(f"  #{index} @ {rate} 失败：{error}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
