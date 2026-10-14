r"""看 bleak 的 discover() 在这台机器上到底返回什么形状。

背景：scan.py 在 Windows 上拿到的是 dict {address: (device, adv)}，
在树莓派的 bleak 0.11.0 上却是 list，直接 .items() 会 AttributeError。
这个探针把版本、函数签名、返回类型与元素形状一次打出来，用来决定怎么写兼容分支。

用法：python3 probe_api.py
"""

import asyncio
import inspect

import bleak
from bleak import BleakScanner


def describe(found):
    """打印返回值的类型与第一个元素的样子。"""

    print("返回类型:", type(found).__name__)
    if isinstance(found, dict):
        if not found:
            print("（空字典）")
            return
        key = next(iter(found))
        print("键样例:", key)
        print("值类型:", type(found[key]).__name__)
        print("值内容:", repr(found[key])[:220])
        return
    print("长度:", len(found))
    if not found:
        print("（空列表）")
        return
    first = found[0]
    print("元素类型:", type(first).__name__)
    print("元素内容:", repr(first)[:220])
    if isinstance(first, (tuple, list)) and len(first) >= 2:
        print("  第 0 个:", type(first[0]).__name__)
        print("  第 1 个:", type(first[1]).__name__)


async def main():
    """打印版本与签名，再实际扫一次看形状。"""

    print("bleak 版本:", getattr(bleak, "__version__", "?"))
    try:
        print("discover 签名:", inspect.signature(BleakScanner.discover))
    except (TypeError, ValueError) as error:
        print("取签名失败:", error)
    found = await BleakScanner.discover(timeout=6, return_adv=True)
    describe(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
