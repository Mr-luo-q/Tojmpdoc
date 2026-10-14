"""量"写调用耗时 vs 世界状态落定耗时"：MCP 写完立刻回，但设备状态是异步落地的。

做法：先记实体当前状态 → 调写入工具（记耗时）→ 轮询 HA 直到状态变成目标值（记落定耗时）
      → 再调恢复工具把它写回原状态 → 轮询确认恢复。

为什么重要：B/C 两条路线都不做写后回读，工具返回"成功"时设备可能还没变；
端侧模型如果立刻复查，会看到旧状态，进而误判自己失败（或反过来谎报成功）。

用法：
    python _tools\\mcp_write_settle.py --http http://localhost:8123/api/mcp `
        --entity switch.simuhome_living_room_side_light `
        --on-tool HassTurnOn  --on-args-file on.json `
        --off-tool HassTurnOff --off-args-file off.json

    python _tools\\mcp_write_settle.py --stdio "uvx hass-mcp" `
        --entity switch.simuhome_living_room_side_light `
        --on-tool entity_action --on-args-file c_on.json `
        --off-tool entity_action --off-args-file c_off.json
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shlex
import time
from pathlib import Path
from typing import Any

import httpx
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TOKEN = PROJECT_ROOT / "_secrets" / "ha_token.txt"
HA_BASE = "http://127.0.0.1:8123"

for _host in ("localhost", "127.0.0.1", "::1"):
    current = os.environ.get("NO_PROXY", "")
    if _host not in current:
        os.environ["NO_PROXY"] = f"{current},{_host}".strip(",")
os.environ.setdefault("no_proxy", os.environ["NO_PROXY"])


def read_state(entity_id: str, token: str) -> str:
    """读实体原始状态。"""

    response = httpx.get(
        f"{HA_BASE}/api/states/{entity_id}",
        headers={"Authorization": f"Bearer {token}"},
        timeout=10,
    )
    response.raise_for_status()
    return str(response.json().get("state"))


def wait_state(entity_id: str, token: str, expected: str, timeout_s: float = 8.0) -> tuple[bool, int]:
    """轮询到状态变成期望值；返回 (是否变到, 耗时毫秒)。"""

    started = time.perf_counter()
    while time.perf_counter() - started < timeout_s:
        if read_state(entity_id, token) == expected:
            return True, int((time.perf_counter() - started) * 1000)
        time.sleep(0.05)
    return False, int((time.perf_counter() - started) * 1000)


async def call_tool(session: ClientSession, name: str, arguments: dict[str, Any]) -> tuple[bool, int, str]:
    """调一个工具，返回 (isError, 毫秒, 文本)。"""

    started = time.perf_counter()
    result = await session.call_tool(name, arguments)
    elapsed = int((time.perf_counter() - started) * 1000)
    text = "\n".join(getattr(item, "text", "") for item in (result.content or []))
    return bool(result.isError), elapsed, text


async def run(options: argparse.Namespace, session: ClientSession, token: str) -> int:
    """跑一次写入-落定-恢复的测量。"""

    entity = options.entity
    before = read_state(entity, token)
    on_args = json.loads(Path(options.on_args_file).read_text(encoding="utf-8"))
    off_args = json.loads(Path(options.off_args_file).read_text(encoding="utf-8"))

    print(f"实体 {entity} 当前状态 {before!r}")
    is_error, call_ms, text = await call_tool(session, options.on_tool, on_args)
    settled, settle_ms = wait_state(entity, token, "on")
    print(f"  开：调用 {call_ms} ms，isError={is_error}，状态落定 {'成功' if settled else '超时'} 用 {settle_ms} ms")
    print(f"  返回：{text[:200].replace(chr(10), ' ')}")

    is_error2, call_ms2, text2 = await call_tool(session, options.off_tool, off_args)
    back, back_ms = wait_state(entity, token, before)
    print(f"  关（还原）：调用 {call_ms2} ms，isError={is_error2}，回到 {before!r} "
          f"{'成功' if back else '超时'} 用 {back_ms} ms")
    return 0


async def main_async(options: argparse.Namespace) -> int:
    """建连接并跑测量。"""

    token_path = Path(options.token_file)
    token = token_path.read_text(encoding="utf-8").strip()
    if options.http:
        headers = {"Authorization": f"Bearer {token}"}
        async with streamablehttp_client(options.http, headers=headers) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                return await run(options, session, token)
    parts = [part.strip('"') for part in shlex.split(options.stdio, posix=False)]
    parameters = StdioServerParameters(command=parts[0], args=parts[1:], env=dict(os.environ))
    async with stdio_client(parameters) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            return await run(options, session, token)


def main() -> int:
    """命令行入口。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--http")
    parser.add_argument("--stdio")
    parser.add_argument("--token-file", default=str(DEFAULT_TOKEN))
    parser.add_argument("--entity", required=True)
    parser.add_argument("--on-tool", required=True)
    parser.add_argument("--on-args-file", required=True)
    parser.add_argument("--off-tool", required=True)
    parser.add_argument("--off-args-file", required=True)
    options = parser.parse_args()
    if bool(options.http) == bool(options.stdio):
        raise SystemExit("必须二选一：--http 或 --stdio")
    return asyncio.run(main_async(options))


if __name__ == "__main__":
    raise SystemExit(main())
