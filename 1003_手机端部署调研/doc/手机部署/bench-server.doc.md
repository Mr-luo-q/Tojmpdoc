# bench-server.ps1 说明文档

## 一、解决的问题

llama-server 每次响应其实都带了分段计时，但它埋在一大坨 JSON 里。原始响应长这样：

```json
{
  "choices": [{"message": {"content": "模型量化是一种..."}}],
  "usage": {"completion_tokens": 24, "prompt_tokens": 35},
  "timings": {
    "prompt_n": 35,        "prompt_ms": 605.383,
    "prompt_per_token_ms": 17.29,  "prompt_per_second": 57.81,
    "predicted_n": 24,     "predicted_ms": 1266.101,
    "predicted_per_token_ms": 55.04, "predicted_per_second": 18.17,
    "cache_n": 0
  }
}
```

人关心的是「提示词处理多快、生成多快、第一个字多久出来」，但要从这堆字段里自己算，每次对话都来一遍不现实。这个脚本把它整理成一张对比表。

服务端**没有直接给出**首 token 时间（TTFT），脚本按这个关系算：

```text
TTFT = prompt_ms + predicted_per_token_ms
     = 提示词全部处理完的耗时 + 生成第一个 token 的耗时
```

这是「按下发送」到「屏幕出现第一个字」的实际等待，体感流畅度看的就是它。

## 二、输入

命令行参数：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `-ServerHost` | `127.0.0.1` | 服务器地址。打手机就传手机 IP |
| `-Port` | `8080` | 端口 |
| `-Prompt` | 用一句话说明什么是模型量化 | 测试用提示词 |
| `-MaxTokens` | `64` | 最多生成多少 token |
| `-Repeat` | `1` | 重复次数，大于 1 时额外输出平均值 |
| `-RawJson` | 关 | 加上则附带打印完整原始响应，排查用 |

脚本会依次访问三个端点取数据：`/health`（确认服务活着）、`/v1/models`（取模型元信息）、`/v1/chat/completions`（要计时）。

## 三、输出

以 mock 服务的实测输出为例（数值为 mock 的固定值）：

```text
==> 目标服务 http://127.0.0.1:8099
    健康检查：ok

模型信息
  ftype      : Q4_K - Medium
  参数量     : 1,777,088,000
  上下文     : 2048
  词表大小   : 151,936

请求参数
  提示词     : 用一句话说明什么是模型量化
  max_tokens : 24
  重复次数   : 2

回复内容
  这是 mock 服务返回的测试内容。

分段计时
轮次 墙钟耗时_ms prefill_tok prefill_ms prefill_tps decode_tok decode_ms decode_tps TTFT_ms 缓存命中tok
 1     8.2          35        605       57.85         24      1266      18.96   657.75       0
 2     1.8          35        605       57.85         24      1266      18.96   657.75       0

指标含义
  prefill / decode / TTFT / cache_n 各自的解释（略）

平均值
prefill_tps : 57.85
decode_tps  : 18.96
TTFT_ms     : 657.8

服务端指标 /metrics
  llamacpp:requests_total 1
  llamacpp:tokens_predicted_total 24
```

表格各列的含义：

```text
轮次          第几次采样（-Repeat 控制次数）
墙钟耗时_ms   脚本侧测的往返总耗时。注意它通常远小于 prefill+decode，
              因为 mock 是瞬间返回；打真机时这一列才有参考价值
prefill_tok   提示词的 token 数
prefill_ms    处理这批提示词花了多少毫秒
prefill_tps   提示词处理速度（tokens/s）
decode_tok    实际生成了多少 token
decode_ms     生成耗时
decode_tps    生成速度（tokens/s）
TTFT_ms       首 token 时间，脚本计算值
缓存命中tok   多轮对话中复用的 KV 长度，这部分不计入 prefill
```

## 四、内部函数

```text
函数                        职责
──────────────────────────────────────────────────────────────
Get-Num(obj, name)          安全取 JSON 数值。字段缺失或为 null 时返回 $null，
                            避免 PowerShell 抛异常中断整轮采样。

主流程                       1 探活 → 2 取元信息 → 3 构造请求 → 4 循环采样
                            → 5 打印回复 → 6 分段表 → 7 指标解释
                            → 8 平均值 → 9 /metrics → 10 原始 JSON（可选）
```

采样循环里 `temperature` 固定设 0，这样重复测试的输入条件一致，速度数据才可比。每次采样都用 `Stopwatch` 独立计时，而不是用总耗时除以次数。

