#!/usr/bin/env python3
# 流式测量模块：按 SSE 内容事件记录首字时间，保留完整响应并核对服务模型标识。
import argparse
import csv
from datetime import datetime
import json
import sys
from pathlib import Path
import time
import urllib.request
import urllib.error


def get_json(url, timeout):
    # 健康与模型核对模块：读取服务原始 JSON，不假定启动脚本已完成模型切换。
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.load(response)


def measure(url, payload, output, timeout):
    # SSE 读取模块：role/空 delta 只算首事件，非空 content 才算用户可见首字。
    encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(url, data=encoded, headers={"Content-Type": "application/json", "Accept": "text/event-stream"})
    start = time.perf_counter()
    first_event = first_content = first_reasoning = None
    content, reasoning, events = [], [], []
    usage, timings, native_fields, finish, complete = {}, {}, {}, "", False
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if "text/event-stream" not in response.headers.get("Content-Type", ""):
            raise ValueError("响应不是 SSE，不能将非流式完成时间计为 TTFT")
        with output.open("w", encoding="utf-8") as raw:
            for line in response:
                text = line.decode("utf-8").strip()
                raw.write(text + "\n")
                raw.flush()
                if not text.startswith("data:"):
                    continue
                data = text[5:].strip()
                if data == "[DONE]":
                    complete = True
                    break
                event = json.loads(data)
                now = time.perf_counter() - start
                events.append(event)
                if first_event is None:
                    first_event = now
                if "error" in event:
                    raise ValueError(f"SSE 返回错误：{event['error']}")
                usage.update(event.get("usage") or {})
                timings.update(event.get("timings") or {})
                for key in ("tokens_evaluated", "tokens_cached"):
                    if key in event:
                        native_fields[key] = event[key]
                choices = event.get("choices") or []
                if choices:
                    delta = choices[0].get("delta") or {}
                    piece = delta.get("content") or ""
                    thought = delta.get("reasoning_content") or delta.get("reasoning") or ""
                    finish = choices[0].get("finish_reason") or finish
                else:
                    piece, thought = event.get("content") or "", ""
                if piece:
                    first_content = now if first_content is None else first_content
                    content.append(piece)
                if thought:
                    first_reasoning = now if first_reasoning is None else first_reasoning
                    reasoning.append(thought)
                if event.get("stop") is True:
                    finish = event.get("stop_type") or "stop"
                    complete = True
                    break
    elapsed = time.perf_counter() - start
    generated = usage.get("completion_tokens", timings.get("predicted_n"))
    rate = None
    if isinstance(generated, (int, float)) and generated > 1 and first_content is not None and elapsed > first_content:
        rate = (generated - 1) / (elapsed - first_content)
    result = {"complete": complete, "first_event_s": first_event, "first_content_s": first_content,
              "first_reasoning_s": first_reasoning, "total_s": elapsed, "completion_tokens": generated,
              "after_first_wall_tps": rate, "server_predicted_tps": timings.get("predicted_per_second"),
              "prompt_tokens": usage.get("prompt_tokens", native_fields.get("tokens_evaluated")),
              "evaluated_prompt_tokens": timings.get("prompt_n"),
              "cached_tokens": (usage.get("prompt_tokens_details") or {}).get("cached_tokens", native_fields.get("tokens_cached", timings.get("cache_n"))),
              "finish_reason": finish, "content": "".join(content), "reasoning": "".join(reasoning),
              "usage": usage, "timings": timings}
    output.with_suffix(".txt").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main():
    # 命令行与归档模块：支持真实聊天和裸 completion 缓存实验，两个结果不能混为同一负载。
    parser = argparse.ArgumentParser(description="手机 SSE 首字延迟测量")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--expected-model", required=True, help="/v1/models 中应包含的模型标识片段")
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--endpoint", choices=("chat", "completion"), default="chat")
    parser.add_argument("--cache", choices=("on", "off"), default="off", help="仅控制裸 completion 的 cache_prompt")
    parser.add_argument("--max-tokens", type=int, default=128)
    parser.add_argument("--repeat", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--label", default="unrecorded")
    parser.add_argument("--out", type=Path, default=Path("stream-results") / datetime.now().strftime("%Y%m%d-%H%M%S"))
    args = parser.parse_args()
    if args.repeat <= 0 or args.max_tokens <= 0 or args.timeout <= 0:
        parser.error("repeat、max-tokens 和 timeout 必须为正数")
    base = args.base_url.rstrip("/")
    try:
        get_json(base + "/health", min(args.timeout, 10))
        models = get_json(base + "/v1/models", min(args.timeout, 10))
        ids = [item.get("id", "") for item in models.get("data", [])]
        if not any(args.expected_model in name for name in ids):
            raise ValueError(f"加载模型与预期不符：{ids}")
        prompt = args.prompt_file.read_text(encoding="utf-8-sig")
        if not prompt.strip():
            raise ValueError("提示词文件为空")
        args.out.mkdir(parents=True, exist_ok=False)
        (args.out / "models.txt").write_text(json.dumps(models, ensure_ascii=False, indent=2), encoding="utf-8")
        if args.endpoint == "chat":
            path = "/v1/chat/completions"
            payload = {"model": next(name for name in ids if args.expected_model in name), "messages": [{"role": "user", "content": prompt}],
                       "stream": True, "stream_options": {"include_usage": True}, "max_tokens": args.max_tokens,
                       "temperature": 0, "seed": 42, "chat_template_kwargs": {"enable_thinking": False}}
        else:
            path = "/completion"
            payload = {"prompt": prompt, "stream": True, "n_predict": args.max_tokens, "temperature": 0,
                       "seed": 42, "cache_prompt": args.cache == "on", "id_slot": 0}
        (args.out / "request.txt").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        fields = ["round", "label", "endpoint", "cache", "status", "first_event_s", "first_content_s", "first_reasoning_s",
                  "total_s", "prompt_tokens", "evaluated_prompt_tokens", "cached_tokens", "completion_tokens", "server_predicted_tps", "after_first_wall_tps", "finish_reason"]
        failures = 0
        with (args.out / "results.tsv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", extrasaction="ignore")
            writer.writeheader()
            for index in range(args.repeat):
                try:
                    result = measure(base + path, payload, args.out / f"{index + 1:03d}-sse.log", args.timeout)
                    status = "OK" if result["complete"] and result["content"].strip() else "FAILED:no-complete-visible-content"
                except (OSError, ValueError, urllib.error.URLError) as exc:
                    result, status = {}, f"FAILED:{exc}"
                failures += int(status != "OK")
                result.update(round=index + 1, label=args.label, endpoint=args.endpoint, cache=args.cache if args.endpoint == "completion" else "server-default", status=status)
                writer.writerow(result)
                stream.flush()
                print(f"round={index + 1} status={status} first_content_s={result.get('first_content_s')}", flush=True)
        return int(failures > 0)
    except (OSError, ValueError, urllib.error.URLError) as exc:
        print(f"FAILED:{exc}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
