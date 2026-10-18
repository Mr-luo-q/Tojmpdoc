# 本文件是 ha_mcp_universal\tests\test_llm_fridge.py 的副本。
# 对应原始文件：ha_mcp_universal\tests\test_llm_fridge.py
# 改动三处（见下方 # 本副本 注释）：
#   1. PROJECT_ROOT 硬编码回源包目录；
#   2. COLD_DEVICE / FREEZE_DEVICE 改成本机别名表里的 id
#      （原文那台机器是 cn_911432173_cold / cn_911432173_freeze）。
# 它会真的写真冰箱，跑完脚本自己还原。
"""大模型直连 MCP 控制米家冰箱：让 DeepSeek 把冷藏设定温度在 2 与 6 之间来回切换。

做法：
  1  按 stdio 起 v2 的 MCP server（ha_mcp_universal）
  2  脚本先快照冰箱两个温区的设定值（冷藏 + 冷冻）
  3  把任务丢给 DeepSeek：它自己决定调 inspect_device / execute_action
  4  跑完由脚本回读核实（不信模型的口头结论），最后把设定值还原成快照

用法（先在 .env 填 DEEPSEEK_API_KEY）：
    python tests\\test_llm_fridge.py --config config.yaml
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(r"D:\项目\simuhome-ljb\ha_mcp_universal")   # 本副本：硬编码回源包目录（副本不在该目录下）
REPO_ROOT = PROJECT_ROOT.parent
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from dotenv import load_dotenv                                   # noqa: E402
from mcp import ClientSession, StdioServerParameters             # noqa: E402
from mcp.client.stdio import stdio_client                        # noqa: E402
from openai import OpenAI                                        # noqa: E402


COLD_DEVICE = "fridge_cold"      # 本副本：改用本机别名表里的 id
FREEZE_DEVICE = "fridge_freeze"  # 本副本：改用本机别名表里的 id
MAX_TOOL_STEPS = 24
ROUNDS = 3
TARGET_LOW, TARGET_HIGH = 2, 6
SYSTEM_PROMPT = "你是家庭环境助手，通过工具读取和控制这个家。无论用户用什么语言提问，都用中文回答。"


def find_env_file() -> Path | None:
    """DeepSeek 的密钥放在 ha_mcp_server\\.env（也可在 v2 目录放一份）。"""

    for candidate in (PROJECT_ROOT / ".env", REPO_ROOT / "ha_mcp_server" / ".env"):
        if candidate.exists():
            return candidate
    return None


def build_client() -> tuple[OpenAI, str, str]:
    """按 .env 建 DeepSeek 客户端，返回 (客户端, 模型名, 思考模式)。"""

    env_path = find_env_file()
    if env_path:
        load_dotenv(env_path)
    api_key = (os.environ.get("DEEPSEEK_API_KEY") or "").strip()
    if not api_key:
        print("DEEPSEEK_API_KEY 为空：请在 ha_mcp_server\\.env 填入密钥后重跑", file=sys.stderr)
        raise SystemExit(2)
    base_url = (os.environ.get("DEEPSEEK_BASE_URL") or "https://api.deepseek.com").strip()
    model = (os.environ.get("DEEPSEEK_MODEL") or "deepseek-flash").strip()
    thinking = (os.environ.get("DEEPSEEK_THINKING") or "disabled").strip()
    return OpenAI(api_key=api_key, base_url=base_url), model, thinking


def tools_for_model(tools: list[Any]) -> list[dict[str, Any]]:
    """把 MCP 的工具清单转成 OpenAI function calling 的格式。"""

    return [
        {
            "type": "function",
            "function": {
                "name": tool.name,
                "description": tool.description or "",
                "parameters": tool.inputSchema,
            },
        }
        for tool in tools
    ]


def payload_of(result: Any) -> dict[str, Any]:
    """把一次 tools/call 的返回解析成统一外壳。"""

    text = result.content[0].text if result.content else "{}"
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"ok": False, "error": {"code": "BAD_PAYLOAD", "message": text[:200]}}


async def call_tool(session: ClientSession, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    """调一次工具并返回统一外壳。"""

    return payload_of(await session.call_tool(name, arguments))


async def read_target(session: ClientSession, device_id: str) -> Any:
    """读一台设备的 target（冰箱温区设定值）。"""

    data = await call_tool(session, "inspect_device", {"device_id": device_id})
    return (data.get("data") or {}).get("state", {}).get("target")


async def ask_model(
    client: OpenAI,
    model: str,
    thinking: str,
    session: ClientSession,
    tools: list[Any],
    task: str,
) -> tuple[list[dict[str, Any]], str]:
    """把任务交给模型，让它自己调工具；返回工具调用序列与最终答复。"""

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task},
    ]
    calls: list[dict[str, Any]] = []
    final_text = ""
    for _ in range(MAX_TOOL_STEPS):
        response = await asyncio.to_thread(
            lambda: client.chat.completions.create(
                model=model,
                messages=messages,
                tools=tools_for_model(tools),
                tool_choice="auto",
                extra_body={"thinking": {"type": thinking}},
            )
        )
        message = response.choices[0].message
        messages.append(message.model_dump(exclude_none=True))
        if not message.tool_calls:
            final_text = message.content or ""
            break
        for tool_call in message.tool_calls:
            try:
                arguments = json.loads(tool_call.function.arguments or "{}")
            except json.JSONDecodeError:
                arguments = {}
            payload = await call_tool(session, tool_call.function.name, arguments)
            calls.append(
                {
                    "tool": tool_call.function.name,
                    "arguments": arguments,
                    "ok": bool(payload.get("ok")),
                    "data": payload.get("data"),
                    "verified": (payload.get("data") or {}).get("verified"),
                    "state_after": (payload.get("data") or {}).get("state_after"),
                    "error": (payload.get("error") or {}).get("code"),
                }
            )
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "content": json.dumps(payload, ensure_ascii=False),
                }
            )
    else:
        messages.append({"role": "user", "content": "请用中文简要总结目前的结论。"})
        response = await asyncio.to_thread(
            lambda: client.chat.completions.create(
                model=model,
                messages=messages,
                tools=tools_for_model(tools),
                tool_choice="none",
                extra_body={"thinking": {"type": thinking}},
            )
        )
        final_text = response.choices[0].message.content or ""
    return calls, final_text


async def main_async(config_path: Path) -> int:
    """跑一整轮：快照 → 模型控制 → 脚本核实与还原。"""

    client, model, thinking = build_client()
    os.environ.setdefault("MCP_TOKEN", "local-dev-token")
    if not os.environ.get("HA_TOKEN"):
        token_file = REPO_ROOT / "_secrets" / "ha_token.txt"
        if token_file.exists():
            os.environ["HA_TOKEN"] = token_file.read_text(encoding="utf-8").strip()

    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-m", "home_mcp.entry", "--config", str(config_path)],
        env={**os.environ, "PYTHONPATH": str(PROJECT_ROOT / "src")},
    )
    checks: list[tuple[str, bool, str]] = []
    checks_append = lambda name, ok, detail="": checks.append((name, ok, detail))  # noqa: E731

    async with stdio_client(parameters) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools = (await session.list_tools()).tools
            print(f"模型 {model}（thinking={thinking}）；MCP 工具 {len(tools)} 个")

            cold_before = await read_target(session, COLD_DEVICE)
            freeze_before = await read_target(session, FREEZE_DEVICE)
            print(f"测试前：冷藏设定={cold_before} 冷冻设定={freeze_before}")

            task = (
                f"请用工具控制冰箱的冷藏室设定温度：把「{COLD_DEVICE}」的目标温度从 "
                f"{TARGET_LOW} 度和 {TARGET_HIGH} 度之间来回切换 {ROUNDS} 轮"
                f"（顺序：{TARGET_LOW}→{TARGET_HIGH}→{TARGET_LOW}→…），"
                "每写一次都要确认真的生效（工具会返回 verified），最后用一句话总结结果。"
            )
            try:
                calls, final_text = await ask_model(client, model, thinking, session, tools, task)
                # 还原之前先记下"模型做完之后"的真实设定值，用来核对模型的口头结论
                cold_after_model = await read_target(session, COLD_DEVICE)
            finally:
                # 无论模型跑成什么样，都把两个温区还原成测试前的设定值
                if cold_before is not None:
                    await call_tool(
                        session,
                        "execute_action",
                        {"device_id": COLD_DEVICE, "action": "set_temperature", "params": {"value": cold_before}},
                    )
                if freeze_before is not None:
                    await call_tool(
                        session,
                        "execute_action",
                        {"device_id": FREEZE_DEVICE, "action": "set_temperature", "params": {"value": freeze_before}},
                    )

            print("\n=== 工具调用序列 ===")
            for index, item in enumerate(calls, 1):
                target = (item.get("arguments") or {}).get("params", {}).get("value")
                detail = f"value={target}" if target is not None else ""
                if not item["ok"]:
                    detail += f" error={item['error']}"
                print(
                    f"  {index:>2}. {item['tool']:<16} ok={item['ok']} "
                    f"verified={item['verified']} {detail} state_after={item['state_after']}"
                )
            print(f"\n模型总结：{final_text.strip()[:200]}")

            writes = [
                item for item in calls
                if item["tool"] == "execute_action"
                and (item.get("arguments") or {}).get("action") == "set_temperature"
                and (item.get("arguments") or {}).get("device_id") == COLD_DEVICE
            ]
            sequence = [(item["arguments"]["params"]["value"]) for item in writes if item.get("ok")]
            freeze_after = await read_target(session, FREEZE_DEVICE)
            cold_restored = await read_target(session, COLD_DEVICE)
            print(f"模型跑完时：冷藏设定={cold_after_model}")
            print(f"已还原：冷藏设定={cold_restored} 冷冻设定={freeze_after}")

            checks_append("模型先查再动（调过 inspect_device）",
                          any(item["tool"] == "inspect_device" for item in calls))
            checks_append(f"对冷藏室至少写了 {ROUNDS * 2} 次", len(writes) >= ROUNDS * 2, f"实际 {len(writes)} 次")
            failed_writes = [item for item in writes if not item["ok"]]
            checks_append("成功的写都 verified=true（失败的重试算过）",
                          bool(writes)
                          and all(item["verified"] is True for item in writes if item["ok"]),
                          f"失败 {len(failed_writes)} 次（错误码 {[item['error'] for item in failed_writes]}）")
            checks_append(f"写序列里 {TARGET_LOW} 与 {TARGET_HIGH} 都出现过",
                          TARGET_LOW in sequence and TARGET_HIGH in sequence, str(sequence))
            checks_append("脚本回读与模型最后一次写的一致",
                          bool(sequence) and cold_after_model == sequence[-1],
                          f"回读={cold_after_model} 最后一次={sequence[-1] if sequence else None}")
            checks_append("两个温区都还原成测试前的设定值",
                          cold_restored == cold_before and freeze_after == freeze_before,
                          f"冷藏 {cold_before}→{cold_restored}；冷冻 {freeze_before}→{freeze_after}")

    for name, ok, detail in checks:
        flag = "通过" if ok else "失败"
        print(f"[{flag}] {name}" + (f"  —— {detail}" if detail else ""))
    failed = [name for name, ok, _ in checks if not ok]
    print(f"结论：{len(checks) - len(failed)} / {len(checks)} 项通过")
    return 1 if failed else 0


def main() -> int:
    """命令行入口。"""

    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(PROJECT_ROOT / "config.yaml"))
    args = parser.parse_args()
    return asyncio.run(main_async(Path(args.config)))


if __name__ == "__main__":
    raise SystemExit(main())
