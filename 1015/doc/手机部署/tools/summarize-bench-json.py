#!/usr/bin/env python3
# 结果汇总模块：把 termux-bench-qwen35-08.sh 产出的逐组 JSON 聚成 Markdown 对照表。
#
# 与 summarize-speed-results.py 的区别：
#   那个读的是 phone-speed-bench.py 的 results.tsv（A/B 交错写在一张表里），
#   这个读的是「一组一个 JSON」的 llama-bench 原始输出，适合手工编排的测量脚本。
import argparse
import json
import re
import statistics
from pathlib import Path
import sys


def load_rows(paths):
    # 读入模块：每个 JSON 文件一组，文件名即标签；损坏或空文件单独计数不参与统计。
    rows, broken = [], []
    for path in paths:
        for file in sorted(path.glob("*.json")):
            try:
                data = json.loads(file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                broken.append(f"{file.name}: {exc}")
                continue
            tag = file.stem
            for row in data:
                avg = row.get("avg_ts")
                if not isinstance(avg, (int, float)) or avg <= 0:
                    broken.append(f"{file.name}: 缺 avg_ts")
                    continue
                rows.append({
                    "tag": tag,
                    "model": row.get("model_filename", "").rsplit("/", 1)[-1],
                    "shape": "pp" if row.get("n_gen", 0) == 0 else "tg",
                    "depth": row.get("n_depth", 0),
                    "threads": row.get("n_threads"),
                    "fa": row.get("flash_attn"),
                    "b": row.get("n_batch"),
                    "ub": row.get("n_ubatch"),
                    "avg_ts": float(avg),
                    "stddev_ts": float(row.get("stddev_ts") or 0.0),
                    "samples": len(row.get("samples_ts") or []),
                })
    return rows, broken


def tag_parts(tag):
    # 标签解析模块：约定 <组>-<模型>，例如 s1-06-a、b2-35、d2048-15。
    # 组名可以是 s1 / b2 / d512 这类任意短标识，模型固定两位数字。
    match = re.match(r"^(.+)-(\d{2})(?:-.+)?$", tag)
    return (match.group(1), match.group(2)) if match else (tag, "?")


def median(values):
    # 统计模块：样本少于两个时退化为单值，避免 statistics 抛异常。
    return statistics.median(values)


def render(rows, title):
    # 渲染模块：逐次原始值 → 分组矩阵 → 跨组合并中位数，避免只看合并后的数字。
    lines = [f"# {title}", ""]
    for row in rows:
        round_name, model_tag = tag_parts(row["tag"])
        row["round"], row["model_tag"] = round_name, model_tag

    lines += ["## 逐次原始值", "",
              "| 标签 | 模型 | 负载 | 深度 | 线程 | fa | avg t/s | stddev | 样本 |",
              "|---|---|---|---|---|---|---|---|---|"]
    for row in sorted(rows, key=lambda r: (r["depth"], r["round"], r["model_tag"], r["shape"])):
        lines.append("| {tag} | {model} | {shape} | {depth} | {threads} | {fa} | {avg:.2f} | {sd:.2f} | {n} |".format(
            tag=row["tag"], model=row["model"], shape=row["shape"], depth=row["depth"],
            threads=row["threads"], fa=row["fa"], avg=row["avg_ts"], sd=row["stddev_ts"], n=row["samples"]))

    model_tags = sorted({row["model_tag"] for row in rows})

    # 分组矩阵模块：同一组、同一负载形状、同一深度下，每个模型取中位数并排显示。
    buckets = {}
    for row in rows:
        key = (row["depth"], row["round"], row["shape"])
        buckets.setdefault(key, {}).setdefault(row["model_tag"], []).append(row["avg_ts"])

    lines += ["", "## 分组矩阵（中位数）", "",
              "| 深度 | 组 | 负载 | " + " | ".join(model_tags) + " |",
              "|---|---|---|" + "---|" * len(model_tags)]
    for key in sorted(buckets):
        depth, round_name, shape = key
        per = buckets[key]
        cells = [f"{median(per[t]):.2f}" if per.get(t) else "—" for t in model_tags]
        lines.append(f"| {depth} | {round_name} | {shape} | " + " | ".join(cells) + " |")

    # 合并模块：把同一个深度与负载下的所有组一起取中位数，作为跨组排名的依据。
    merged = {}
    for row in rows:
        merged.setdefault((row["depth"], row["shape"]), {}).setdefault(row["model_tag"], []).append(row["avg_ts"])
    lines += ["", "## 跨组合并（同深度同负载的全部运行取中位数）", "",
              "| 深度 | 负载 | " + " | ".join(model_tags) + " |",
              "|---|---|" + "---|" * len(model_tags)]
    for key in sorted(merged):
        depth, shape = key
        per = merged[key]
        cells = []
        for tag in model_tags:
            values = per.get(tag)
            cells.append(f"{median(values):.2f} (n={len(values)})" if values else "—")
        lines.append(f"| {depth} | {shape} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main():
    # 参数模块：接受一个或多个结果目录，输出可直接贴进文档的 Markdown。
    parser = argparse.ArgumentParser(description="汇总 llama-bench JSON 结果")
    parser.add_argument("dirs", nargs="+", type=Path)
    parser.add_argument("--title", default="Qwen3-0.6B vs Qwen3.5-0.8B 测速汇总")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    rows, broken = load_rows(args.dirs)
    if not rows:
        print("没有可用的结果行", file=sys.stderr)
        return 1
    text = render(rows, args.title)
    if broken:
        text += "\n## 被跳过的文件\n\n" + "\n".join(f"- {item}" for item in broken) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8")
        print(f"已写入 {args.out}，有效行 {len(rows)}，跳过 {len(broken)}", file=sys.stderr)
    else:
        sys.stdout.reconfigure(encoding="utf-8")
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
