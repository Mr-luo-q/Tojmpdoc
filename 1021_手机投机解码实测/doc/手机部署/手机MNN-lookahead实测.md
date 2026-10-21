# 手机 MNN lookahead 实测 · Redmi K70E

## 一、结论

MNN 的 lookahead 在手机上确实有效，而且和 llama.cpp 的 draft 投机解码是两条完全不同的曲线。

| 场景 | 0.6B 基线 → lookahead | 2B 基线 → lookahead |
|---|---|---|
| 逐字复述 | 46.59 → **127.22 t/s（2.73 倍）** | 22.30 → **45.55 t/s（2.04 倍）** |
| 自然问答 | 47.14 → 33.62 t/s（慢 29%） | 23.51 → 25.95 t/s（草稿长度 4，+10.4%） |

lookahead 只对“输出大量复用输入”的文本有正收益。逐字复述时输入里已经有完整的 n-gram，草稿几乎不用花模型前向；普通问答没有这种结构，验证开销直接变成净亏损。

草稿长度 8 是这台机器上的可用上限。再往上设 12 或 16，实测直接生成 0 个 token，`prefill=inf / decode=nan`，不能靠加长草稿继续换速度。

## 二、环境与口径

| 项 | 值 |
|---|---|
| 手机 | Redmi K70E，2311DRK48C，Android 16，11.6 GB 内存 |
| 运行时 | MNN 3.6.1，Android arm64，CPU 静态链接，无额外 `.so` |
| 二进制 | `llm_demo`，NDK r28b 构建，2026-10-19 产物 |
| 模型 | Qwen3-0.6B-MNN（int4，451 MB）、Qwen3.5-2B-MNN（int4，1.18 GB） |
| 线程 | `thread_num=4` |
| 采样 | `sampler_type=greedy`，关闭 thinking |
| 生成长度 | 48 token |
| 温度 | 测试前 24.5°C，测试后 29.2°C，电量 93% |

四份配置只改 lookahead 字段，其余完全一致：

```json
{
  "speculative_type": "lookahead",
  "draft_predict_length": 8,
  "draft_match_strictness": "low",
  "draft_selection_rule": "freqxlen",
  "ngram_match_maxlen": 4,
  "ngram_update": true
}
```

两条提示词与 llama 那轮相同：

```text
natural.txt   用三句话解释什么是模型量化。         20 token
repeat.txt    要求逐字复述一段 79 token 的中文      79 token
```

每个配置跑 2 次；2B 自然问答因为首次基线明显偏低，补到 5 次。表中是均值，速度取自 `llm_demo` 打印的 `decode speed`，prefill 不受 lookahead 影响，单独列出。

## 三、为什么 lookahead 不需要第二个模型

MNN 的 lookahead 草稿来自 n-gram，而不是另一个语言模型：

```text
输入 prompt / lookup_file
        │
        ▼
  建 n-gram 索引（默认最长匹配 4 个 token）
        │
        ▼
  用当前历史 token 查后缀 → 拼出 draft_predict_length 个候选
        │
        ▼
  目标模型一次前向并行验证候选 → 接受最长匹配前缀
```

所以它没有 0.6B 草稿模型的 23 ms/token 成本，只有“验证批次”的成本。逐字复述时草稿命中率极高，验证一次能吐出多个 token，收益就出来了；自然问答查不到长匹配，草稿长度为 0，仍然要付验证路径的固定开销，于是变慢。

这也是它和 llama.cpp draft 的分水岭：后者无论有没有命中都要先跑草稿模型，手机上 0.6B 草稿本身就是 20 多毫秒一个 token，接受率再高也补不回来。

## 四、0.6B 结果

| 提示 | 基线 | 草稿 2 | 草稿 4 | 草稿 8 |
|---|---:|---:|---:|---:|
| 逐字复述 | 46.59 | 84.47 | 104.97 | **127.22** |
| 自然问答 | 47.14 | 41.08 | 39.23 | 33.62 |

逐字复述的加速比：

```text
草稿 2   84.47 / 46.59 = 1.81 倍
草稿 4  104.97 / 46.59 = 2.25 倍
草稿 8  127.22 / 46.59 = 2.73 倍
```

