r"""边扫边看：只打印"新出现"的设备，方便在按设备按钮的那一刻抓到它。

为什么单独写一个：scan.py 一次会打出上百台设备的广播，噪声太大。
很多 BLE 传感器只在状态变化或按下按钮时才广播，所以要"守着看"。

用法（先运行它，然后去按传感器上的按钮，或把电池取出来再装回去）：
    python _work\ble\watch.py          # 默认守 60 秒
    python _work\ble\watch.py 120      # 守 120 秒

只读：不连接、不配对。
"""

import asyncio
import sys
import time

from bleak import BleakScanner

# 与 scan.py 保持一致的两条启发式
SENSOR_HINTS = ("LYWSD", "MJ_HT", "MJWSD", "ATC_", "Thermo", "Temp", "Humid",
                "CGG", "MHO-C", "XMWSDJ", "TH-", "SHT", "midea")
ENV_SERVICE = "0000181a-0000-1000-8000-00805f9b34fb"

SKIP_SECONDS = 8.0        # 前几秒当作基线，之后出现的才算新设备


def interesting(name, uuids):
    """名字命中片段、或广播里带环境感知服务，就算值得看。"""

    if name and any(hint.lower() in name.lower() for hint in SENSOR_HINTS):
        return True
    return any(u.lower() == ENV_SERVICE for u in uuids)


def describe(device, adv):
    """把一台设备压成一段可读的多行文本。"""

    value = getattr(adv, "rssi", None)
    rssi = value if value is not None else getattr(device, "rssi", None)
    lines = [f"{device.address}  rssi={rssi}  name={adv.local_name or device.name!r}"]
    if adv.service_uuids:
        lines.append("     服务: " + ", ".join(adv.service_uuids))
    for company, payload in (adv.manufacturer_data or {}).items():
        lines.append(f"     厂商: 0x{company:04x}  {payload[:20].hex(' ')}")
    return "\n".join(lines)


async def main():
    """两阶段：先扫基线，再只报基线之外新出现的设备。"""

    total = float(sys.argv[1]) if len(sys.argv) > 1 else 60.0
    print(f"1/2 建基线：先安静扫 {SKIP_SECONDS:.0f} 秒……")
    # 同样用回调收，不用 discover(return_adv=True)——那个 API 的形状随版本变
    baseline = set()

    def on_baseline(device, adv):
        """基线阶段只记地址，不做判断。"""

        baseline.add(device.address)

    async with BleakScanner(detection_callback=on_baseline):
        await asyncio.sleep(SKIP_SECONDS)
    print(f"     基线里 {len(baseline)} 台设备。")
    print(f"2/2 现在开始守 {total:.0f} 秒 —— 去按传感器上的按钮，或把电池取出再装回去。")
    print("     下面只列基线之外的设备。")
    print("")

    seen: dict = {}

    def on_detect(device, adv):
        """每收到一次广播调一次；只报基线之外的设备与命中启发式的设备。"""

        first = seen.get(device.address)
        if first is None:
            seen[device.address] = time.monotonic()
        uuids = list(adv.service_uuids or [])
        name = adv.local_name or device.name
        fresh = (first is None) and (device.address not in baseline)
        if fresh or interesting(name, uuids):
            tag = "新出现" if fresh else "命中启发式"
            print(f"[{tag}] " + describe(device, adv))
            print("")

    async with BleakScanner(detection_callback=on_detect):
        await asyncio.sleep(total)

    print(f"结束：总共看到 {len(seen)} 台设备的广播。")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
