r"""探 pycaw 的 API 形状：读默认输出设备的音量，并试写一次。

pycaw 各版本取 IAudioEndpointVolume 的方式不同，先把能用的那条路记下来。
"""

from pycaw.pycaw import AudioUtilities


def main() -> int:
    device = AudioUtilities.GetSpeakers()
    print("GetSpeakers() ->", type(device).__name__)
    for name in ("EndpointVolume", "Activate", "QueryInterface"):
        print(f"  有 {name}: {hasattr(device, name)}")

    volume = None
    if hasattr(device, "EndpointVolume"):
        volume = device.EndpointVolume
        print("走 device.EndpointVolume")
    else:
        from comtypes import CLSCTX_ALL

        from pycaw.api.endpointvolume import IAudioEndpointVolume

        interface = device.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume = interface.QueryInterface(IAudioEndpointVolume)
        print("走 Activate + QueryInterface")

    current = volume.GetMasterVolumeLevelScalar()
    print(f"当前音量 = {current:.3f}")
    print(f"是否静音 = {bool(volume.GetMute())}")
    print("设置 API:", [name for name in dir(volume) if "Master" in name or "Mute" in name])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
