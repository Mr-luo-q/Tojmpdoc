"""方案 B 原型：把房间信息前置成固定块，去掉 observe_home 那一跳。

与主线完全隔离——A_policy.md、工具表、D5 管线都不动，改写全部在内存里完成。
目的是先回答一个问题：模型在"没有 observe_home 工具、房间信息由系统预置"的形态下，
还能不能正确往下走，以及这样一条任务的单轮耗时是多少。
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

# 复用主线脚本的读数据、HTTP 与计时口径，避免两套实现漂移
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR.parent / "tools"))
import traj_replay as base  # noqa: E402

# A_policy.md 里那行原文，以及替换后的写法
OBSERVE_LINE = "  observe_home     只有房间 id 和名称；没有设备、没有温湿度"
OBSERVE_NOTE = "  （本家的房间与设备清单已在对话开头的 home 块里给出，不必再查询）"


def load_sample(sample_id: str) -> dict:
    """按 scenario_id 取一条样本。"""
    rows = base.read_rows(base.DATASET)
    return next(r for r in rows if r["record"]["scenario_id"] == sample_id)


def build_system_b(tools: list[dict]) -> tuple[str, list[dict]]:
    """把 A_policy 改成方案 B 版本：工具表去掉 observe_home，并改掉那行说明。"""
    kept = [t for t in tools if t["name"] != "observe_home"]
    policy = base.POLICY.read_text(encoding="utf-8").replace(
        "{{tools}}", json.dumps(kept, ensure_ascii=False)
    )
    policy = policy.replace(OBSERVE_LINE, OBSERVE_NOTE)
    return policy, kept


def build_home_block(row: dict, level: str) -> dict:
    """拼 home 块。rooms 只给房间；full 再给每个房间的设备 id/名称/类型，不给状态与动作。"""
    rooms = row["record"]["turns"][0]["observation_after"]["last_tool_result"]["data"]["rooms"]
    if level == "rooms":
        return {"rooms": rooms}

    home = row["scenario"]["home"]
    devices = {d["device_id"]: d for d in home["devices"]}
    detailed = []
    for room in rooms:
        source = next(r for r in home["rooms"] if r["room_id"] == room["room_id"])
        detailed.append(
            {
                "room_id": room["room_id"],
                "display_name": room["display_name"],
                "devices": [
                    {
                        "device_id": device_id,
                        "display_name": devices[device_id]["display_name"],
                        "kind": devices[device_id]["kind"],
                        "device_type": devices[device_id]["device_type"],
                    }
                    for device_id in source["device_ids"]
                ],
            }
        )
    return {"rooms": detailed}


def build_messages_b(row: dict, level: str) -> tuple[list[dict], list[dict], str]:
    """返回方案 B 的消息列表：system' + home 块 + 用户话 + 教师从第二跳起的往返。"""
    turns = row["record"]["turns"]
    tools = turns[0]["observation_before"]["tools"]
    policy, kept = build_system_b(tools)
    messages = [
        {"role": "system", "content": policy},
        {
            "role": "user",
            "content": "home: " + json.dumps(build_home_block(row, level), ensure_ascii=False),
        },
        {"role": "user", "content": row["scenario"]["user_request"]},
    ]
    # 教师轨迹里 observe_home 之后的往返照搬，只把第一跳换掉
    for turn in turns[1:]:
        call = turn["tool_calls"][0]
        messages.append(
            {
                "role": "assistant",
                "content": json.dumps(
                    {"name": call["name"], "arguments": call["arguments"]},
                    ensure_ascii=False,
                ),
            }
        )
        if call["name"] == "finish":
            break
        payload = turn["observation_after"]["last_tool_result"]
        messages.append(
            {
                "role": "user",
                "content": "observation: " + json.dumps(payload, ensure_ascii=False),
            }
        )
    return messages, kept, policy


