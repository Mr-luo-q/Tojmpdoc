# MNN 2026-10-19 实验归档

这次实验验证 MNN 3.6.1 在 Redmi K70E 上的 CPU 推理。完整结论写入 [MNN部署实测报告.md](../../MNN部署实测报告.md)，本文件只记录归档内容和数据字段。

## 文件结构

```text
research/mnn-20261019/
  mnn_chat_0_8_3.apk              MNN Chat 0.8.3 官方 APK，41,834,292 bytes
  model_market.json               MNN Chat 的模型市场快照，版本 22
  prompt-zh.txt                   中文端到端验证提示词
  src/MNN-3.6.1.zip               MNN 源码归档
  src/extracted/MNN-3.6.1/       解压后的源码
  toolchain/                      Android NDK r28b 及其压缩包
  build/                          Android arm64 CPU 构建目录
  model/Qwen3.5-0.8B-MNN/         官方导出的 MNN 文本/视觉模型
  device-results/                 手机端 llm_bench 原始 JSON
  termux*.png                     Termux 实测截图
```

## MNN 模型文件

| 文件 | 字节数 | 作用 |
|---|---:|---|
| `llm.mnn` | 2,148,136 | LLM 计算图 |
| `llm.mnn.weight` | 470,382,614 | 4-bit 主权重 |
| `llm.mnn.json` | 5,343,877 | 权重与量化描述 |
| `tokenizer.txt` | 6,465,727 | tokenizer |
| `visual.mnn` | 251,528 | 视觉编码器计算图 |
| `visual.mnn.weight` | 63,043,212 | 视觉编码器权重 |
| `llm_config.json` | 8,691 | Qwen3.5 模板与模型结构 |
| `config.json` | 652 | MNN 运行时配置 |
| `export_args.json` | 1,044 | 导出和量化参数 |
| `configuration.json` | 46 | 模型类型声明 |

主权重 SHA-256：

```text
4E25EF4CBFB49A33013D17300C2F68CD9C9CE8F2E3F7B947FD2C574EC297CA5E
```

## 运行时配置摘要

`config.json` 的当前值：

| 字段 | 值 | 含义 |
|---|---|---|
| `backend_type` | `cpu` | 只走 CPU |
| `thread_num` | `4` | 4 个线程 |
| `precision` | `low` | 低精度优先 |
| `memory` | `low` | 低内存策略 |
| `max_new_tokens` | `8192` | 单次最大生成上限 |
| `sampler_type` | `mixed` | 组合采样 |
| `enable_thinking` | `true` | 默认打开思考模式 |

`export_args.json` 的关键字段：

| 字段 | 值 |
|---|---|
| `quant_bit` | `4` |
| `quant_block` | `64` |
| `lm_quant_bit` | `4` |
| `lm_quant_block` | `64` |
| `export` | `mnn` |
| `hqq` | `true` |

`llm_config.json` 表明模型类型为 `qwen3_5`，`hidden_size` 为 1024，`is_visual` 为 true，并包含完整的 Jinja 聊天模板、图像 token 和 EOS 定义。文本基准实际只使用 LLM 部分，视觉权重没有参与本轮测速。

## 模型市场快照

`model_market.json` 是 MNN Chat 0.8.3 自带的模型目录，顶层字段包括：

```text
version         22
models          文本和多模态 LLM 条目
tts_models      语音合成模型
asr_models      语音识别模型
libs            额外运行库，例如 QNN
tagTranslations 标签中文翻译
```

本次只使用其中 `Qwen3.5-0.8B-MNN` 条目。市场清单会随 App 版本变化，不能把该文件当作永久模型索引。

## 原始结果

| 文件 | 内容 |
|---|---|
| `device-results/mnn-smoke.json` | 首次单次冒烟 |
| `device-results/mnn-t4-r3.json` | 4 线程，3 次重复，主结果 |
| `device-results/mnn-t6-r3.json` | 6 线程，3 次重复 |
| `device-results/mnn-t8-r3.json` | 8 线程，3 次重复 |
| `device-results/mnn-t4-r3-postllama.json` | 高温状态复测 |
| `device-results/mnn-t4-r1.json` | 短停后再次复测 |
| `device-results/mnn-d*.json` | 0/512/2048/4096 提示长度结果 |

JSON 结构：

```json
{
  "model": "Qwen3.5-0.8B-MNN",
  "backend": "CPU",
  "threads": 4,
  "precision": 2,
  "memory": 2,
  "flashAttention": 1,
  "results": [
    {
      "type": "prefill",
      "prompt_len": 128,
      "tps": 200.98,
      "std": 0.31,
      "loading_time": 0.99
    },
    {
      "type": "decode",
      "generate_len": 64,
      "tps": 47.97,
      "std": 0.89,
      "loading_time": 1.02
    }
  ]
}
```

`tps` 是该组测试的 token/s，`std` 是重复测量标准差，`loading_time` 是模型加载时间。MNN 的 `-p` 和 `-n` 与 llama.cpp 的 `-pg` 不是同一个参数协议，跨框架比较时只引用最终的 prefill/decode 数值。
