r"""订阅美的温湿度计的通知，看它会不会主动把数据推过来。

为什么写它：midea_probe.py 已经确认这台设备能连、能读（不用配对），
但它对外只暴露三个厂商服务，每个都是一对"read,write + read,indicate"特征，
直接读全是 0。数据要么靠订阅通知推过来，要么靠写命令去问。
这一步只做前者——订阅 + 定时重读，看数值会不会变。

用法（在树莓派上跑）：
    python3 midea_listen.py                      # 默认窗口 300 秒、听 90 秒
    python3 midea_listen.py --window 900 --duration 120

只读：只订阅与读取，不写任何特征（写命令那条留到确认必要之后再说）。
"""

import argparse
import asyncio
import datetime
from collections import Counter

from bleak import BleakClient

DEFAULT_ADDRESS = "50:5E:3A:E9:93:2C"


def stamp() -> str:
    """当前时间，精确到毫秒，用来给通知打时间戳。"""

    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def make_handler(uuid: str, counter: Counter):
    """给某个特征造一个回调：把收到的每一条原样打出来。"""

    def handler(_sender, data):
        counter[uuid] += 1
        payload = bytes(data)
        print(f"[{stamp()}] {uuid.split('-')[0]}  {payload.hex(' ')}  (len={len(payload)})", flush=True)

    return handler


async def listen(address: str, window: float, duration: float, interval: float) -> int:
    """连上设备、订阅所有可通知特征，然后一边等通知一边定时重读可读特征。"""

    client = BleakClient(address, timeout=window)
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
            print(f"    连不上：{type(error).__name__}（剩余 {left} 秒）", flush=True)
            if left <= 0:
                return 1
            await asyncio.sleep(interval)

    print(f"已连接：{client.is_connected}", flush=True)

    counter = Counter()
    notifiable = []
    readable = []
    for service in client.services:
        for characteristic in service.characteristics:
            props = set(characteristic.properties)
            if props & {"notify", "indicate"}:
                notifiable.append(characteristic)
            if "read" in props:
                readable.append(characteristic)

    for characteristic in notifiable:
        try:
            await client.start_notify(characteristic, make_handler(characteristic.uuid, counter))
            print(f"订阅成功 {characteristic.uuid}  {sorted(characteristic.properties)}", flush=True)
        except Exception as error:
            print(f"订阅失败 {characteristic.uuid}：{type(error).__name__}: {error}", flush=True)

    print("", flush=True)
    print(f"开始听 {duration:.0f} 秒，同时每 {interval:.0f} 秒重读一次可读特征……", flush=True)

    end = asyncio.get_event_loop().time() + duration
    last = {}
    round_no = 0
    while asyncio.get_event_loop().time() < end:
        await asyncio.sleep(interval)
        round_no += 1
        for characteristic in readable:
            if characteristic.uuid.startswith("00002a"):   # 标准信息特征不会变，跳过
                continue
            try:
                raw = bytes(await client.read_gatt_char(characteristic))
            except Exception as error:
                print(f"    重读 {characteristic.uuid.split('-')[0]} 失败：{type(error).__name__}", flush=True)
                continue
            if last.get(characteristic.uuid) != raw:
                last[characteristic.uuid] = raw
                print(f"[{stamp()}] 第 {round_no} 轮重读 {characteristic.uuid.split('-')[0]} 变了："
                      f"{raw.hex(' ')}", flush=True)

    print("", flush=True)
    print("通知统计：")
    if counter:
        for uuid, count in counter.items():
            print(f"  {uuid}  {count} 条")
    else:
        print("  一条通知都没收到")

    await client.disconnect()
    print("已断开。")
    return 0


def main() -> int:
    """收参数，跑一次订阅监听。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--address", default=DEFAULT_ADDRESS)
    parser.add_argument("--window", type=float, default=300.0, help="等待设备出现的总窗口秒数")
    parser.add_argument("--duration", type=float, default=90.0, help="连上之后听多久")
    parser.add_argument("--interval", type=float, default=15.0, help="重读可读特征的间隔与重连间隔")
    options = parser.parse_args()
    return asyncio.run(listen(options.address, options.window, options.duration, options.interval))


if __name__ == "__main__":
    raise SystemExit(main())