def show_dry_run(messages: list[dict], kept: list[dict], policy: str, tools_all: list[dict]) -> None:
    """离线验收：打印 system 的改动、工具表变化、以及将要发的消息清单。"""
    original = base.POLICY.read_text(encoding="utf-8")
    # 与改造后同口径的对照：原文把 5 个工具都填进去之后的长度
    original_filled = original.replace("{{tools}}", json.dumps(tools_all, ensure_ascii=False))
    print("== system 段的改动 ==")
    print(f"  删掉的一行   : {OBSERVE_LINE.strip()}")
    print(f"  换成         : {OBSERVE_NOTE.strip()}")
    print(f"  原文里那行   : {'能找到' if OBSERVE_LINE in original else '找不到'}")
    print(f"  工具数       : 5 -> {len(kept)}（去掉 observe_home）")
    print(f"  system 字符数: {len(original_filled)}（5 工具）-> {len(policy)}（4 工具）")

    print("\n== 将要发出的消息 ==")
    print(f"{'序号':>4}  {'角色':<10}{'字符数':>8}  开头")
    for index, message in enumerate(messages):
        head = message["content"].replace("\n", " ")[:58]
        print(f"{index:>4}  {message['role']:<10}{len(message['content']):>8}  {head}")


def main() -> None:
    """入口：构造方案 B 的消息，预热 [system+home] 固定块，然后逐跳计时。"""
    parser = argparse.ArgumentParser(description="方案 B 原型：房间信息前置 + 去掉 observe_home")
    parser.add_argument("--host", default="http://127.0.0.1:18080", help="llama-server 地址")
    parser.add_argument("--sample", default="sc_T1_001", help="样本 id")
    parser.add_argument("--home-level", choices=["rooms", "full"], default="rooms",
                        help="home 块给到哪一层：rooms 只给房间；full 连设备 id/名称/类型")
    parser.add_argument("--max-tokens", type=int, default=32, help="每跳生成上限")
    parser.add_argument("--no-prewarm", action="store_true", help="不预热固定块，做对照")
    parser.add_argument("--no-cache", action="store_true", help="禁用前缀 KV 复用")
    parser.add_argument("--dry-run", action="store_true", help="只打印构造结果，不连手机")
    parser.add_argument("--tag", default="", help="写日志时附加的标签")
    args = parser.parse_args()

    row = load_sample(args.sample)
    messages, kept, policy = build_messages_b(row, args.home_level)

    if args.dry_run:
        show_dry_run(messages, kept, policy, row["record"]["turns"][0]["observation_before"]["tools"])
        return

    # 固定块 = system' + home 块；这一段按"家"共享，与用户那句话无关
    head = messages[:2]
    pairs = (len(messages) - 3) // 2
    steps = [messages[: 3 + 2 * k] for k in range(pairs + 1)]

    base.chat(args.host, [{"role": "user", "content": "预热"}], 1, True)

    prewarm_ms = None
    if not args.no_prewarm:
        started = time.perf_counter()
        base.chat(args.host, head, 1, True)
        prewarm_ms = (time.perf_counter() - started) * 1000
        print(f"固定块预热 [system' + home]：{prewarm_ms / 1000:.1f} s（不计入统计）")

    records = []
    for index, step in enumerate(steps):
        payload = base.chat(args.host, step, args.max_tokens, not args.no_cache)
        row_summary = base.summarize(payload, index)
        records.append(row_summary)
        print(f"  第 {index} 跳：" + (row_summary.get("content_head") or "")[:90], flush=True)

    print()
    base.print_table(records)
    total_wall = sum(r["wall_ms"] for r in records)
    total_prefill = sum(r["prefill_ms"] for r in records)
    print()
    print(f"跳数 {len(records)}；prefill 合计 {total_prefill/1000:.1f} s；墙钟合计 {total_wall/1000:.1f} s")
    if prewarm_ms is not None:
        print(f"固定块预热另计 {prewarm_ms/1000:.1f} s")
        print(f"含预热的总账 {total_wall/1000 + prewarm_ms/1000:.1f} s")
    if records:
        print(f"单跳平均墙钟 {total_wall/len(records)/1000:.1f} s")

    base.LOGDIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    name = f"{args.sample}_protoB_{args.home_level}"
    if args.tag:
        name += "_" + args.tag
    out = base.LOGDIR / f"{name}_{stamp}.json"
    out.write_text(
        json.dumps(
            {"args": vars(args), "prewarm_ms": prewarm_ms, "records": records},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"已写入 {out}")


if __name__ == "__main__":
    main()
