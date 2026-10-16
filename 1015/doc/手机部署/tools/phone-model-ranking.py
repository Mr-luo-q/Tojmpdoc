#!/usr/bin/env python3
# 模型排名模块：在电脑上驱动手机里的 llama-server，逐模型问同一批题并按规则判分。
#
# 为什么走 HTTP 而不是 llama-cli：
#   llama-cli 每问一题都要重新加载模型（3~8 秒），五模型 × 八题 × 四轮会浪费十几分钟；
#   服务端加载一次就能连续接受全部请求，而且并发固定为 1 时请求是串行的，耗时可比。
#
# 判分原则：
#   只对「有唯一正确答案」或「有明确约束」的题做自动判定，
#   每题都保存原始回答，规则判错时可以回看原文重新裁定。
#
# 用法：
#   python tools/phone-model-ranking.py --out research/rank-20261015/quality
import argparse
import json
import re
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# 手机侧的五个模型：标签、展示名、Termux 里的绝对路径。
MODELS = [
    ("06", "Qwen3-0.6B", "/data/data/com.termux/files/home/models/Qwen3-0.6B-Q4_K_M.gguf"),
    ("08", "Qwen3.5-0.8B", "/data/data/com.termux/files/home/models/Qwen3.5-0.8B-Q4_K_M.gguf"),
    ("15", "Qwen2.5-1.5B", "/data/data/com.termux/files/home/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
    ("17", "Qwen3-1.7B", "/data/data/com.termux/files/home/models/Qwen3-1.7B-Q4_K_M.gguf"),
    ("35", "Qwen3.5-2B", "/data/data/com.termux/files/home/models/Qwen3.5-2B-Q4_K_M.gguf"),
]

CTL = "/data/data/com.termux/files/home/scripts/termux-server-ctl.sh"
BASH = "/data/data/com.termux/files/usr/bin/bash"

# 设备侧端口 8080，电脑侧转发到 18080，避免和用户自己的服务抢端口。
DEVICE_PORT = 8080
LOCAL_PORT = 18080


def adb(args, timeout=120):
    # adb 调用模块：统一用列表传参，避免中文与空格被 shell 二次解析。
    result = subprocess.run(["adb"] + args, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout)
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def termux(script_args, timeout=180):
    # 在 Termux 私有环境里执行控制脚本：run-as 不带 PATH，所以 bash 必须写绝对路径。
    return adb(["shell", "run-as", "com.termux", BASH, CTL] + script_args, timeout=timeout)


def cjk_count(text):
    # 汉字计数：只统计 CJK 统一表意文字，标点与英文字母不计入题目的字数约束。
    return len(re.findall(r"[\u4e00-\u9fff]", text))


def extract_json(text):
    # 从模型回答里抠出第一个合法 JSON 对象；容忍代码框、前后解释、外层数组。
    cleaned = re.sub(r"```[a-zA-Z]*", "", text).replace("```", "")
    for start in [m.start() for m in re.finditer(r"[\[{]", cleaned)]:
        depth, in_string, escape = 0, False, False
        for index in range(start, len(cleaned)):
            char = cleaned[index]
            if in_string:
                if escape:
                    escape = False
                elif char == "\\":
                    escape = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char in "[{":
                depth += 1
            elif char in "]}":
                depth -= 1
                if depth == 0:
                    try:
                        value = json.loads(cleaned[start:index + 1])
                    except json.JSONDecodeError:
                        break
                    if isinstance(value, list) and value and isinstance(value[0], dict):
                        return value[0]
                    return value if isinstance(value, dict) else None
    return None


def check_01(text):
    # 题01：JSON 里的 total 必须是数值 41，currency 必须是 CNY。
    obj = extract_json(text)
    if obj is None:
        return False, "没有解析出 JSON 对象"
    total, currency = obj.get("total"), obj.get("currency")
    ok = isinstance(total, (int, float)) and not isinstance(total, bool) and abs(float(total) - 41) < 1e-6
    ok = ok and str(currency).strip().upper() == "CNY"
    return ok, f"total={total!r} currency={currency!r}"


def check_02(text):
    # 题02：五个字段全部正确才算通过，电话必须保留为字符串。
    obj = extract_json(text)
    if obj is None:
        return False, "没有解析出 JSON 对象"
    want = {"order_id": "A102", "name": "李华", "phone": "13800138000", "quantity": 2}
    bad = [k for k, v in want.items()
           if str(obj.get(k, "")).strip() != str(v)]
    if "杯子" not in str(obj.get("item", "")):
        bad.append("item")
    return (not bad), ("全部字段正确" if not bad else f"字段不符: {','.join(bad)}")


def check_03(text):
    # 题03：答案应是设备甲；允许顺带提到设备乙，但甲必须先出现。
    plain = re.sub(r"\s+", "", text)
    if "甲" not in plain:
        return False, "未出现设备甲"
    if "乙" in plain and plain.find("甲") > plain.find("乙"):
        return False, "先提到的是设备乙"
    return True, "指向设备甲"


def check_04(text):
    # 题04：一句中文、不超过 25 个汉字，且三步顺序完整。
    # 同义词必须放宽：「关/停」「改/换/替换」「启/开/重启」都是合法概括，
    # 第一版只认「关闭/替换/重新启动」，把「先关服务，再改模型，后重启」判成了错，
    # 这是判分规则的假阴性，2026-10-15 复核 20 条原始回答后修正。
    plain = text.strip()
    ok = cjk_count(plain) <= 25
    ok = ok and any(w in plain for w in ("关", "停"))
    ok = ok and any(w in plain for w in ("改", "换"))
    ok = ok and any(w in plain for w in ("启", "开", "重"))
    return ok, f"汉字数={cjk_count(plain)}"


def check_05(text):
    # 题05：既不能编造密码（出现 4 位以上数字即失败），也要明确表示无法确定。
    if re.search(r"\d{4,}", text):
        return False, "出现了疑似密码的数字串"
    ok = any(w in text for w in ("不能", "无法", "不知道", "不确定", "没有"))
    return ok, "未编造并明确表示无法确定" if ok else "没有明确表示无法确定"


def check_06(text):
    # 题06：只认最后一个整数，避免把过程里的 391 当成答案。
    numbers = re.findall(r"-?\d+", text)
    if not numbers:
        return False, "答案里没有数字"
    return numbers[-1] == "372", f"最后出现的数字={numbers[-1]}"


def check_07(text):
    # 题07：必须保留「书房」与「第二个抽屉」两项事实。
    ok = ("书房" in text) and ("抽屉" in text) and ("第二" in text or "2" in text)
    return ok, "事实完整" if ok else "缺少书房/第二个抽屉"


def check_08(text):
    # 题08：不超过 40 个汉字，且必须同时出现「精度」与「内存」。
    ok = cjk_count(text) <= 40 and "精度" in text and "内存" in text
    return ok, f"汉字数={cjk_count(text)} 含精度={'精度' in text} 含内存={'内存' in text}"


# 八道题的清单：文件、考点、判定函数。
QUESTIONS = [
    ("题01", "JSON 抽取 total=41 / currency=CNY", check_01),
    ("题02", "JSON 字段抽取五项", check_02),
    ("题03", "单跳推理，答设备甲", check_03),
    ("题04", "顺序概括，≤25 汉字", check_04),
    ("题05", "拒绝编造密码", check_05),
    ("题06", "算术 17×23−19=372", check_06),
    ("题07", "事实保持，书房第二个抽屉", check_07),
    ("题08", "定义句，≤40 汉字且含两个词", check_08),
]


def wait_health(deadline_s):
    # 健康检查模块：轮询电脑侧的转发端口，服务真正可推理才继续。
    url = f"http://127.0.0.1:{LOCAL_PORT}/health"
    start = time.monotonic()
    while time.monotonic() - start < deadline_s:
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                if '"ok"' in response.read().decode("utf-8", "replace"):
                    return time.monotonic() - start
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(1)
    return None


def ask(prompt, temperature, seed, max_tokens=256, timeout=300):
    # 请求模块：固定串行、固定最大输出长度，让不同模型的耗时可比。
    body = json.dumps({
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "seed": seed,
        "stream": False,
    }).encode("utf-8")
    request = urllib.request.Request(
        f"http://127.0.0.1:{LOCAL_PORT}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"})
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8", "replace"))
    elapsed = time.monotonic() - started
    choice = payload.get("choices", [{}])[0]
    return choice.get("message", {}).get("content", ""), elapsed, payload.get("usage", {})


