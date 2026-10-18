"""模拟 llama-server 的最小 HTTP 服务，用于离线验证 bench-server.ps1 的解析逻辑。

只实现 bench-server.ps1 会调用的四个端点：
  GET  /health              -> {"status":"ok"}
  GET  /v1/models           -> 带 meta 字段的模型列表
  POST /v1/chat/completions -> 带 timings 字段的回复（数值固定，便于断言）
  GET  /metrics             -> Prometheus 文本格式

计时数值刻意用固定值，这样脚本输出可预期：
  prompt_n=35  prompt_ms=605.0   prompt_per_second=57.85
  predicted_n=24 predicted_ms=1266.0 predicted_per_second=18.96
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

# 固定的计时数值，让输出可被断言
TIMINGS = {
    "cache_n": 0,
    "prompt_n": 35,
    "prompt_ms": 605.0,
    "prompt_per_token_ms": 17.2857,
    "prompt_per_second": 57.85,
    "predicted_n": 24,
    "predicted_ms": 1266.0,
    "predicted_per_token_ms": 52.75,
    "predicted_per_second": 18.96,
}

MODELS = {
    "data": [{
        "id": "mock",
        "meta": {"n_ctx": 2048, "n_params": 1777088000, "n_vocab": 151936,
                 "ftype": "Q4_K - Medium"},
    }]
}


class Handler(BaseHTTPRequestHandler):
    """按路径返回预设响应，模拟 llama-server 的接口形态。"""

    def _send(self, code, payload, ctype='application/json'):
        """统一发送响应，避免各分支重复写头部。"""
        body = payload.encode('utf-8') if isinstance(payload, str) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        """处理三个只读端点，未知路径返回 404。"""
        if self.path == '/health':
            self._send(200, {"status": "ok"})
        elif self.path == '/v1/models':
            self._send(200, MODELS)
        elif self.path == '/metrics':
            self._send(200, "# mock metrics\nllamacpp:requests_total 1\n"
                            "llamacpp:tokens_predicted_total 24\n", 'text/plain')
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        """处理对话请求，回一个与真实服务同构的响应。"""
        if self.path != '/v1/chat/completions':
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get('Content-Length', 0))
        self.rfile.read(length)  # 读掉请求体，避免连接被挂住
        self._send(200, {
            "choices": [{"finish_reason": "stop", "index": 0,
                         "message": {"role": "assistant",
                                     "content": "这是 mock 服务返回的测试内容。"}}],
            "model": "mock",
            "object": "chat.completion",
            "usage": {"completion_tokens": 24, "prompt_tokens": 35, "total_tokens": 59},
            "timings": TIMINGS,
        })

    def log_message(self, *args):
        """屏蔽默认的逐请求日志，保持测试输出干净。"""
        pass


if __name__ == '__main__':
    srv = HTTPServer(('127.0.0.1', 8099), Handler)
    print('mock llama-server 已启动: http://127.0.0.1:8099')
    srv.serve_forever()
