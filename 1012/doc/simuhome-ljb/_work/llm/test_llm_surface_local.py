# 本文件是 ha_mcp_universal\tests\test_llm_surface.py 的副本。
# 对应原始文件：ha_mcp_universal\tests\test_llm_surface.py
# 唯一改动（两处，见下方 # 本副本 注释）：
#   1. PROJECT_ROOT 硬编码回源包目录；
#   2. 临时配置改写进系统临时目录，不落进 ha_mcp_universal\。
# 原因：AGENTS.md 第 1 条要求不往仓库源目录里写文件。
"""DeepSeek 通过 stdio 实测 v2 MCP：验证它能否调用当前暴露的 8 个接口。

覆盖：inspect_time / inspect_device / execute_action / memory /
      time_control（schedule + cancel + list）/ finish。
模型只负责发工具调用；脚本负责核对调用序列与真实结果，并还原设备状态。

用法（先在 ha_mcp_server\\.env 填 DEEPSEEK_API_KEY）：
    python tests\\test_llm_surface.py --config config.yaml
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(r"D:\项目\simuhome-ljb\ha_mcp_universal")   # 本副本：硬编码回源包目录（副本不在该目录下，parents[1] 会指错）
REPO_ROOT = PROJECT_ROOT.parent
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(PROJECT_ROOT / "src"))

import yaml                                                     # noqa: E402
from mcp import ClientSession, StdioServerParameters            # noqa: E402
from mcp.client.stdio import stdio_client                       # noqa: E402

from home_mcp.runtime import load_config                        # noqa: E402
from tests.test_llm_fridge import (                             # noqa: E402
    ask_model,
    build_client,
    call_tool,
)


LIGHT = "living_room_side_light"
MEMORY_TEXT = "用户喜欢22度"
EXPECTED_TOOLS = [
    "observe_home",
    "inspect_room",
    "inspect_device",
    "execute_action",
    "finish",
    "inspect_time",
    "time_control",
    "memory",
]


def write_temp_config(config_path: Path) -> tuple[Path, Path]:
    """复制一份临时配置：隔离记忆文件与预约库，固定 8 条工具顺序。"""

    tmpdir = Path(tempfile.mkdtemp())
    config = load_config(config_path)
    config["memory"] = {**dict(config.get("memory") or {}), "file": str(tmpdir / "memory.yaml")}
    config["time"] = {**dict(config.get("time") or {}), "db": str(tmpdir / "schedules.db")}
    config["tools"] = {**dict(config.get("tools") or {}), "expose": EXPECTED_TOOLS}
    config.pop("_config_path", None)
    config.pop("_config_dir", None)
    temp_config = tmpdir / "config.live_surface_test.yaml"   # 本副本：临时配置写进临时目录，不写源目录
    temp_config.write_text(
        yaml.safe_dump(config, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    return temp_config, tmpdir


def find_calls(calls: list[dict[str, Any]], name: str, **filters: Any) -> list[dict[str, Any]]:
    """按工具名与参数过滤调用记录。"""

    hits = []
    for item in calls:
        if item.get("tool") != name:
            continue
        arguments = item.get("arguments") or {}
        if all(arguments.get(key) == value for key, value in filters.items()):
            hits.append(item)
    return hits


async def main_async(config_path: Path) -> int:
    """跑三组任务：时间+执行、记忆读写、预约+取消+finish。"""

    client, model, thinking = build_client()
    os.environ.setdefault("MCP_TOKEN", "local-dev-token")
    if not os.environ.get("HA_TOKEN"):
        token_file = REPO_ROOT / "_secrets" / "ha_token.txt"
        if token_file.exists():
            os.environ["HA_TOKEN"] = token_file.read_text(encoding="utf-8").strip()

    temp_config, tmpdir = write_temp_config(config_path)
    parameters = StdioServerParameters(
        command=sys.executable,
        args=["-m", "home_mcp.entry", "--config", str(temp_config)],
        env={**os.environ, "PYTHONPATH": str(PROJECT_ROOT / "src")},
    )
    checks: list[tuple[str, bool, str]] = []
    calls: list[dict[str, Any]] = []

    def record(name: str, ok: bool, detail: str = "") -> None:
        """登记一项检查结果。"""

        checks.append((name, ok, detail))

    try:
        async with stdio_client(parameters) as (read_stream, write_stream):
            async with ClientSession(read_stream, write_stream) as session:
                await session.initialize()
                tools = (await session.list_tools()).tools
                names = [tool.name for tool in tools]
                print(f"模型 {model}（thinking={thinking}）；MCP 工具：{names}")
                record("tools/list 为 8 条且顺序正确", names == EXPECTED_TOOLS, str(names))

                light_before = (
                    (await call_tool(session, "inspect_device", {"device_id": LIGHT}))
                    .get("data", {})
                    .get("state", {})
                    .get("on")
                )

                # 第一组：时间 + 设备 + 立即执行
                task_a = (
                    "请按顺序调用工具完成：1) 用 observe_home 查看全屋快照；"
                    "2) 用 inspect_room 查看 living_room；"
                    "3) 用 inspect_time 查当前时间；"
                    f"4) 用 inspect_device 查看 {LIGHT} 的状态；"
                    f"5) 用 execute_action 把 {LIGHT} 打开；"
                    "6) 用一句话总结。必须实际调用工具，不要只回答。"
                )
                calls_a, text_a = await ask_model(client, model, thinking, session, tools, task_a)
                calls.extend(calls_a)

                # 第二组：记忆写入 + 读回
                task_b = (
                    f"请用工具完成：1) 调用 memory，op=write，把文本「{MEMORY_TEXT}」写入；"
                    "2) 调用 memory，op=read，读出确认；3) 用一句话总结。"
                    "必须实际调用工具。"
                )
                calls_b, text_b = await ask_model(client, model, thinking, session, tools, task_b)
                calls.extend(calls_b)

                # 第三组：预约 + 取消 + 查单 + finish
                tomorrow = (dt.datetime.now().astimezone() + dt.timedelta(days=1)).strftime(
                    "%Y-%m-%d 07:00"
                )
                task_c = (
                    "请用工具完成：1) 调用 time_control，op=schedule，"
                    f'at="{tomorrow}"，steps=[{{"device_id":"{LIGHT}","action":"turn_off"}}]；'
                    "2) 调用 time_control，op=list，看到这张单在列表里；"
                    "3) 用拿到的 schedule_id 调用 time_control，op=cancel 取消它；"
                    "4) 再调用 time_control，op=list，确认这张单已经不在列表里；"
                    "5) 调用 finish，outcome=completed；6) 用一句话总结。"
                    "必须实际调用工具。"
                )
                calls_c, text_c = await ask_model(client, model, thinking, session, tools, task_c)
                calls.extend(calls_c)

                # 还原灯的状态
                if light_before is False:
                    await call_tool(
                        session,
                        "execute_action",
                        {"device_id": LIGHT, "action": "turn_off", "params": {}},
                    )

                print("\n=== 工具调用序列 ===")
                for index, item in enumerate(calls, 1):
                    state = item.get("state_after")
                    detail = f"args={json.dumps(item.get('arguments'), ensure_ascii=False)}"
                    if state:
                        detail += f" state_after={state}"
                    if not item.get("ok"):
                        detail += f" error={item.get('error')}"
                    print(f"  {index:>2}. {item['tool']:<14} ok={item['ok']} {detail}")
                print(f"\n模型总结 A：{text_a.strip()[:160]}")
                print(f"模型总结 B：{text_b.strip()[:160]}")
                print(f"模型总结 C：{text_c.strip()[:160]}")

                inspect_time_calls = find_calls(calls, "inspect_time")
                observe_calls = find_calls(calls, "observe_home")
                room_calls = find_calls(calls, "inspect_room", room_id="living_room")
                execute_calls = find_calls(calls, "execute_action", action="turn_on")
                memory_writes = find_calls(calls, "memory", op="write")
                memory_reads = find_calls(calls, "memory", op="read")
                schedules = find_calls(calls, "time_control", op="schedule")
                cancels = find_calls(calls, "time_control", op="cancel")
                lists = find_calls(calls, "time_control", op="list")
                finish_calls = find_calls(calls, "finish")

                record(
                    "DeepSeek 调用了 observe_home",
                    any(item.get("ok") for item in observe_calls),
                    f"calls={len(observe_calls)}",
                )
                record(
                    "DeepSeek 调用了 inspect_room(living_room)",
                    any(item.get("ok") for item in room_calls),
                    f"calls={len(room_calls)}",
                )
                record("DeepSeek 调用了 inspect_time", bool(inspect_time_calls), str(inspect_time_calls))
                record(
                    "DeepSeek 调用了 execute_action 并确认灯打开",
                    any(item.get("ok") and (item.get("state_after") or {}).get("on") is True
                        for item in execute_calls),
                    str(execute_calls),
                )
                record(
                    "DeepSeek 调用了 memory write 且返回 code OK",
                    any(item.get("ok") for item in memory_writes),
                    str(memory_writes),
                )
                record(
                    "DeepSeek 调用了 memory read 且读回包含写入文本",
                    any(item.get("ok") for item in memory_reads),
                    str(memory_reads),
                )
                record("DeepSeek 调用了 time_control schedule", bool(schedules), str(schedules))
                record("DeepSeek 调用了 time_control cancel", bool(cancels), str(cancels))
                scheduled_ids = {
                    (item.get("data") or {}).get("schedule_id")
                    for item in schedules if item.get("ok")
                }
                cancelled_ids = {
                    (item.get("arguments") or {}).get("schedule_id") for item in cancels
                }
                visible_seen = any(
                    entry.get("schedule_id") in scheduled_ids
                    for item in lists
                    for entry in ((item.get("data") or {}).get("items") or [])
                )
                last_cancel_at = max(
                    (index for index, item in enumerate(calls)
                     if item["tool"] == "time_control"
                     and (item.get("arguments") or {}).get("op") == "cancel"),
                    default=-1,
                )
                tail_lists = [
                    item for item in calls[last_cancel_at + 1:]
                    if item["tool"] == "time_control"
                    and (item.get("arguments") or {}).get("op") == "list"
                    and item.get("ok")
                ]
                gone_after_cancel = bool(tail_lists) and all(
                    entry.get("schedule_id") not in cancelled_ids
                    for item in tail_lists
                    for entry in ((item.get("data") or {}).get("items") or [])
                )
                record(
                    "DeepSeek：list 先看到预约单，取消后同一单不再出现",
                    visible_seen and gone_after_cancel,
                    f"visible={visible_seen} gone={gone_after_cancel}",
                )
                probe = await call_tool(session, "time_control", {"op": "list"})
                probe_items = (probe.get("data") or {}).get("items") or []
                record(
                    "DeepSeek 调用了 time_control list，且脚本复核取消后的单不在列表里",
                    bool(lists) and probe_items == [],
                    str(probe_items),
                )
                record("DeepSeek 调用了 finish", bool(finish_calls), str(finish_calls))
    finally:
        temp_config.unlink(missing_ok=True)
        shutil.rmtree(tmpdir, ignore_errors=True)

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
