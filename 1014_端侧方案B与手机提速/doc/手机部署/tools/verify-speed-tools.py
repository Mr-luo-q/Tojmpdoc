#!/usr/bin/env python3
# 离线验证模块：只验证调度、失败归档、来源完整性和SSE协议，不产生手机性能结论。
import argparse
import contextlib
import csv
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def load_module(name, filename):
    # 按路径导入含连字符的工具文件，验证使用实际实现。
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bench = load_module("speed_bench", "phone-speed-bench.py")
stream = load_module("speed_stream", "measure-phone-stream.py")
HELP = "--device --no-kv-offload --no-op-offload --repack --flash-attn --cache-type-k --n-depth"


class ProtocolHandler(BaseHTTPRequestHandler):
    # 本机SSE夹具：分别发送空角色、思考、中文答案与最终usage，故意让它们时间错开。
    def log_message(self, format, *args):
        # 关闭HTTP默认访问日志，保持验证输出清晰。
        pass

    def do_GET(self):
        # 提供健康和模型接口，用于模型不匹配测试。
        data = {"status": "ok"} if self.path == "/health" else {"data": [{"id": "fixture-Qwen3-0.6B"}]}
        encoded = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_POST(self):
        # 用真实HTTP连接发出协议夹具；所有数字仅为测试字段。
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.last_request = request
        self.send_response(200)
        self.send_header("Content-Type", "application/json" if self.path == "/non-sse" else "text/event-stream")
        self.end_headers()
        if self.path == "/non-sse":
            self.wfile.write(b"{}")
            return
        events = [{"choices": [{"delta": {"role": "assistant"}}]},
                  {"choices": [{"delta": {"reasoning_content": "fixture"}}]},
                  {"choices": [{"delta": {"content": "你好"}}]},
                  {"choices": [{"delta": {"content": "。"}, "finish_reason": "stop"}],
                   "usage": {"prompt_tokens": 7, "completion_tokens": 3, "prompt_tokens_details": {"cached_tokens": 2}}}]
        if self.path == "/native":
            events = [{"content": "你好"}, {"content": "", "stop": True, "stop_type": "eos", "tokens_evaluated": 7, "tokens_cached": 2,
                       "timings": {"predicted_n": 3, "predicted_per_second": 12.5, "prompt_n": 5}}]
        for event in events:
            self.wfile.write(("data: " + json.dumps(event, ensure_ascii=False) + "\n\n").encode("utf-8"))
            self.wfile.flush()
            time.sleep(0.015)
        if self.path not in ("/incomplete", "/native"):
            self.wfile.write(b"data: [DONE]\n\n")