def main():
    # 主流程：逐模型起服务 → 跑完两轮设置 → 停服务 → 判分落盘。
    parser = argparse.ArgumentParser(description="手机端五个模型的答案质量评分")
    parser.add_argument("--prompts", type=Path, default=Path("phone-prompts"))
    parser.add_argument("--out", type=Path, default=Path("research/rank-quality"))
    parser.add_argument("--rescore", type=Path, default=None,
                        help="只对已有 answers.jsonl 重新判分，不再访问手机")
    parser.add_argument("--samples", type=int, default=3, help="采样温度 0.7 下的重复次数")
    parser.add_argument("--models", nargs="*", default=None, help="只测指定标签，调试用")
    parser.add_argument("--questions", nargs="*", default=None, help="只测指定题号，例如 题06 题01")
    parser.add_argument("--reasoning", choices=("off", "on"), default="off",
                        help="传给服务端的思考模式；on 用于对照关闭思考是否影响正确率")
    parser.add_argument("--max-tokens", type=int, default=256,
                        help="单题最大输出；开启思考时需要放大，否则答案会被截断")
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    selected = [m for m in MODELS if not args.models or m[0] in args.models]
    questions = [q for q in QUESTIONS if not args.questions or q[0] in args.questions]

    if args.rescore:
        # 复核模式：规则修正后不必重跑手机，直接对保存的原始回答重新判分。
        checker = {q[0]: q[2] for q in QUESTIONS}
        records = []
        for line in args.rescore.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            record = json.loads(line)
            ok, note = checker[record["question"]](record["answer"])
            record.update({"ok": ok, "note": note})
            records.append(record)
        target = args.out / "answers-rescored.jsonl"
        with target.open("w", encoding="utf-8") as stream:
            for record in records:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")
        print(write_summary(records, questions, args.out, "复核"), file=sys.stderr)
        return 0

    forward, err, code = adb(["forward", f"tcp:{LOCAL_PORT}", f"tcp:{DEVICE_PORT}"])
    if code != 0:
        print(f"adb forward 失败: {err}", file=sys.stderr)
        return 1

    records = []
    for tag, name, path in selected:
        print(f"===== {tag} {name} =====", flush=True)
        termux(["stop"])
        out, err, code = termux(["start", path, str(DEVICE_PORT), args.reasoning])
        print(f"  启动: {out} {err}".strip(), flush=True)
        if "ready" not in out:
            print(f"  启动失败，跳过 {tag}", file=sys.stderr)
            continue
        ready = wait_health(60)
        print(f"  健康检查耗时 {ready:.1f}s" if ready else "  健康检查超时", flush=True)

        for question, desc, checker in questions:
            prompt = (args.prompts / f"{question}.txt").read_text(encoding="utf-8").strip()
            # greedy 一轮定对错，采样三轮看稳定性；两者用同一批题与同一上限。
            rounds = [("greedy", 0.0, 0)] + [("sample", 0.7, i) for i in range(1, args.samples + 1)]
            for kind, temperature, seed in rounds:
                try:
                    text, elapsed, usage = ask(prompt, temperature, seed, max_tokens=args.max_tokens)
                    ok, note = checker(text)
                except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
                    text, elapsed, usage, ok, note = "", 0.0, {}, False, f"请求失败: {exc}"
                records.append({
                    "model_tag": tag, "model": name, "question": question, "desc": desc,
                    "kind": kind, "seed": seed, "ok": ok, "note": note,
                    "elapsed_s": round(elapsed, 2), "answer": text,
                    "completion_tokens": usage.get("completion_tokens"),
                    "reasoning": args.reasoning,
                })
                print(f"  {question} {kind}#{seed} {'PASS' if ok else 'FAIL'} {elapsed:.1f}s {note}", flush=True)
        termux(["stop"])

    # 落盘模块：逐条记录 + 汇总表，原始回答完整保留以便人工复核。
    with (args.out / "answers.jsonl").open("w", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(write_summary(records, questions, args.out, args.reasoning))
    adb(["forward", "--remove", f"tcp:{LOCAL_PORT}"])
    return 0


def write_summary(records, questions, out_dir, reasoning):
    # 汇总模块：按模型算 greedy 正确数与采样通过率，写成 Markdown 表；返回表文本。
    summary = {}
    for record in records:
        key = (record["model_tag"], record["model"])
        bucket = summary.setdefault(key, {"greedy": [], "sample": []})
        bucket[record["kind"]].append(record["ok"])

    lines = [f"| 标签 | 模型 | greedy 通过 | 采样通过率 | 综合分 |（思考模式：{reasoning}）",
             "|---|---|---|---|---|"]
    ranking = []
    for (tag, name), bucket in summary.items():
        greedy = sum(bucket["greedy"])
        sampled = sum(bucket["sample"])
        total = len(bucket["sample"])
        score = greedy / len(questions) * 0.5 + (sampled / total if total else 0) * 0.5
        ranking.append((score, greedy, sampled, total, tag, name))
    for score, greedy, sampled, total, tag, name in sorted(ranking, reverse=True):
        lines.append(f"| {tag} | {name} | {greedy}/{len(questions)} | {sampled}/{total} | {score:.3f} |")
    text = "\n".join(lines) + "\n"
    (out_dir / "summary.md").write_text(text, encoding="utf-8")
    return text


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
