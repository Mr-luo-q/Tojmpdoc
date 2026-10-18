r"""读每个输出端点的峰值电平，客观判断"音频到底有没有被渲染到音箱那一路"。

背景：桥打日志"开始播放"、Windows 音频会话是 Active，这两件事都只说明
"有一个音频流开着"，不等于声音真的进了音箱。Windows 的 IAudioMeterInformation
暴露每个输出端点当前正在被渲染的峰值，读它就能把问题切成两半：

  某个端点峰值 > 0    Windows 确实在往这个端点送样本（问题在端点之后：蓝牙传输、音箱本身）
  所有端点峰值 = 0    没有音频在渲染（问题在 Windows 之前：流没起来或被静音）

默认输出端点排在第一个，逐行打印"端点名 / 峰值 / 静态时基线"。

用法：
    python _work\bt_speaker\meter.py             # 采样 6 秒，每 0.25 秒打一次当前最大值
    python _work\bt_speaker\meter.py 12          # 采样 12 秒

依赖：pycaw、comtypes
"""

from __future__ import annotations

import sys
import time
from ctypes import HRESULT, POINTER, c_float, c_uint

import comtypes
from comtypes import COMMETHOD, GUID, IUnknown
from pycaw.pycaw import AudioUtilities


class IAudioMeterInformation(IUnknown):
    """Windows 的音频端点电平表接口（MMDevice API 的一部分，pycaw 没带，这里自带）。"""

    _iid_ = GUID("{C02216F6-8C67-4B5B-9D00-D008E73E0064}")
    _methods_ = (
        COMMETHOD([], HRESULT, "GetPeakValue", (["out"], POINTER(c_float), "peak")),
        COMMETHOD(
            [], HRESULT, "GetMeteringChannelCount", (["out"], POINTER(c_uint), "count")
        ),
        COMMETHOD(
            [],
            HRESULT,
            "GetChannelsPeakValues",
            (["in"], c_uint, "channels"),
            (["out"], POINTER(c_float), "values"),
        ),
        COMMETHOD(
            [], HRESULT, "QueryHardwareSupport", (["out"], POINTER(c_uint), "mask")
        ),
    )


def open_meter(device) -> IAudioMeterInformation | None:
    """在某个 AudioDevice 上打开电平表；打不开返回 None（不参与比较）。"""

    try:
        interface = device._dev.Activate(
            IAudioMeterInformation._iid_, comtypes.CLSCTX_ALL, None
        )
        return interface.QueryInterface(IAudioMeterInformation)
    except Exception:  # noqa: BLE001 - 个别端点没有电平表是正常的
        return None


def render_endpoints() -> list[tuple[str, IAudioMeterInformation]]:
    """收集所有"当前可用"的输出端点及其电平表，默认输出排在最前面。

    pycaw 的 GetAllDevices() 会把未插入（unplugged）的端点也列出来，
    用 state == 1（DEVICE_STATE_ACTIVE）过滤掉它们，避免噪声。
    """

    default_name = ""
    try:
        default_name = AudioUtilities.GetSpeakers().FriendlyName or ""
    except Exception:  # noqa: BLE001
        pass

    found: list[tuple[str, IAudioMeterInformation]] = []
    for device in AudioUtilities.GetAllDevices():
        if not str(device.id).startswith("{0.0.0."):  # 0.0.0 = render
            continue
        # pycaw 的 state 是 AudioDeviceState 枚举（不是 IntEnum），取 .value 再比
        state = getattr(device, "state", 1)
        if getattr(state, "value", state) != 1:  # 1 = ACTIVE
            continue
        meter = open_meter(device)
        if meter is None:
            continue
        found.append((device.FriendlyName or "?", meter))
    found.sort(key=lambda item: 0 if item[0] == default_name else 1)
    return found


def peak(meter: IAudioMeterInformation) -> float:
    """读一次峰值（0.0~1.0）；读失败当 0。"""

    try:
        return float(meter.GetPeakValue())
    except Exception:  # noqa: BLE001
        return 0.0


def main() -> int:
    """采样若干秒，打印每个端点见过的最大峰值。"""

    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
    endpoints = render_endpoints()
    if not endpoints:
        print("没有可用的输出端点（或者都打不开电平表）")
        return 1

    default_name = endpoints[0][0]
    print(f"默认输出 = {default_name}")
    print(f"采样 {seconds:.1f} 秒，逐端点记录最大峰值（0.000 = 完全没收到音频）\n")

    maxima = [0.0] * len(endpoints)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        for index, (_, meter) in enumerate(endpoints):
            value = peak(meter)
            if value > maxima[index]:
                maxima[index] = value
        time.sleep(0.05)

    for (name, _), value in zip(endpoints, maxima):
        mark = " ← 默认输出" if name == default_name else ""
        bar = "#" * int(round(value * 40))
        print(f"  {value:.3f}  {bar:<40}  {name[:52]}{mark}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
