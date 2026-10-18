r"""连到美的蓝牙温湿度计，枚举它的 GATT 服务与特征，并尝试读所有"可读"特征。

为什么写它：这台设备在广播里只发自己的 MAC 与序列号，不带温湿度，
而且载荷全程不变（见 11 号报告第 4.4 节）。要回答"数据到底能不能读出来"，
唯一办法是主动连上去看它有没有对外暴露可读特征：
  有可读特征且数值会变  → 能接，按特征格式写解析即可
  只有需要加密/配对的特征 → 要绑密钥，成本高一个量级
  连都连不上（只认自家 App）→ 判定不值得做

用法（在树莓派上跑）：
    python3 midea_probe.py                                  # 默认连已知那台
    python3 midea_probe.py --address AA:BB:CC:DD:EE:FF --timeout 40

只读：只做"枚举 + 读"，不写任何特征，也不做配对。
"""

import argparse
import asyncio
import sys

from bleak import BleakClient

# 标准服务 UUID，命中时值得优先看
ENV_SENSING = "0000181a-0000-1000-8000-00805f9b34fb"
BATTERY = "0000180f-0000-1000-8000-00805f9b34fb"

DEFAULT_ADDRESS = "50:5E:3A:E9:93:2C"


def hex_or_none(value) -> str:
    """把读回来的字节压成十六进制字符串，空值原样显示。"""

    if value is None:
        return "None"
    return bytes(value).hex(" ")


async def probe(address: str, timeout: float, window: float, interval: float) -> int:
    """连上设备，列出全部服务与特征，并把可读特征逐个读一遍。

    这类设备只在被唤醒时短暂广播，所以连不上就等一会再试，直到窗口用完。
    """

    client = BleakClient(address, timeout=timeout)
    deadline = asyncio.get_event_loop().time() + window
    attempt = 0
    while True:
        attempt += 1
        print(f"[第 {attempt} 次] 连接 {address} ……", flush=True)
        try:
            await client.connect()
            break
        except Exception as error:
            left = int(deadline - asyncio.get_event_loop().time())
            print(f"    连不上：{type(error).__name__}: {error}（剩余 {left} 秒，等 {interval:.0f} 秒重试）",
                  flush=True)
            if left <= 0:
                print("窗口用完，放弃。")
                return 1
            await asyncio.sleep(interval)

    print(f"已连接：{client.is_connected}")
    services = list(client.services)
    print(f"服务数：{len(services)}")
    print("")

    readable = []
    for service in services:
        mark = "  <== 标准环境感知" if service.uuid.lower() == ENV_SENSING else ""
        print(f"[服务] {service.uuid}  {getattr(service, 'description', '')}{mark}")
        for characteristic in service.characteristics:
            props = ",".join(characteristic.properties)
            print(f"    [特征] {characteristic.uuid}  ({props})")
            if "read" in characteristic.properties:
                readable.append(characteristic)
        print("")

    print(f"可读特征共 {len(readable)} 个，逐个读：")
    for characteristic in readable:
        try:
            raw = await client.read_gatt_char(characteristic)
            text = hex_or_none(raw)
            hint = ""
            if characteristic.uuid.lower() == BATTERY:
                hint = f"  → 电量 {int.from_bytes(bytes(raw), 'little')}%"
            print(f"    {characteristic.uuid}  =  {text}{hint}")
        except Exception as error:
            print(f"    {characteristic.uuid}  读取失败：{type(error).__name__}: {error}")

    await client.disconnect()
    print("")
    print("已断开。")
    return 0


def main() -> int:
    """收参数，跑一次探测。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--address", default=DEFAULT_ADDRESS)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--window", type=float, default=60.0, help="整段等待窗口的秒数")
    parser.add_argument("--interval", type=float, default=8.0, help="两次重试之间等多久")
    options = parser.parse_args()
    return asyncio.run(probe(options.address, options.timeout, options.window, options.interval))


if __name__ == "__main__":
    raise SystemExit(main())