## 五、实测验证状态

按 AGENTS.md 的要求区分三档：

**已验证的事实**

| 验证项 | 方式 | 结果 |
|---|---|---|
| 脚本语法 | AST 解析（带 BOM 后） | PASS |
| 服务不可达分支 | 打未监听地址 | 正确打印「连不上服务」，退出码 1 |
| 成功路径（离线） | 打 `tools/mock-llama-server.py` | 表格 / 平均值 / metrics 全部正确渲染，数值与 mock 固定值一致且换算自洽 |
| **成功路径（真机）** | **adb 转发后用本脚本打手机** | **跑通，退出码 0** |

真机实测输出（`-MaxTokens 64 -Repeat 3`）：

```text
轮次 墙钟耗时_ms prefill_tok prefill_ms prefill_tps decode_tok decode_ms decode_tps TTFT_ms 缓存命中tok
 1    2944.2         33      609.99     54.10         36     2280.82    15.35    673.35       0
 2    2642.1          1       81.07     12.33         36     2529.09    13.84    151.33      32
 3    3321.2          1       88.46     11.31         36     3209.42    10.91    177.61      32

平均值：prefill 25.91 t/s   decode 13.36 t/s   TTFT 334.1 ms
```

`/metrics` 也验证可用（需启动时加 `--metrics`），返回了 12 项指标：

```text
llamacpp:prompt_tokens_total 35
llamacpp:prompt_tokens_cached_total 64
llamacpp:tokens_predicted_total 108
llamacpp:predicted_tokens_seconds 13.0934
llamacpp:n_decode_total 108
...
```

**从这份数据能读出的东西**

第 2、3 轮的 `prefill_tok` 只有 1、而 `缓存命中tok` 是 32 —— 这精确展示了 KV 缓存的复用机制：重复相同提示词时，前 32 个 token 直接命中缓存，只需要处理新增的那 1 个。这也是为什么第 2、3 轮 prefill 的 tps 数值（12.33、11.31）看着很低却无妨：分母只有 1 个 token，不具可比性，**该看 TTFT 列**（151 ms、178 ms，比首轮的 673 ms 快得多）。

**待确认的风险**

decode 从首轮 15.35 递减到第 3 轮 10.91，当时判断为热降频，后经独立测试证实（见下）。
所以**单看这三次采样不能代表稳定性能**，需要标注设备热状态才有意义。

## 六、真机使用的两个环境坑

**adb 端口转发活不过一次工具调用。** 本机每次执行命令后 `adb server` 会被回收，`adb forward --list` 随之清空。所以必须把「建转发」和「跑脚本」放进同一次调用：

```powershell
adb -s <序列号> forward tcp:8080 tcp:8080
powershell -NoProfile -ExecutionPolicy Bypass -File .\bench-server.ps1
```

**手机与电脑可能不通网。** 实测手机 `172.18.209.84/17`、电脑 `172.18.145.29/17` 同网段但互相不可达（电脑连 IPv4 默认网关都没有），`adb tcpip 5555` 也连不上。所以只能走 adb 转发，不能直接填手机 IP。

## 七、两个必须知道的坑

**执行策略。** 本机 PowerShell 会拦住未签名脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\bench-server.ps1 -ServerHost 172.18.209.84
```

**文件编码。** 这个脚本必须保存为 **UTF-8 带 BOM**。Windows PowerShell 5.1 读 `.ps1` 时，若无 BOM 会按系统 ANSI（中文系统即 GBK）解码；中文注释被解成乱码后，行尾注释会把后面的参数一起吞掉，报出这种错：

```text
line 18: 函数参数列表中缺少 ")"
line 110: 哈希文本中的键后面缺少 "=" 运算符
```

这些报错位置和真实原因完全无关，很容易查错方向。用 `Set-Content -Encoding UTF8` 保存（PS 5.1 会自动加 BOM），或改用 PowerShell 7（默认按 UTF-8 读取）。

## 八、和 llama-bench 的分工

两者不重复，测的东西不同：

| 工具 | 位置 | 测什么 |
|---|---|---|
| `llama-bench` | 手机 Termux 内 | 纯性能基准。固定 pp512 / tg128 这类合成负载，多轮取平均，用于横向比较参数配置 |
| `bench-server.ps1` | 电脑上 | 真实请求的分段耗时。走完整 HTTP 链路，反映实际使用时的体验 |

调参找最优配置用 `llama-bench`；想知道「我这次提问到底等了多久、卡在哪一段」用这个脚本。