class SpeedTests(unittest.TestCase):
    # 测试集合：通过可观测结果验证行为，而不把夹具数值写作设备性能。
    @classmethod
    def setUpClass(cls):
        # 为SSE解析启动只绑定本机的HTTP服务器。
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), ProtocolHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        # 结束测试服务器并关闭端口，不留下后台进程。
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def test_command_cpu_and_depth(self):
        # 检查CPU控制选项和上下文深度不会因套件丢失。
        command = bench.make_command("llama-bench", Path("fixture.gguf"), bench.plans("baseline", [0])[0][2], 2048, 128, 64, 3)
        for option, value in [("-ngl", "0"), ("-dev", "none"), ("-nkvo", "1"), ("-nopo", "1"), ("-d", "2048")]:
            self.assertEqual(command[command.index(option) + 1], value)

    def test_attention_comparisons(self):
        # 验证先独立比较FA，再在FA开启条件下比较K/V量化。
        experiments = bench.plans("attention", [0, 2048])
        self.assertEqual(len(experiments), 6)
        for label, depth, a, b in experiments:
            changed = {key for key in a if a[key] != b[key]}
            self.assertEqual(changed, {"fa"} if label == "flash-attn" else {"ctk", "ctv"})

    def test_reject_bad_results(self):
        # 空、损坏及无吞吐输出不能被认为成功。
        for raw in ("[]", "{}", "broken", '[{"avg_ts": 0}]', '[{"avg_ts": null}]', '[{"avg_ts": NaN}]', '[{"avg_ts": Infinity}]'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                bench.parse_result(raw)

    def bench_fixture(self, behavior, suite="baseline"):
        # 创建临时数据并模拟外部基准进程，保留真实的工具输出目录供断言。
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        model = root / "fixture.gguf"
        model.write_bytes(b"test data; not a GGUF model")
        args = SimpleNamespace(models=[str(model)], bench="fixture-bench", suite=suite, depths=[0], blocks=1,
                               prompt=128, gen=64, repetitions=3, dry_run=False, out=root / "out", label="fixture-only", timeout=1, cooldown=0)
        with patch.object(bench, "busy_processes", return_value=[]), patch.object(bench, "capture_metadata", return_value="fixture-only"), \
             patch.object(bench.subprocess, "run", side_effect=behavior), contextlib.redirect_stdout(io.StringIO()):
            status = bench.run(args)
        with (args.out / "results.tsv").open(encoding="utf-8", newline="") as file:
            rows = list(csv.DictReader(file, delimiter="\t"))
        return status, rows, args.out

    def test_abba_archive(self):
        # 验证完整ABBA顺序及每轮原始输出均被落盘。
        def process(command, **kwargs):
            # 模拟进程成功，JSON速度是固定夹具值。
            raw = HELP if "--help" in command else '[{"n_prompt":128,"n_gen":0,"avg_ts":10,"stddev_ts":1}]'
            return subprocess.CompletedProcess(command, 0, raw, "fixture")
        status, rows, output = self.bench_fixture(process, "repack")
        self.assertEqual(status, 0)
        self.assertEqual([row["arm"] for row in rows], ["A", "B", "B", "A"])
        self.assertEqual(len(list(output.glob("*-stdout.log"))), 4)

    def test_baseline_failure_stops(self):
        # 基线失效时不能继续比较候选或输出伪吞吐。
        def process(command, **kwargs):
            # 模拟空结果的基线进程。
            return subprocess.CompletedProcess(command, 0, HELP if "--help" in command else "[]", "fixture")
        status, rows, output = self.bench_fixture(process, "repack")
        self.assertEqual(status, 1)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["avg_ts"], "")

    def test_timeout_preserves_partial_output(self):
        # 超时写入FAILED且保留截断原文。
        def process(command, **kwargs):
            # 模拟子进程计时超时，不能伪造完整JSON。
            if "--help" in command:
                return subprocess.CompletedProcess(command, 0, HELP, "")
            raise subprocess.TimeoutExpired(command, 1, output=b"partial", stderr=b"blocked")
        status, rows, output = self.bench_fixture(process)
        self.assertEqual(status, 1)
        self.assertEqual((output / "001-stdout.log").read_text(), "partial")
        self.assertTrue(rows[0]["status"].startswith("FAILED:"))

    def test_candidate_failure_remains_visible(self):
        # 不支持的候选必须保留失败行，后续基线照常归档。
        def process(command, **kwargs):
            # 用重排参数模拟候选配置不支持。
            if "--help" in command:
                return subprocess.CompletedProcess(command, 0, HELP, "")
            candidate = command[command.index("--repack") + 1] == "0"
            return subprocess.CompletedProcess(command, 2 if candidate else 0,
                                               "" if candidate else '[{"avg_ts":10,"n_prompt":128,"n_gen":0}]',
                                               "unsupported fixture" if candidate else "fixture")
        status, rows, output = self.bench_fixture(process, "repack")
        self.assertEqual(status, 1)
        self.assertEqual([row["arm"] for row in rows], ["A", "B", "B", "A"])
        self.assertTrue(all(row["status"].startswith("FAILED:") and row["avg_ts"] == "" for row in rows if row["arm"] == "B"))

    def stream_fixture(self, endpoint):
        # 请求真实本机SSE服务器，返回解析后的结果。
        with tempfile.TemporaryDirectory() as temporary:
            return stream.measure(self.base + endpoint, {"prompt": "中文测试"}, Path(temporary) / "raw.log", 5)

    def test_sse_visible_content(self):
        # 空role与reasoning都不能提前算成答案首字，且UTF-8答案不损坏。
        result = self.stream_fixture("/chat")
        self.assertTrue(result["complete"])
        self.assertEqual(result["content"], "你好。")
        self.assertLess(result["first_event_s"], result["first_reasoning_s"])
        self.assertLess(result["first_reasoning_s"], result["first_content_s"])
        self.assertEqual(result["completion_tokens"], 3)
        self.assertEqual(result["cached_tokens"], 2)

    def test_incomplete_not_success(self):
        # 没有DONE的截断聊天不能被标为完整响应。
        self.assertFalse(self.stream_fixture("/incomplete")["complete"])

    def test_native_completion(self):
        # 裸completion的stop事件和timings字段按自己的协议处理。
        result = self.stream_fixture("/native")
        self.assertTrue(result["complete"])
        self.assertEqual(result["server_predicted_tps"], 12.5)
        self.assertEqual(result["prompt_tokens"], 7)
        self.assertEqual(result["evaluated_prompt_tokens"], 5)
        self.assertEqual(result["cached_tokens"], 2)

    def test_non_sse_rejected(self):
        # 非流式响应直接拒绝，避免TTFT测量误用。
        with self.assertRaises(ValueError):
            self.stream_fixture("/non-sse")

    def test_model_mismatch(self):
        # 核对失败发生在创建结果目录和发出推理请求之前。
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "should-not-exist"
            argv = ["measure-phone-stream.py", "--base-url", self.base, "--expected-model", "wrong-model",
                    "--prompt-file", "missing.txt", "--out", str(output)]
            with patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(stream.main(), 1)
            self.assertFalse(output.exists())


def main():
    # 验证入口：先核对归档SHA-256，再运行离线协议测试并输出可保存的摘要。
    parser = argparse.ArgumentParser(description="离线验证复现工具；不运行手机模型")
    parser.add_argument("--sources", type=Path, default=Path("research/speed-20261014/sources"))
    args = parser.parse_args()
    count = 0
    rows = {}
    for name in ("manifest.tsv", "manifest-selected.tsv"):
        with (args.sources / name).open(encoding="utf-8", newline="") as file:
            rows.update({row["id"]: row for row in csv.DictReader(file, delimiter="\t")})
    for row in rows.values():
        if row["status"] == "OK":
            digest = hashlib.sha256((args.sources / row["file"]).read_bytes()).hexdigest()
            if digest != row["sha256"]:
                raise ValueError(f"来源哈希不符：{row['id']}")
            count += 1
    print(f"Source hashes verified: {count}; unavailable sources: {len(rows) - count}", flush=True)
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SpeedTests))
    return int(not result.wasSuccessful())


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
