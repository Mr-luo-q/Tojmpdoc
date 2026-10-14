# tools/mock-llama-server.py 说明文档

## 一、为什么需要这个脚本

`bench-server.ps1` 要解析 llama-server 返回的分段计时数据。但验证这个解析逻辑有个现实障碍：手机可能没连着（USB 拔了、或者和电脑不在同一网段），而电脑上也没有 llama-server 可跑。

直接拿真机测，等于「验证依赖运气」。所以写一个**返回同构响应**的 mock 服务：接口路径、JSON 字段名、数值量级都和真 llama-server 一致，这样解析和渲染这条链可以随时离线验证。

```text
                          真实链路
  手机 llama-server  ──HTTP──►  bench-server.ps1  ──►  分段计时表
        ▲
        │ 换成 mock（响应结构相同，数值固定）
        │
  mock-llama-server.py  ──HTTP──►  bench-server.ps1  ──►  分段计时表
                          离线可跑，输出可断言
```

## 二、输入输出

**输入**：无参数。固定监听 `127.0.0.1:8099`。选 8099 而不是 8080，是为了避免和本机可能已经存在的真实服务撞端口。

**输出**：四个端点的响应，全部为固定值。

| 端点 | 返回内容 |
|---|---|
| `GET /health` | `{"status":"ok"}` |
| `GET /v1/models` | 模型列表，meta 里带 `n_ctx=2048`、`n_params=1777088000`、`n_vocab=151936`、`ftype=Q4_K - Medium` |
| `POST /v1/chat/completions` | 回复内容 + 完整的 `timings` 字段 |
| `GET /metrics` | 两行 Prometheus 文本格式指标 |
| 其他路径 | HTTP 404 |

计时数值刻意取固定值，这样脚本输出可以预期、便于人工核对：

```text
字段                        值          换算校验
──────────────────────────────────────────────────────────────
prompt_n                    35          提示词 token 数
prompt_ms                   605.0       35 / 0.605s = 57.85 t/s ✓
prompt_per_second           57.85
predicted_n                 24          生成 token 数
predicted_ms                1266.0      24 / 1.266s = 18.96 t/s ✓
predicted_per_second        18.96
cache_n                     0           无缓存命中
```

**TTFT（首 token 时间）** 由 `bench-server.ps1` 自己算，mock 不提供：

```text
TTFT = prompt_ms + predicted_per_token_ms
     = 605.0 + 52.75
     = 657.75 ms
```

## 三、内部结构

模块分三段：计时常量、模型元信息常量、请求处理器。

### TIMINGS / MODELS 常量

放在模块级而非写在处理函数里，是为了让「期望值」集中在一处。改动这两个常量就等于改变测试基准，脚本输出随之变化。

### Handler 类

继承 `BaseHTTPRequestHandler`，四个方法各司其职：

```text
_send(code, payload, ctype)   统一发包。自动判断 payload 是 str 还是 dict，
                              分别按文本或 JSON 编码，并写 Content-Length。
                              抽出来是为了不在各分支重复写响应头。

do_GET()                      按 self.path 分发三个只读端点，未知路径 404。

do_POST()                     只处理 /v1/chat/completions。必须先读掉
                              请求体再回包，否则客户端可能读到连接被重置。

log_message()                 覆写为空实现。基类默认会把每个请求打到 stderr，
                              测试输出会全是噪音。
```

### 启动方式

```powershell
python tools\mock-llama-server.py
```

前台运行，`Ctrl+C` 退出。因为它只是测试替身，不需要常驻。

## 四、配套用法

两个终端配合：

```powershell
# 终端 1：起 mock
python tools\mock-llama-server.py

# 终端 2：让 bench-server.ps1 打 mock（注意端口是 8099）
powershell -NoProfile -ExecutionPolicy Bypass -File .\bench-server.ps1 -ServerHost 127.0.0.1 -Port 8099 -MaxTokens 24
```

预期看到的关键数值：prefill 57.85 t/s、decode 18.96 t/s、TTFT 657.75 ms。

## 五、已实测的结果

| 验证项 | 结果 |
|---|---|
| `bench-server.ps1` 语法检查 | PASS |
| 目标不可达时的错误分支 | 正确打印「连不上服务」并退出码 1 |
| 执行策略拦截 | 本机需加 `-ExecutionPolicy Bypass`（未签名脚本） |
| mock 成功路径 | 见下节实测记录 |

## 六、局限

**不复现真实服务的随机性。** 计时是固定值，所以它只能验证「解析与渲染正确」，不能用来评估真实性能。真实性能必须打真机。

**不实现流式响应（SSE）。** `bench-server.ps1` 用的是非流式请求，所以 mock 也只回整体 JSON。将来若脚本改用 `stream: true`，这个 mock 需要同步扩展。

**不校验请求内容。** 它读掉请求体就丢弃，不检查提示词或参数是否符合预期。
