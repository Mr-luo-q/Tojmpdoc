"""逐轮回放一条真实合成轨迹，量手机端 llama-server 的分段耗时。

与 training/10-5_sft/data.py 的 reconstruct_messages 口径一致：
  system      A_policy.md 填入该样本记录的公开工具表
  user        scenario.user_request
  每轮        assistant = {"name":..., "arguments":...}
              user      = "observation: " + json.dumps(last_tool_result)

只负责测量，不改任何数据，也不把生成结果写回轨迹。
"""

from __future__ import annotations

import argparse
import json
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

# 仓库与数据位置（只读）
REPO = Path(r"D:\项目\autodl-tmp")
DATASET = REPO / "new_demo/runs/quota200_20261004_v2/data_processed/D_dataset.jsonl"
POLICY = REPO / "new_demo/data_static/D0_templates/A_policy.md"
# 实测记录输出目录（已被 _work/.gitignore 排除）
LOGDIR = Path(__file__).resolve().parent.parent / "logs"


def read_rows(path: Path) -> list[dict]:
    """读 jsonl 数据集，一行一条轨迹。"""
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def build_messages(row: dict) -> list[dict]:
    """按 data.py 的口径把一条轨迹摊成消息列表，返回 system + 逐轮消息。"""
    turns = row["record"]["turns"]
    tools = turns[0]["observation_before"]["tools"]
    policy = POLICY.read_text(encoding="utf-8").replace(
        "{{tools}}", json.dumps(tools, ensure_ascii=False)
    )
    messages = [
        {"role": "system", "content": policy},
        {"role": "user", "content": row["scenario"]["user_request"]},
    ]
    for turn in turns:
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
    return messages


