#!/usr/bin/env python3
# 结果汇总模块：把 phone-speed-bench.py 的逐调用 TSV 聚成对照表，并检查方向一致性。
import argparse
import csv
from pathlib import Path
import statistics
import sys


def read_rows(paths):
    # 读入模块：一个结果目录一个 results.tsv，跳过失败行但记录条数。
    rows, failed = [], 0
    for path in paths:
        result_file = path / "results.tsv" if path.is_dir() else path
        # 用 utf-8-sig 容忍 BOM：经 Windows 管道或文本编辑器中转时可能被加上。
        with result_file.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                if row["status"] != "OK" or not row["avg_ts"]:
                    failed += 1
                    continue
                row["avg_ts"] = float(row["avg_ts"])
                row["stddev_ts"] = float(row["stddev_ts"]) if row["stddev_ts"] else 0.0
                row["source"] = result_file.parent.name
                rows.append(row)
    return rows, failed


def group(rows):
    # 分组模块：同一个模型、实验、深度、负载形状的 A/B 必须成对比较，不能跨负载合并。
    buckets = {}
    for row in rows:
        key = (row["model"], row["experiment"], int(row["depth"]), row["n_prompt"], row["n_gen"])
        buckets.setdefault(key, {}).setdefault(row["arm"], []).append(row)
    return buckets


def compare(buckets):
    # 统计模块：取中位数，并给出「每个块的方向是否一致」这一条独立证据。
    lines = []
    for key in sorted(buckets):
        model, experiment, depth, n_prompt, n_gen = key
        arms = buckets[key]
        shape = f"pp{n_prompt}" if n_prompt != "0" else f"tg{n_gen}"
        a = [row["avg_ts"] for row in arms.get("A", [])]
        b = [row["avg_ts"] for row in arms.get("B", [])]
        if not a:
            continue
        a_med = statistics.median(a)
        a_txt = f"{a_med:.2f}"
        if not b:
            lines.append((model, experiment, depth, shape, a_txt, "—", "—", "—", len(a), 0))
            continue
        b_med = statistics.median(b)
        gain = (b_med / a_med - 1) * 100
        blocks = sorted({row["block"] for row in arms["A"]} & {row["block"] for row in arms["B"]})
        consistent, detail = True, []
        for block in blocks:
            av = [row["avg_ts"] for row in arms["A"] if row["block"] == block]
            bv = [row["avg_ts"] for row in arms["B"] if row["block"] == block]
            if not av or not bv:
                continue
            delta = statistics.median(bv) - statistics.median(av)
            detail.append(f"{'+' if delta >= 0 else ''}{delta:.2f}")
            consistent &= (delta >= 0) == (gain >= 0)
        lines.append((model, experiment, depth, shape, a_txt, f"{b_med:.2f}", f"{gain:+.1f}%",
                      ("一致 " if consistent and len(detail) > 1 else "单块 ") + " ".join(detail), len(a), len(b)))
    return lines


def report(lines, sources, failed, label, output):
    # 输出模块：Markdown 表格，表头写明来源目录与失败条数，避免脱离上下文引用。
    text = [f"# 手机提速对照汇总", "",
            f"- 结果目录：{', '.join(str(s) for s in sources)}",
            f"- 条件标签：{label}",
            f"- 有效行：{len(lines)} 组；失败/跳过行：{failed}", "",
            "| 模型 | 实验 | 深度 | 形状 | A 中位数 t/s | B 中位数 t/s | B/A | 分块方向 | nA | nB |",
            "|---|---|---:|---|---:|---:|---:|---|---:|---:|"]
    for model, experiment, depth, shape, a, b, gain, detail, na, nb in lines:
        text.append(f"| {model} | {experiment} | {depth} | {shape} | {a} | {b} | {gain} | {detail} | {na} | {nb} |")
    text += ["", "A 是基线，B 是候选。方向一致指每个复验块的变化方向与总体中位数方向相同；只有单块时不做一致性判断。", ""]
    # 写文件用 UTF-8：Windows 控制台编码常与手机不一致，避免中文变成问号。
    output.write_text("\n".join(text), encoding="utf-8")
    return len(lines)


def main():
    # 命令行入口：接受任意多个结果目录，默认不做任何过滤。
    parser = argparse.ArgumentParser(description="汇总手机提速基准结果为 Markdown 对照表")
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--label", default="未标注条件")
    parser.add_argument("--out", type=Path, help="Markdown 输出文件；不给则打印到标准输出")
    args = parser.parse_args()
    for path in args.paths:
        if not path.exists():
            print(f"FAILED: 路径不存在 {path}")
            return 1
    rows, failed = read_rows(args.paths)
    if not rows:
        print("FAILED: 没有可用的 OK 结果行")
        return 1
    lines = compare(group(rows))
    if args.out:
        count = report(lines, args.paths, failed, args.label, args.out)
        print(f"groups={count} failed_rows={failed} out={args.out}")
    else:
        report(lines, args.paths, failed, args.label, Path("_summary_tmp.md"))
        print(Path("_summary_tmp.md").read_text(encoding="utf-8").encode("ascii", "replace").decode("ascii"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
