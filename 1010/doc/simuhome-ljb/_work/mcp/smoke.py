r"""用 MCP 客户端连本机 server，跑一遍只读冒烟：列工具 + observe_home + inspect_device。

用法：python _work\mcp\smoke.py [device_id]
默认 device_id 是米家冰箱的 cn_911432173（见 _work\mcp\data\device_aliases.yaml）。
只读，不下发任何控制命令。
"""

import asyncio
import json
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TOKEN = (ROOT / "_secrets" / "ha_token.txt").read_text(encoding="utf-8").strip()

DEVICE_ID = sys.argv[1] if len(sys.argv) > 1 else "cn_911432173"


def show(title: str, result) -> None:
    """打印一次工具调用的结果。"""

    print(f"\n== {title} ==")
    if getattr(result, "isError", False):
        print("调用失败")
    for block in result.content:
        text = getattr(block, "text", None)
        if text is None:
            print("(非文本内容)")
            continue
        try:
            print(json.dumps(json.loads(text), ensure_ascii=False, indent=2))
        except json.JSONDecodeError:
            print(text)


async def main() -> None:
    params = StdioServerParameters(
        command=sys.executable,
        args=["-m", "home_mcp.entry", "--config", "config.yaml"],
        cwd=str(HERE),
        env={**os.environ, "HA_TOKEN": TOKEN},
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print("工具面:", [tool.name for tool in tools.tools])

            show("observe_home", await session.call_tool("observe_home", {}))
            show(
                f"inspect_device({DEVICE_ID})",
                await session.call_tool("inspect_device", {"device_id": DEVICE_ID}),
            )
            # 给了第三个参数就顺手执行一次动作，用来验证端到端
            # 例：python smoke.py speaker turn_on
            if len(sys.argv) > 2:
                action = sys.argv[2]
                params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
                show(
                    f"execute_action({DEVICE_ID}, {action}, {params})",
                    await session.call_tool(
                        "execute_action",
                        {"device_id": DEVICE_ID, "action": action, "params": params},
                    ),
                )


if __name__ == "__main__":
    asyncio.run(main())
