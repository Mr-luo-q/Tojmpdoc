"""汇总方案 B 的实测记录：每一步调了什么工具、引用的 id 是真实存在还是编造。

用途是做 05 文档里那几条验收：模型有没有跳过必要的观察、有没有凭空造 id。
只读 logs 与数据集，不连手机。
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR.parent / "tools"))
import traj_replay as base  # noqa: E402


def load_truth() -> dict[str, dict]:
    """从数据集里取出每个样本"合法的设备 id 与房间 id"，用来判断模型是不是编的。"""
    truth: dict[str, dict] = {}
    for row in base.read_rows(base.DATASET):
        home = row["scenario"]["home"]
        truth[row["record"]["scenario_id"]] = {
            "devices": {d["device_id"] for d in home["devices"]},
            "rooms": {r["room_id"] for r in home["rooms"]},
        }
    return truth


def pick(content: str, key: str) -> str | None:
    """从生成内容里抠出某个字段的值，抠不到返回 None。"""
    found = re.search(r'"' + key + r'"\s*:\s*"([^"]+)"', content)
    return found.group(1) if found else None


def main() -> None:
    """遍历 protoB 的日志，逐条打印工具调用与 id 真伪。"""
    truth = load_truth()
    pattern = str(base.LOGDIR / "*protoB*.json")
    first_step_wrong = 0
    total = 0

    for path in sorted(glob.glob(pattern)):
        record = json.loads(Path(path).read_text(encoding="utf-8"))
        sample = record["args"]["sample"]
        level = record["args"].get("home_level", "?")
        known = truth.get(sample, {"devices": set(), "rooms": set()})
        print(f"=== {sample}  home={level}  模型 {record.get('model') or '(旧记录无此字段)'}"
              f"  预热 {record['prewarm_ms'] / 1000:.1f} s")

        for row in record["records"]:
            content = row.get("content_head") or ""
            tool = pick(content, "name") or "?"
            device_id = pick(content, "device_id")
            room_id = pick(content, "room_id")
            note = ""
            if device_id:
                note = f"device_id={device_id} {'真实' if device_id in known['devices'] else '★编造'}"
            elif room_id:
                note = f"room_id={room_id} {'真实' if room_id in known['rooms'] else '★编造'}"
            print(f"    第{row['turn']}跳 {tool:<15} {note}")

            # 第 0 跳的正确形态：先观察（inspect_room），不该是 execute_action
            if row["turn"] == 0:
                total += 1
                bad = tool != "inspect_room" or (room_id is not None and room_id not in known["rooms"])
                first_step_wrong += 1 if bad else 0

        wall = sum(r["wall_ms"] for r in record["records"])
        steps = len(record["records"])
        print(f"    合计：预热 {record['prewarm_ms'] / 1000:.1f} s"
              f" + 计时 {wall / 1000:.1f} s（{steps} 跳，单跳 {wall / steps / 1000:.1f} s）")

    print()
    print(f"第 0 跳不达标 {first_step_wrong} / {total} 条（达标 = 先 inspect_room 且房间 id 真实）")


if __name__ == "__main__":
    main()
