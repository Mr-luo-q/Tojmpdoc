# 手机提速对照汇总

- 结果目录：D:\项目\手机部署\research\speed-20261014\device-20261014\15-threads, D:\项目\手机部署\research\speed-20261014\device-20261014\15-baseline
- 条件标签：1.5B, t2/3/6/8 vs t4, AC充电, enhance, 无风扇, 冷却10s
- 有效行：10 组；失败/跳过行：0

| 模型 | 实验 | 深度 | 形状 | A 中位数 t/s | B 中位数 t/s | B/A | 分块方向 | nA | nB |
|---|---|---:|---|---:|---:|---:|---|---:|---:|
| qwen2.5-1.5b-instruct-q4_k_m.gguf | baseline | 0 | tg64 | 18.67 | — | — | — | 1 | 0 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | baseline | 0 | pp128 | 28.12 | — | — | — | 1 | 0 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t2 | 0 | tg64 | 17.40 | 8.86 | -49.1% | 单块 -8.54 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t2 | 0 | pp128 | 26.21 | 12.50 | -52.3% | 单块 -13.71 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t3 | 0 | tg64 | 16.92 | 12.82 | -24.2% | 单块 -4.10 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t3 | 0 | pp128 | 24.39 | 17.98 | -26.3% | 单块 -6.41 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t6 | 0 | tg64 | 16.07 | 11.36 | -29.4% | 单块 -4.72 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t6 | 0 | pp128 | 22.86 | 22.76 | -0.4% | 单块 -0.10 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t8 | 0 | tg64 | 15.30 | 8.17 | -46.6% | 单块 -7.13 | 2 | 2 |
| qwen2.5-1.5b-instruct-q4_k_m.gguf | t8 | 0 | pp128 | 21.89 | 23.57 | +7.7% | 单块 +1.68 | 2 | 2 |

A 是基线，B 是候选。方向一致指每个复验块的变化方向与总体中位数方向相同；只有单块时不做一致性判断。
