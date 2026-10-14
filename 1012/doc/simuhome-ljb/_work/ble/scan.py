r"""扫一遍周围的 BLE 广播，看看有哪些设备、里面有没有温湿度计。

为什么需要它：HA 跑在 Docker 的 Linux VM 里，拿不到 Windows 的蓝牙适配器
（见 _work\04_蓝牙音箱MQTT桥.md 第 1 节）。所以想接 BLE 设备，只能在本机 Windows
这一侧读，再经 MQTT 转给 HA——和蓝牙音箱桥同一条思路。

BLE 温湿度计大多是广播型：读数直接写在广播包里，不需要建立 GATT 连接。
也就是说手机 App 连着它，并不妨碍我们被动接收；这个脚本验证的正是这件事。

用法：
    python _work\ble\scan.py           # 默认扫 12 秒
    python _work\ble\scan.py 20        # 扫 20 秒

只读：不连接、不配对、不写任何设备。
"""

import asyncio
import sys

from bleak import BleakScanner

# 名字里出现这些片段，多半就是温湿度计（覆盖米家、青萍、ATC 等常见固件）
SENSOR_HINTS = ("LYWSD", "MJ_HT", "MJWSD", "ATC_", "Thermo", "Temp", "Humid",
                "CGG", "MHO-C", "XMWSDJ", "TH-", "SHT")

# 蓝牙标准里的环境感知服务；广播里带它基本就是温湿度或气压类设备
ENV_SERVICE = "0000181a-0000-1000-8000-00805f9b34fb"


def looks_like_sensor(name, uuids):
    """按名字片段与标准服务 UUID 猜它是不是温湿度计。"""

    if name and any(hint.lower() in name.lower() for hint in SENSOR_HINTS):
        return True
    return any(uuid.lower() == ENV_SERVICE for uuid in uuids)


def rssi_of(device, adv):
    """取信号强度：新 bleak 放在 AdvertisementData 上，0.11.0 放在 BLEDevice 上。"""

    value = getattr(adv, "rssi", None)
    return value if value is not None else getattr(device, "rssi", None)


def hex_preview(data, limit=24):
    """把字节串打成长度受限的十六进制，够看清结构就行。"""

    text = data[:limit].hex(" ")
    return text + (" ..." if len(data) > limit else "")


async def main():
    """扫一段时间的广播，逐台打印，并标出疑似温湿度计。"""

    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 12.0
    print(f"扫描 {seconds:.0f} 秒 ...（只读，不连接任何设备）")

    # 用 detection_callback 收广播，而不是 discover(return_adv=True)：
    # 后者的语义随 bleak 版本变（新版返回 dict，0.11.0 直接忽略 return_adv、
    # 只返回一堆没有广播数据的 BLEDevice），回调那套在两边都成立。
    seen = {}

    def on_detect(device, adv):
        """每收到一次广播就覆盖这台设备的最新记录。"""

        seen[device.address] = (device, adv)

    async with BleakScanner(detection_callback=on_detect):
        await asyncio.sleep(seconds)

    rows = []
    for address, pair in seen.items():
        device, adv = pair
        uuids = list(adv.service_uuids or [])
        name = adv.local_name or device.name
        rows.append(
            {
                "address": address,
                "name": name,
                "rssi": rssi_of(device, adv),
                "uuids": uuids,
                "manufacturer": adv.manufacturer_data or {},
                "service_data": adv.service_data or {},
                "sensor": looks_like_sensor(name, uuids),
            }
        )
    rows.sort(key=lambda item: (-int(item["sensor"]), -(item["rssi"] or -999)))

    print(f"\n共收到 {len(rows)} 台设备的广播\n")
    for item in rows:
        mark = "  <== 疑似温湿度计" if item["sensor"] else ""
        print(f"{item['address']}  rssi={item['rssi']}  name={item['name']!r}{mark}")
        if item["uuids"]:
            print(f"    服务 UUID: {', '.join(item['uuids'])}")
        for company, payload in item["manufacturer"].items():
            print(f"    厂商数据 company=0x{company:04x}  {hex_preview(payload)}")
        for uuid, payload in item["service_data"].items():
            print(f"    服务数据 {uuid}  {hex_preview(payload)}")

    sensors = [item for item in rows if item["sensor"]]
    print(f"\n结论：疑似温湿度计 {len(sensors)} 台")
    for item in sensors:
        print(f"  {item['address']}  {item['name']!r}")
    if not sensors:
        print("  没扫到。确认设备在附近、并且正在广播（有的固件被 App 连着时会停广播）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
