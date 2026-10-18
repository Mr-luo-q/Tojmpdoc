"""MCP 接口面计量器：量一个 MCP server 的"固定开销"与"单次调用开销"。

量什么：
  ① tools/list 的字节数与估算 token 数（端侧模型每轮都要背的固定开销）
  ② 每个工具的 schema：参数个数、必填个数、有没有 enum / 上下界
  ③ prompts / resources 的数量与体量
  ④ 一组读操作（或安全的错误调用）的输出字节数、估算 token 数、耗时

预设了三套调用档案（--profile b|c|e），对应三条路线：
  b  官方 MCP Server：GetLiveContext（全屋上下文）
  c  社区 hass-mcp：list_entities / get_entity（含一次错误调用）
  e  我们的 MCP：observe_home / inspect_room / inspect_device / execute_action（错误调用）

用法：
    python _tools\\mcp_surface_bench.py --profile b --http http://localhost:8123/api/mcp
    python _tools\\mcp_surface_bench.py --profile c --stdio "uvx hass-mcp"
    python _tools\\mcp_surface_bench.py --profile e --stdio "python -m home_mcp.entry --config config.yaml"
输出：控制台摘要 + --out 指定的 JSON 明细
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import shlex
import sys
import time
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TOKEN = PROJECT_ROOT / "_secrets" / "ha_token.txt"

for _host in ("localhost", "127.0.0.1", "::1"):
    current = os.environ.get("NO_PROXY", "")
    if _host not in current:
        os.environ["NO_PROXY"] = f"{current},{_host}".strip(",")
os.environ.setdefault("no_proxy", os.environ["NO_PROXY"])

# 三条路线的调用档案：(工具名, 参数, 说明)
PROFILES: dict[str, list[tuple[str, dict[str, Any], str]]] = {
    "b": [
        ("GetLiveContext", {}, "全屋上下文快照"),
        ("HassTurnOn", {"name": "不存在的设备"}, "不存在的名字（错误输出体量）"),
    ],
    "c": [
        ("list_entities", {}, "列实体"),
        ("get_entity", {"entity_id": "switch.simuhome_living_room_side_light"}, "读单实体"),
        ("get_entity", {"entity_id": "switch.simuhome_no_such_device"}, "不存在的实体（错误输出体量）"),
    ],
    "e": [
        ("observe_home", {}, "全屋快照"),
        ("inspect_room", {"room_id": "living_room"}, "读一个房间"),
        ("inspect_device", {"device_id": "living_room_ac"}, "读一台设备"),
        ("execute_action", {"device_id": "ghost", "action": "turn_on"}, "不存在的设备（错误输出体量）"),
    ],
}


def estimate_tokens(text: str) -> int:
    """粗略估算 token：中日韩字符按 1.5 字/词，其余按 4 字/词。"""

    cjk = sum(1 for ch in text if "\u4e00" <= ch <= "\u9fff" or "\u3000" <= ch <= "\u303f")
    others = len(text) - cjk
    return int(cjk / 1.5 + others / 4)


def dump_size(payload: Any) -> tuple[int, int]:
    """返回 (字节数, 估算 token)。"""

    text = json.dumps(payload, ensure_ascii=False, default=str)
    return len(text.encode("utf-8")), estimate_tokens(text)


async def measure(session: ClientSession, profile: str) -> dict[str, Any]:
    """量工具面 + 跑档案里的调用，返回明细。"""

    report: dict[str, Any] = {}

    tools = await session.list_tools()
    tool_payload = [item.model_dump(exclude_none=True) for item in tools.tools]
    size, tokens = dump_size(tool_payload)
    per_tool = []
    for item in tool_payload:
        schema = item.get("inputSchema") or {}
        props = schema.get("properties") or {}
        required = schema.get("required") or []
        constrained = [
            key
            for key, spec in props.items()
            if any(k in spec for k in ("enum", "minimum", "maximum", "multipleOf", "pattern"))
        ]
        per_tool.append(
            {
                "name": item.get("name"),
                "schema_bytes": len(json.dumps(schema, ensure_ascii=False).encode()),
                "params": list(props),
                "required": required,
                "constrained": constrained,
            }
        )
    report["tools"] = {
        "count": len(tool_payload),
        "bytes": size,
        "tokens": tokens,
        "per_tool": per_tool,
    }

    prompts, resources = [], []
    try:
        prompts = [item.model_dump(exclude_none=True) for item in (await session.list_prompts()).prompts]
    except Exception:  # noqa: BLE001
        prompts = []
    try:
        resources = [
            item.model_dump(exclude_none=True) for item in (await session.list_resources()).resources
        ]
    except Exception:  # noqa: BLE001
        resources = []
    p_bytes, p_tokens = dump_size(prompts)
    r_bytes, r_tokens = dump_size(resources)
    report["prompts"] = {"count": len(prompts), "bytes": p_bytes, "tokens": p_tokens}
    report["resources"] = {"count": len(resources), "bytes": r_bytes, "tokens": r_tokens}

    calls = []
    for name, arguments, note in PROFILES[profile]:
        started = time.perf_counter()
        try:
            result = await session.call_tool(name, arguments)
            texts = [getattr(item, "text", "") for item in (result.content or [])]
            payload_text = "\n".join(texts)
            is_error = bool(result.isError)
        except Exception as err:  # noqa: BLE001
            payload_text = f"{type(err).__name__}: {err}"
            is_error = True
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        calls.append(
            {
                "tool": name,
                "note": note,
                "is_error": is_error,
                "elapsed_ms": elapsed_ms,
                "bytes": len(payload_text.encode("utf-8")),
                "tokens": estimate_tokens(payload_text),
                "head": payload_text[:200].replace("\n", " "),
            }
        )
    report["calls"] = calls
    return report


async def run_http(url: str, token: str | None, profile: str) -> dict[str, Any]:
    """连 Streamable HTTP 端点。"""

    headers = {"Authorization": f"Bearer {token}"} if token else None
    async with streamablehttp_client(url, headers=headers) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            return await measure(session, profile)


async def run_stdio(command: str, profile: str) -> dict[str, Any]:
    """起 stdio 子进程。"""

    parts = [part.strip('"') for part in shlex.split(command, posix=False)]
    parameters = StdioServerParameters(command=parts[0], args=parts[1:], env=dict(os.environ))
    async with stdio_client(parameters) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            return await measure(session, profile)


def print_summary(profile: str, report: dict[str, Any]) -> None:
    """打印人类可读的摘要。"""

    tools = report["tools"]
    print(f"[{profile}] 工具 {tools['count']} 个｜工具面 {tools['bytes']} 字节 ≈ {tools['tokens']} token")
    no_required = sum(1 for item in tools["per_tool"] if not item["required"])
    print(f"      必填为空的工具 {no_required}/{tools['count']}；带约束（enum/上下界）的工具 "
          f"{sum(1 for item in tools['per_tool'] if item['constrained'])}/{tools['count']}")
    print(f"      提示 {report['prompts']['count']} 个（{report['prompts']['bytes']} 字节）"
          f"｜资源 {report['resources']['count']} 个（{report['resources']['bytes']} 字节）")
    for call in report["calls"]:
        flag = "错误" if call["is_error"] else "正常"
        print(f"      {call['tool']:<22} {flag}  {call['elapsed_ms']:>5} ms  "
              f"{call['bytes']:>6} 字节 ≈ {call['tokens']:>5} token  {call['note']}")


def main() -> int:
    """命令行入口。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True, choices=sorted(PROFILES))
    parser.add_argument("--http")
    parser.add_argument("--stdio")
    parser.add_argument("--token-file", default=str(DEFAULT_TOKEN))
    parser.add_argument("--out")
    options = parser.parse_args()

    if bool(options.http) == bool(options.stdio):
        print("必须二选一：--http 或 --stdio", file=sys.stderr)
        return 2

    if options.http:
        token_path = Path(options.token_file)
        token = token_path.read_text(encoding="utf-8").strip() if token_path.exists() else None
        report = asyncio.run(run_http(options.http, token, options.profile))
    else:
        report = asyncio.run(run_stdio(options.stdio, options.profile))

    print_summary(options.profile, report)
    if options.out:
        Path(options.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"明细已写入 {options.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