def count_tokens(host: str, text: str) -> int:
    """调 /tokenize 数 token，口径与手机上的模型完全一致。"""
    body = json.dumps({"content": text}).encode("utf-8")
    req = urllib.request.Request(
        host + "/tokenize", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return len(json.loads(resp.read())["tokens"])


def chat(host: str, messages: list[dict], max_tokens: int, cache_prompt: bool) -> dict:
    """发一次 chat 请求，返回服务端 timings 与 usage。"""
    body = json.dumps(
        {
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": 0,
            "cache_prompt": cache_prompt,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        host + "/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=900) as resp:
        payload = json.loads(resp.read())
    wall_ms = (time.perf_counter() - start) * 1000
    payload["wall_ms"] = wall_ms
    return payload


def summarize(payload: dict, turn: int) -> dict:
    """把一次响应压成一行关键指标。"""
    timings = payload.get("timings") or {}
    choice = (payload.get("choices") or [{}])[0]
    content = (choice.get("message") or {}).get("content") or ""
    prompt_ms = timings.get("prompt_ms") or 0.0
    first_token_ms = timings.get("predicted_per_token_ms") or 0.0
    return {
        "turn": turn,
        "finish_reason": choice.get("finish_reason"),
        "content_head": content[:200],
        "usage": payload.get("usage"),
        "wall_ms": round(payload.get("wall_ms", 0.0), 1),
        "prompt_tokens": timings.get("prompt_n"),
        "cached_tokens": timings.get("cache_n"),
        "prefill_ms": round(prompt_ms, 1),
        "prefill_tps": round(timings.get("prompt_per_second") or 0.0, 2),
        "decode_tokens": timings.get("predicted_n"),
        "decode_ms": round(timings.get("predicted_ms") or 0.0, 1),
        "decode_tps": round(timings.get("predicted_per_second") or 0.0, 2),
        "ttft_ms": round(prompt_ms + first_token_ms, 1),
    }


def print_table(rows: list[dict]) -> None:
    """打印分段耗时表。"""
    head = (
        f"{'轮':>3} {'墙钟ms':>9} {'prompt':>7} {'命中':>5} {'prefill_ms':>11} "
        f"{'pp t/s':>7} {'生成':>5} {'decode_ms':>10} {'tg t/s':>7} {'TTFT_ms':>9}"
    )
    print(head)
    print("-" * len(head))
    for row in rows:
        print(
            f"{row['turn']:>3} {row['wall_ms']:>9} {row['prompt_tokens']:>7} "
            f"{row['cached_tokens']:>5} {row['prefill_ms']:>11} {row['prefill_tps']:>7} "
            f"{row['decode_tokens']:>5} {row['decode_ms']:>10} {row['decode_tps']:>7} "
            f"{row['ttft_ms']:>9}"
        )


def brief(value: object, limit: int = 160) -> str:
    """把任意结构压成一行短文本，超长截断。"""
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + "…"


def shape_actions(actions: list[dict]) -> str:
    """把一台设备的动作清单写成「动作名(范围)」串，范围取 enum 或 min–max。"""
    if not actions:
        return "（只读，无动作）"
    parts = []
    for action in actions:
        ranges = []
        for name, spec in (action.get("params") or {}).items():
            if "enum" in spec:
                ranges.append("/".join(str(v) for v in spec["enum"]))
            elif "minimum" in spec:
                ranges.append(f'{spec["minimum"]}–{spec["maximum"]} step {spec.get("step")}')
        parts.append(action["action"] + (f'({"; ".join(ranges)})' if ranges else ""))
    return " / ".join(parts)


def shape_result(name: str, data: object) -> str:
    """按工具名把观察结果写成一句人话，只保留模型真正拿到的东西。"""
    if name == "observe_home":
        rooms = data.get("rooms", [])
        return f'{len(rooms)} 个房间：' + "、".join(r["display_name"] for r in rooms)
    if name == "inspect_room":
        room = data["room"]
        devices = "、".join(
            f'{d["display_name"]}({d["device_id"]})' for d in room["devices"]
        )
        return f'{room["display_name"]} → {devices}'
    if name == "inspect_device":
        device = data["device"]
        return (f'{device["display_name"]} state={json.dumps(device["state"], ensure_ascii=False)}'
                f'  actions={shape_actions(device["actions"])}')
    if name == "execute_action":
        return (f'state_after={json.dumps(data["state_after"], ensure_ascii=False)}'
                f'  verified={data.get("verified")}  changed={data.get("changed")}')
    if name == "finish":
        return f'{data.get("summary")}（{data.get("outcome")}）'
    return brief(data, 200)


def show_row(row: dict) -> None:
    """把一条轨迹按人话摊开：家、用户话、隐藏任务、逐轮交互。"""
    turns = row["record"]["turns"]
    scenario = row["scenario"]
    home = scenario["home"]
    print(f"样本 {row['record']['scenario_id']}   类别 {row['category']}   "
          f"{len(turns)} 轮   标签 {row['labels']}   D6 {row.get('d6')}")

    # 这份家：按房间列设备与当前状态
    print("\n【这份家 s0】")
    devices = {d["device_id"]: d for d in home["devices"]}
    for room in home["rooms"]:
        print(f"  {room['display_name']}")
        for device_id in room["device_ids"]:
            device = devices[device_id]
            print(f"    {device['display_name']:<8} {device_id:<28} "
                  f"{brief(device['state'], 80)}")

    print(f"\n【用户说】{scenario['user_request']}")
    print(f"【隐藏任务（模型看不见）】{brief(scenario['task'], 300)}")

    # 逐轮：这一轮调了什么工具、拿到什么、状态怎么变
    print("\n【逐轮交互】")
    for turn in turns:
        call = turn["tool_calls"][0]
        print(f"  第 {turn['turn']} 轮  {call['name']} {brief(call['arguments'], 120)}")
        for event in turn["events"]:
            result = event["result"]
            if result.get("error"):
                print(f"            → 报错 {brief(result['error'], 120)}")
            else:
                print(f"            → {shape_result(event['tool_name'], result.get('data'))}")
            if event.get("state_diff"):
                print(f"            → 状态变化 {brief(event['state_diff'], 140)}")
        if call["name"] == "finish":
            break


def show_messages(row: dict) -> None:
    """打印实际发给模型的消息清单，并检查家里状态有没有混进 prompt。"""
    messages = build_messages(row)
    print(f"共 {len(messages)} 条消息：system 1 条 + 用户话 1 条 + "
          f"{len(messages) - 2} 条逐轮往返\n")
    print(f"{'序号':>4}  {'角色':<10}{'字符数':>8}  开头")
    for index, message in enumerate(messages):
        head = message["content"].replace("\n", " ")[:64]
        print(f"{index:>4}  {message['role']:<10}{len(message['content']):>8}  {head}")

    # 关键验证：具体房间名、设备 id 是不是只在模型自己问出来之后才出现
    print("\n这几个串分别出现在第几条消息里：")
    for probe in ["device_kitchen_fridge", "厨房冰箱", "room_kitchen", "7.5"]:
        hits = [i for i, m in enumerate(messages) if probe in m["content"]]
        where = "、".join(str(i) for i in hits) if hits else "从未出现"
        print(f"  {probe:<24} {where}")


def main() -> None:
    """入口：选样本、重建 prompt、逐轮或单轮实测。"""
    parser = argparse.ArgumentParser(description="回放真实轨迹量端侧耗时")
    parser.add_argument("--host", default="http://127.0.0.1:8080", help="llama-server 地址")
    parser.add_argument("--sample", default="sc_T1_001", help="样本 id（scenario_id）")
    parser.add_argument("--mode", choices=["single", "traj"], default="traj", help="单轮或整条回放")
    parser.add_argument("--max-tokens", type=int, default=32, help="每轮最多生成多少 token")
    parser.add_argument("--no-cache", action="store_true", help="禁用前缀 KV 复用")
    parser.add_argument("--tag", default="", help="写日志时附加的标签，例如模型名")
    parser.add_argument("--show", action="store_true", help="只把这条轨迹摊开看，不连手机")
    parser.add_argument("--messages", action="store_true", help="打印实际发给模型的消息清单，不连手机")
    parser.add_argument(
        "--warmup",
        choices=["none", "short", "system"],
        default="short",
        help="预热方式：none 不预热；short 打一个 1 token 的短请求（只为升频）；"
             "system 先把 system 段灌进 KV（这才是真正的预热）",
    )
    parser.add_argument(
        "--skip-rounds",
        type=int,
        default=0,
        help="把前 N 步的完整上下文先打一次当预热（这段固定头就进了 KV），"
             "计时从第 N 步开始。N=1 等于跳过 observe_home 那一步，"
             "从它给出回答之后的下一步起算",
    )
    parser.add_argument("--dry-run", action="store_true", help="只打印要发的请求，不连手机")
    parser.add_argument("--list", action="store_true", help="只列出样本与轮数")
    args = parser.parse_args()

    rows = read_rows(DATASET)
    if args.list:
        for row in rows:
            if len(row["record"]["turns"]) == 5 and row["category"] == "T1":
                print(row["record"]["scenario_id"], row["category"], len(row["record"]["turns"]))
        return

    row = next(r for r in rows if r["record"]["scenario_id"] == args.sample)

    # 只看不测：打印完直接退出，不碰网络
    if args.messages:
        show_messages(row)
        return

    if args.show:
        show_row(row)
        return

    messages = build_messages(row)
    turns = row["record"]["turns"]

    # 单轮模式只在最后一步的完整上下文上量一次，这是最长的那一轮
    pairs = (len(messages) - 2) // 2
    if args.mode == "single":
        # 注意括号：必须先把 (len-2)//2 算出来再乘 2，
        # 否则 * 与 // 同级左结合会把整条消息列表都算进切片。
        prefix = messages[: 2 + 2 * pairs]
        steps = [prefix]
        skip = 0
    else:
        skip = min(max(args.skip_rounds, 0), pairs)
        steps = [messages[: 2 + 2 * k] for k in range(skip, pairs + 1)]

    if args.dry_run:
        print(f"样本 {args.sample}：共 {pairs + 1} 步，跳过前 {skip} 步")
        if skip:
            print(f"  预热的 prompt = 前 {2 + 2 * skip} 条消息，"
                  f"{sum(len(m['content']) for m in messages[: 2 + 2 * skip])} 字符")
        for index, step in enumerate(steps):
            chars = sum(len(m["content"]) for m in step)
            print(f"  第 {skip + index} 步计时：{len(step)} 条消息，{chars} 字符，"
                  f"末条角色 {step[-1]['role']}")
        return

    # 预热：短请求只为 CPU 升频；system 预热会把 A_policy + 工具表那段灌进 KV，
    # 之后每条轨迹的首轮都只剩用户那一句要算
    if args.warmup == "short":
        chat(args.host, [{"role": "user", "content": "预热"}], 1, True)
    elif args.warmup == "system":
        chat(args.host, [{"role": "system", "content": messages[0]["content"]}], 1, True)

    # 固定头预热：把前 skip 步的完整上下文先打一次，计时从第 skip 步开始。
    # 预热请求的 prompt 必须与下一步完全一致，前缀才可能被复用。
    prewarm_ms = None
    if skip:
        started = time.perf_counter()
        chat(args.host, messages[: 2 + 2 * skip], 1, True)
        prewarm_ms = (time.perf_counter() - started) * 1000
        print(f"固定头预热 {skip} 步：{prewarm_ms / 1000:.1f} s（不计入下面的统计）")

    records = []
    for index, step in enumerate(steps):
        payload = chat(args.host, step, args.max_tokens, not args.no_cache)
        row_summary = summarize(payload, skip + index)
        row_summary["text_tokens"] = count_tokens(
            args.host, "".join(m["content"] for m in step)
        )
        records.append(row_summary)
        print(f"  第 {index} 轮完成：TTFT {row_summary['ttft_ms']} ms", flush=True)

    print()
    print_table(records)
    total_prefill_ms = sum(r["prefill_ms"] for r in records)
    total_wall_ms = sum(r["wall_ms"] for r in records)
    print()
    print(f"轮数 {len(records)}；prefill 合计 {total_prefill_ms/1000:.1f} s；墙钟合计 {total_wall_ms/1000:.1f} s")
    print(f"prompt token 合计 {sum(r['prompt_tokens'] for r in records)}")
    if prewarm_ms is not None:
        print(f"其中固定头预热另外花了 {prewarm_ms/1000:.1f} s（发生在计时区间之前）")
    if records:
        print(f"单轮平均墙钟 {total_wall_ms/len(records)/1000:.1f} s，"
              f"单轮平均 prefill {total_prefill_ms/len(records)/1000:.1f} s")

    LOGDIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    tag = "nocache" if args.no_cache else "cache"
    name = f"{args.sample}_{args.mode}_{tag}"
    if args.tag:
        name += "_" + args.tag
    out = LOGDIR / f"{name}_{stamp}.json"
    out.write_text(
        json.dumps({"args": vars(args), "turns": len(turns), "skip_rounds": skip,
                    "prewarm_ms": prewarm_ms, "records": records},
                   ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"已写入 {out}")


if __name__ == "__main__":
    main()
