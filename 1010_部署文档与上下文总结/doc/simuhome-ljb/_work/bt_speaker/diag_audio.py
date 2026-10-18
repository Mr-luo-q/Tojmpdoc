r"""诊断音频链路：默认输出设备是谁、音量多少、有没有静音，并直接放一次 announce.wav。

用法：
  python _work\bt_speaker\diag_audio.py            # 只看设备与音量，放一次
  python _work\bt_speaker\diag_audio.py 60 3      # 先把音量调到 60%，再连放 3 次
"""

from pathlib import Path
import sys

from pycaw.pycaw import AudioUtilities

HERE = Path(__file__).resolve().parent
MEDIA = HERE / "media" / "announce.wav"


def main() -> int:
    # 设备名里有非 GBK 字符（比如上标），Windows 控制台默认编码会炸
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    print("== 所有音频设备（render = 输出）==")
    for device in AudioUtilities.GetAllDevices():
        kind = "render" if device.id.startswith("{0.0.0.") else "capture"
        print(f"  [{kind}] {device.FriendlyName}")

    speaker = AudioUtilities.GetSpeakers()
    print("\n== 默认输出设备 ==")
    print(f"  {speaker.FriendlyName}")
    volume = speaker.EndpointVolume
    level = volume.GetMasterVolumeLevelScalar()
    muted = bool(volume.GetMute())
    print(f"  音量 = {level:.3f}（{round(level * 100)}%）  静音 = {muted}")

    times = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    if len(sys.argv) > 1:
        target = max(0, min(100, int(sys.argv[1])))
        volume.SetMasterVolumeLevelScalar(target / 100.0, None)
        print(f"\n  已把音量调到 {target}%")

    print("\n== 试放 ==")
    print(f"  文件：{MEDIA}  存在={MEDIA.exists()}")
    if not MEDIA.exists():
        print("  文件不存在，桥会在启动时重新生成")
        return 1
    import winsound

    for index in range(times):
        winsound.PlaySound(str(MEDIA), winsound.SND_FILENAME)
        print(f"  第 {index + 1}/{times} 次播放完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
