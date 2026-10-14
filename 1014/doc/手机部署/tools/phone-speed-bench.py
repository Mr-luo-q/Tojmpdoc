#!/usr/bin/env python3
# 手机基准模块：固定 CPU 路径，以 ABBA 顺序比较单一变量并保存原始结果。
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import threading
import time


def sha256_file(path):
    # 分块计算模型和二进制哈希，避免把大模型全部读入内存。
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def plans(suite, depths):
    # 每个实验只改变一个参数；注意力实验先比较 FA，再比较 KV 精度。
    base = {"t": "4", "fa": "off", "ctk": "f16", "ctv": "f16", "b": "512", "ub": "128", "repack": "1"}
    if suite == "baseline":
        return [("baseline", 0, base, None)]
    pairs = []
    if suite == "threads":
        pairs = [(f"t{t}", 0, base, dict(base, t=str(t))) for t in (2, 3, 6, 8)]
    elif suite == "batch":
        pairs = [(f"ub{ub}", 0, base, dict(base, ub=str(ub))) for ub in (64, 256, 512)]
    elif suite == "repack":
        pairs = [("repack-off", 0, base, dict(base, repack="0"))]
    elif suite == "attention":
        fa = dict(base, fa="on")
        for depth in depths:
            pairs.append(("flash-attn", depth, base, fa))
            for quant in ("q8_0", "q4_0"):
                pairs.append((f"kv-{quant}", depth, fa, dict(fa, ctk=quant, ctv=quant)))
    return pairs


def make_command(bench, model, settings, depth, prompt, gen, repetitions):
    # 基准使用独立 pp 和指定深度的 tg；禁止隐式 GPU 和 KV/算子卸载。
    command = [bench, "-m", str(model), "-ngl", "0", "-dev", "none", "-nkvo", "1", "-nopo", "1",
               "-p", str(prompt), "-n", str(gen), "-d", str(depth), "-r", str(repetitions), "-o", "json"]
    for key, value in settings.items():
        command.extend(["--repack" if key == "repack" else f"-{key}", value])
    return command


def parse_result(raw):
    # stdout 必须是 llama-bench JSON；日志损坏或缺失吞吐字段时拒绝生成成功行。
    data = json.loads(raw)
    if not isinstance(data, list) or not data:
        raise ValueError("llama-bench stdout 必须是非空 JSON 数组")
    for row in data:
        if not isinstance(row, dict) or not isinstance(row.get("avg_ts"), (int, float)) or not math.isfinite(row["avg_ts"]) or row["avg_ts"] <= 0:
            raise ValueError("结果缺少有效 avg_ts，不能认作完成")
    return data


def capture_metadata(bench, models, label):
    # 环境取证模块：保留系统版本、包版本、CPU 特性及文件哈希，不把不可读节点填成零。
    lines = [f"label={label}", f"utc={datetime.now(timezone.utc).isoformat()}", f"platform={os.name}"]
    for command in ([bench, "--version"], ["getprop", "ro.build.version.release"],
                    ["getprop", "ro.build.version.sdk"], ["getprop", "ro.soc.model"],
                    ["dpkg-query", "-W", "llama-cpp", "libc++"]):
        try:
            result = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=10)
            lines.append(f"command={command!r}\nrc={result.returncode}\n{result.stdout}{result.stderr}")
        except (OSError, subprocess.TimeoutExpired) as exc:
            lines.append(f"command={command!r}\nunavailable={exc}")
    for file in (Path("/proc/cpuinfo"), Path("/proc/meminfo")):
        try:
            lines.append(f"file={file}\n{file.read_text(errors='replace')}")
        except OSError as exc:
            lines.append(f"file={file}\nunavailable={exc}")
    for model in models:
        lines.append(f"model={model}\nbytes={model.stat().st_size}\nsha256={sha256_file(model)}")
    executable = Path(bench)
    if executable.is_file():
        lines.append(f"bench_sha256={sha256_file(executable)}")
    return "\n".join(lines)


