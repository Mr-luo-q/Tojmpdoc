"""统一 MCP 探针：连一个 MCP server，列出工具 / 提示 / 资源，或调用一个工具。

支持的两种传输：
  stdio             在本地起一个子进程（例：uvx hass-mcp）
  streamable HTTP   连远端 URL（例：HA 官方 MCP 的 http://localhost:8123/api/mcp）

用法（令牌默认读 ..\\_secrets\\ha_token.txt，只用于 HTTP 传输）：
    python _tools\\mcp_probe.py --http http://localhost:8123/api/mcp
    python _tools\\mcp_probe.py --stdio "uvx hass-mcp"
    python _tools\\mcp_probe.py --http http://localhost:8123/api/mcp --call GetLiveContext --args "{}"
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shlex
import sys
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client


DEFAULT_TOKEN = Path(__file__).resolve().parent.parent / "_secrets" / "ha_token.txt"
MAX_DESCRIPTION = 80
MAX_PAYLOAD = 4000

# 本机开着系统代理（127.0.0.1:7897）时，httpx 会把 localhost 也发进代理，拿到 502。
# 探针只连本机 HA，所以显式把本机地址放进 NO_PROXY；子进程（stdio server）也会继承。
for _host in ("localhost", "127.0.0.1", "::1"):
    current = os.environ.get("NO_PROXY", "")
    if _host not in current:
        os.environ["NO_PROXY"] = f"{current},{_host}".strip(",")
os.environ.setdefault("no_proxy", os.environ["NO_PROXY"])


def load_token(path: Path | None) -> str | None:
    """读 HA 长期令牌；文件不存在就返回 None（有些 server 不需要鉴权）。"""

    if path is None or not path.exists():
        return None
    return path.read_text(encoding="utf-8").strip()


async def print_surface(session: ClientSession) -> None:
    """打印 tools / prompts / resources 三个能力面；不支持的服务器跳过。"""

    tools = await session.list_tools()
    print(f"工具 {len(tools.tools)} 个：")
    for tool in tools.tools:
        schema = tool.inputSchema or {}
        params = list((schema.get("properties") or {}).keys())
        required = list(schema.get("required") or [])
        description = (tool.description or "").replace("\n", " ")[:MAX_DESCRIPTION]
        print(f"  - {tool.name}  参数={params}  必填={required}")
        if description:
            print(f"      {description}")

    try:
        prompts = await session.list_prompts()
        print(f"提示 {len(prompts.prompts)} 个：" + ", ".join(item.name for item in prompts.prompts))
    except Exception as err:  # noqa: BLE001 - 服务器不支持时各种异常都可能
        print(f"提示：不支持或读取失败（{type(err).__name__}）")

    try:
        resources = await session.list_resources()
        print(f"资源 {len(resources.resources)} 个：" + ", ".join(str(item.uri) for item in resources.resources))
    except Exception as err:  # noqa: BLE001
        print(f"资源：不支持或读取失败（{type(err).__name__}）")


async def call_one(session: ClientSession, name: str, arguments: dict[str, Any]) -> None:
    """调一个工具并打印结果（截断到 MAX_PAYLOAD 字）。"""

    result = await session.call_tool(name, arguments)
    texts = [getattr(item, "text", "") for item in (result.content or [])]
    payload = "\n".join(texts)
    print(f"调用 {name} → isError={result.isError}")
    print(payload[:MAX_PAYLOAD])


async def probe_http(url: str, token: str | None, call: str | None, args: dict[str, Any]) -> int:
    """连 Streamable HTTP 端点。"""

    headers = {"Authorization": f"Bearer {token}"} if token else None
    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            await print_surface(session)
            if call:
                await call_one(session, call, args)
    return 0


async def probe_stdio(command: str, call: str | None, args: dict[str, Any]) -> int:
    """起一个 stdio 子进程当 MCP server。"""

    parts = shlex.split(command, posix=False)
    parts = [part.strip('"') for part in parts]
    parameters = StdioServerParameters(command=parts[0], args=parts[1:], env=dict(os.environ))
    async with stdio_client(parameters) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            await print_surface(session)
            if call:
                await call_one(session, call, args)
    return 0


def main() -> int:
    """命令行入口：二选一 --http 或 --stdio。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--http", help="Streamable HTTP 端点，例如 http://localhost:8123/api/mcp")
    parser.add_argument("--stdio", help="stdio server 命令行，例如 \"uvx hass-mcp\"")
    parser.add_argument("--token-file", default=str(DEFAULT_TOKEN), help="HTTP 用的令牌文件")
    parser.add_argument("--call", help="可选：调用某个工具名")
    parser.add_argument("--args", default="{}", help="调用参数（JSON）")
    parser.add_argument(
        "--args-file",
        help="调用参数改从文件读（PowerShell 5.1 传带引号的 JSON 容易被打散，复杂参数用这个）",
    )
    options = parser.parse_args()

    if bool(options.http) == bool(options.stdio):
        print("必须二选一：--http 或 --stdio", file=sys.stderr)
        return 2

    if options.args_file:
        arguments = json.loads(Path(options.args_file).read_text(encoding="utf-8"))
    else:
        arguments = json.loads(options.args)
    if options.http:
        token = load_token(Path(options.token_file))
        return asyncio.run(probe_http(options.http, token, options.call, arguments))
    return asyncio.run(probe_stdio(options.stdio, options.call, arguments))


if __name__ == "__main__":
    raise SystemExit(main())