草稿 8 的 4 次原始值是 129.62、120.65、129.93、128.66，均值 127.22；第一次略低，后三次稳定在 128–130。

自然问答相反，草稿越长越慢：41.08 → 39.23 → 33.62。没有可查的 n-gram，长草稿只是把无效候选送进验证。

## 五、2B 结果

| 提示 | 基线 | 草稿 2 | 草稿 4 | 草稿 8 |
|---|---:|---:|---:|---:|
| 逐字复述 | 22.30 | 31.90 | 41.63 | **45.55** |
| 自然问答 | 23.51 | 20.94 | **25.95** | 18.75 |

逐字复述：草稿 8 是 2.04 倍，草稿 4 是 1.87 倍。2B 的最优草稿长度和 0.6B 一样，都是 8。

自然问答的基线有一个冷机异常值：5 次分别是 16.80、22.93、22.91、23.87、23.74。表中基线 23.51 取后 3 次；若把首次 16.80 也算进去，均值是 22.05，草稿 4 会显示成 +18%，那是被异常值放大的。草稿 8 反而降到 18.75，说明自然问答下草稿过长会把收益吃回去。

2B 的 prefill 基本不变：自然问答约 90 t/s，逐字复述约 79 t/s。lookahead 只作用于 decode。

## 六、草稿长度上限

同一套配置把 `draft_predict_length` 改成 12 或 16：

| 模型 | 提示 | 草稿 12 | 草稿 16 |
|---|---|---|---|
| Qwen3-0.6B | 逐字复述 | 0 token，decode=nan | 0 token，decode=nan |
| Qwen3.5-2B | 逐字复述 | 1 token，decode=inf | 未测 |

这不是“太慢”，而是直接没有正常生成。按 8 封顶即可，不要继续加长。具体是验证长度超限还是 KV cache 形状问题，本轮没有定位到源码行。

## 七、和 llama.cpp draft 的对照

同一台手机、同一类提示：

| 运行时 | 组合 | 逐字复述 | 自然问答 |
|---|---|---:|---:|
| MNN lookahead | 0.6B 单模型 | **2.73 倍** | 0.71 倍 |
| llama.cpp draft | 0.6B → 1.7B | 0.62 倍 | 0.52 倍 |
| MNN lookahead | 2B 单模型 | **2.04 倍** | 1.10 倍 |
| llama.cpp draft | 0.8B → 2B | 未测 | 0.68 倍 |

差异不在“投机解码”这个名字，而在草稿从哪来：MNN 的草稿是查表，llama 的草稿是一次真实前向。手机 CPU 上，后者付不起。

## 八、复现

手机上的目录：

```text
~/mnn/llm_demo                          MNN arm64 静态二进制
~/mnn/models/Qwen3-0.6B-MNN/            config_phone_base.json / lookahead2/4/8.json
~/mnn/models/Qwen3.5-2B-MNN/            同上
~/spec-bench/natural.txt
~/spec-bench/repeat.txt
```

命令：

```bash
cd ~/mnn
./llm_demo models/Qwen3-0.6B-MNN/config_phone_lookahead8.json \
  $HOME/spec-bench/repeat.txt 48

./llm_demo models/Qwen3.5-2B-MNN/config_phone_base.json \
  $HOME/spec-bench/natural.txt 48
```

最后一个参数是最大生成 token 数；不传会进入交互聊天。原始 CSV 在 `research/mnn-20261019/spec-test/phone-mnn-results-*.csv`。

## 九、风险与未验证

本轮只测一台 K70E、四线程、greedy、48 token，2–5 次重复，温度 24.5→29.2°C。没有测 2/6/8 线程、Q8 量化、KV 量化、FlashAttention 开关，也没有测持续负载后的热衰减。

lookahead 的输出 token 数与基线不完全一致：0.6B 是 51 对 48，2B 草稿 4 是 52 对 48，2B 草稿 8 自然问答只有 30 个就遇到 EOS。速度仍按实际生成 token 数计算，但输出长度变化会影响任务级的主观感受，不能只看 t/s。

MNN 的 `DUMP_PROFILE_INFO` 默认关闭，这版二进制没有打印草稿接受率，所以本文只有端到端速度，没有“接受率 / 验证次数”的分解。要补这两个指标需要重新编译带宏的 Android 版本。