def sample_frequency(stop, path, job):
    # 观察模块：每秒采样 0/4/7 号核；sysfs 值仅记为读数，不解释为真实平均频率。
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(["job", "elapsed_s", "cpu", "scaling_cur_freq_khz", "scaling_max_freq_khz"])
        start = time.monotonic()
        while not stop.is_set():
            for cpu in (0, 4, 7):
                values = []
                for name in ("scaling_cur_freq", "scaling_max_freq"):
                    try:
                        values.append(Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/{name}").read_text().strip())
                    except OSError:
                        values.append("unavailable")
                writer.writerow([job, round(time.monotonic() - start, 3), cpu, *values])
            stream.flush()
            stop.wait(1)


def busy_processes():
    # 并发检查模块：只检测可读的 /proc 项，遇到推理进程则要求使用者先停止它。
    found = []
    for entry in Path("/proc").glob("[0-9]*/comm"):
        try:
            name = entry.read_text().strip()
            if name in ("llama-bench", "llama-server", "llama-cli", "llama-completion"):
                found.append(f"{entry.parent.name}:{name}")
        except OSError:
            pass
    return found


def run(args):
    # 执行模块：先检查帮助、模型和并发，再逐组写入原文、采样与汇总；超时保留失败记录。
    models = [Path(name).expanduser().resolve() for name in args.models]
    experiments = plans(args.suite, args.depths)
    jobs = []
    for model in models:
        for experiment, depth, a, b in experiments:
            order = [("A", a)] if b is None else [("A", a), ("B", b), ("B", b), ("A", a)]
            for block in range(args.blocks):
                for arm, settings in order:
                    jobs.append((model, experiment, depth, block, arm, settings))
    if args.dry_run:
        for model, experiment, depth, block, arm, settings in jobs:
            print(json.dumps({"experiment": experiment, "depth": depth, "block": block, "arm": arm,
                              "command": make_command(args.bench, model, settings, depth, args.prompt, args.gen, args.repetitions)}, ensure_ascii=False))
        return 0
    for model in models:
        if not model.is_file():
            raise ValueError(f"模型不存在：{model}")
    busy = busy_processes()
    if busy:
        raise ValueError(f"先停止可见的推理进程，再测试：{busy}")
    help_result = subprocess.run([args.bench, "--help"], capture_output=True, text=True, errors="replace", timeout=20)
    help_text = help_result.stdout + help_result.stderr
    for option in ("--device", "--no-kv-offload", "--no-op-offload", "--repack", "--flash-attn", "--cache-type-k", "--n-depth"):
        if option not in help_text:
            raise ValueError(f"此版本缺少 {option}，不能复用本协议；请保留帮助并按报告构建固定版本")
    args.out.mkdir(parents=True, exist_ok=False)
    (args.out / "help.txt").write_text(help_text, encoding="utf-8")
    (args.out / "metadata.txt").write_text(capture_metadata(args.bench, models, args.label), encoding="utf-8")
    failures = 0
    with (args.out / "results.tsv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t")
        writer.writerow(["job", "model", "experiment", "depth", "block", "arm", "status", "n_prompt", "n_gen", "avg_ts", "stddev_ts", "elapsed_s", "settings"])
        for index, (model, experiment, depth, block, arm, settings) in enumerate(jobs):
            job = f"{index + 1:03d}"
            print(f"{job}/{len(jobs)} {model.name} {experiment} d={depth} {arm}", flush=True)
            command = make_command(args.bench, model, settings, depth, args.prompt, args.gen, args.repetitions)
            stop = threading.Event()
            observer = threading.Thread(target=sample_frequency, args=(stop, args.out / f"{job}-freq.tsv", job), daemon=True)
            observer.start()
            start = time.monotonic()
            status, rows, stdout, stderr = "OK", [], "", ""
            try:
                result = subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=args.timeout)
                stdout, stderr = result.stdout, result.stderr
                if result.returncode:
                    raise ValueError(f"exit={result.returncode}")
                rows = parse_result(stdout)
            except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
                status = f"FAILED:{exc}"
                failures += 1
                if isinstance(exc, subprocess.TimeoutExpired):
                    stdout = (exc.stdout or b"").decode("utf-8", errors="replace")
                    stderr = (exc.stderr or b"").decode("utf-8", errors="replace")
            finally:
                stop.set()
                observer.join(timeout=3)
            elapsed = round(time.monotonic() - start, 3)
            (args.out / f"{job}-stdout.log").write_text(stdout, encoding="utf-8")
            (args.out / f"{job}-stderr.log").write_text(stderr, encoding="utf-8")
            (args.out / f"{job}-command.txt").write_text(json.dumps(command, ensure_ascii=False), encoding="utf-8")
            for row in rows or [{}]:
                writer.writerow([job, model.name, experiment, depth, block, arm, status, row.get("n_prompt", ""), row.get("n_gen", ""),
                                 row.get("avg_ts", ""), row.get("stddev_ts", ""), elapsed, json.dumps(settings)])
            stream.flush()
            if not rows and arm == "A":
                print("基线失败，停止本次测试；请检查 stderr。", flush=True)
                break
            if index + 1 < len(jobs):
                time.sleep(args.cooldown)
    return int(failures > 0)


def main():
    # 参数模块：默认只跑基线，完整矩阵需明确选择，避免手机长时间无谓压测。
    parser = argparse.ArgumentParser(description="手机模型 CPU 提速复现；输出到新目录")
    parser.add_argument("--models", nargs="+", required=True)
    parser.add_argument("--bench", default="llama-bench")
    parser.add_argument("--suite", choices=("baseline", "threads", "attention", "batch", "repack"), default="baseline")
    parser.add_argument("--depths", type=int, nargs="+", default=[0, 2048])
    parser.add_argument("--prompt", type=int, default=128)
    parser.add_argument("--gen", type=int, default=64)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--blocks", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--cooldown", type=float, default=15)
    parser.add_argument("--label", default="standard-unrecorded-power-state")
    parser.add_argument("--out", type=Path, default=Path("speed-results") / datetime.now().strftime("%Y%m%d-%H%M%S"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if min(args.prompt, args.gen, args.repetitions, args.blocks) <= 0 or min(args.depths) < 0 or args.cooldown < 0 or args.timeout <= 0:
        parser.error("长度、重复数、块数、超时须为正数；深度与冷却不得为负数")
    try:
        return run(args)
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"FAILED: {exc}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
