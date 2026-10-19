# 1019_Qwen架构与MNN部署

主题：Qwen3-0.6B 前向架构详解；K70E 上的 MNN 3.6.1 CPU 部署、端到端生成与同机 llama.cpp 对照

本目录共 30 个文件，来自 小模型研究、手机部署。“原路径”是它在来源工程里的位置。

## 小模型研究（1）

| 文件 | 原路径 | 大小 |
| --- | --- | --- |
| [1019.md](<doc/小模型研究/1019.md>) | `1019.md` | 20.3 KB |

## 手机部署（29）

| 文件 | 原路径 | 大小 |
| --- | --- | --- |
| [MNN部署实测报告.md](<doc/手机部署/MNN部署实测报告.md>) | `MNN部署实测报告.md` | 12.0 KB |
| [README.md](<doc/手机部署/research/mnn-20261019/README.md>) | `research/mnn-20261019/README.md` | 4.0 KB |
| [mnn-d0-r2.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-d0-r2.json>) | `research/mnn-20261019/device-results/mnn-d0-r2.json` | 268 B |
| [mnn-d2048-r2.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-d2048-r2.json>) | `research/mnn-20261019/device-results/mnn-d2048-r2.json` | 358 B |
| [mnn-d4096-r2.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-d4096-r2.json>) | `research/mnn-20261019/device-results/mnn-d4096-r2.json` | 355 B |
| [mnn-d512-r2.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-d512-r2.json>) | `research/mnn-20261019/device-results/mnn-d512-r2.json` | 354 B |
| [mnn-smoke.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-smoke.json>) | `research/mnn-20261019/device-results/mnn-smoke.json` | 448 B |
| [mnn-t4-r1.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-t4-r1.json>) | `research/mnn-20261019/device-results/mnn-t4-r1.json` | 462 B |
| [mnn-t4-r3-postllama.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-t4-r3-postllama.json>) | `research/mnn-20261019/device-results/mnn-t4-r3-postllama.json` | 490 B |
| [mnn-t4-r3.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-t4-r3.json>) | `research/mnn-20261019/device-results/mnn-t4-r3.json` | 490 B |
| [mnn-t6-r3.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-t6-r3.json>) | `research/mnn-20261019/device-results/mnn-t6-r3.json` | 498 B |
| [mnn-t8-r3.json](<doc/手机部署/research/mnn-20261019/device-results/mnn-t8-r3.json>) | `research/mnn-20261019/device-results/mnn-t8-r3.json` | 481 B |
| [config.json](<doc/手机部署/research/mnn-20261019/model/Qwen3.5-0.8B-MNN/config.json>) | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/config.json` | 652 B |
| [configuration.json](<doc/手机部署/research/mnn-20261019/model/Qwen3.5-0.8B-MNN/configuration.json>) | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/configuration.json` | 46 B |
| [export_args.json](<doc/手机部署/research/mnn-20261019/model/Qwen3.5-0.8B-MNN/export_args.json>) | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/export_args.json` | 1.0 KB |
| [llm_config.json](<doc/手机部署/research/mnn-20261019/model/Qwen3.5-0.8B-MNN/llm_config.json>) | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/llm_config.json` | 8.5 KB |
| [model_market.json](<doc/手机部署/research/mnn-20261019/model_market.json>) | `research/mnn-20261019/model_market.json` | 84.3 KB |
| [prompt-zh.txt](<doc/手机部署/research/mnn-20261019/prompt-zh.txt>) | `research/mnn-20261019/prompt-zh.txt` | 71 B |
| [termux-bench.png](<doc/手机部署/research/mnn-20261019/termux-bench.png>) | `research/mnn-20261019/termux-bench.png` | 327.4 KB |
| [termux-bench2.png](<doc/手机部署/research/mnn-20261019/termux-bench2.png>) | `research/mnn-20261019/termux-bench2.png` | 352.3 KB |
| [termux-bench4096.png](<doc/手机部署/research/mnn-20261019/termux-bench4096.png>) | `research/mnn-20261019/termux-bench4096.png` | 357.9 KB |
| [termux-ls.png](<doc/手机部署/research/mnn-20261019/termux-ls.png>) | `research/mnn-20261019/termux-ls.png` | 254.4 KB |
| [termux-ls2.png](<doc/手机部署/research/mnn-20261019/termux-ls2.png>) | `research/mnn-20261019/termux-ls2.png` | 311.3 KB |
| [termux-ui.xml](<doc/手机部署/research/mnn-20261019/termux-ui.xml>) | `research/mnn-20261019/termux-ui.xml` | 8.1 KB |
| [termux-ui2.xml](<doc/手机部署/research/mnn-20261019/termux-ui2.xml>) | `research/mnn-20261019/termux-ui2.xml` | 8.5 KB |
| [termux-version.png](<doc/手机部署/research/mnn-20261019/termux-version.png>) | `research/mnn-20261019/termux-version.png` | 331.2 KB |
| [termux.png](<doc/手机部署/research/mnn-20261019/termux.png>) | `research/mnn-20261019/termux.png` | 237.2 KB |
| [deploy-mnn-bench.doc.md](<doc/手机部署/tools/deploy-mnn-bench.doc.md>) | `tools/deploy-mnn-bench.doc.md` | 4.5 KB |
| [deploy-mnn-bench.ps1](<doc/手机部署/tools/deploy-mnn-bench.ps1>) | `tools/deploy-mnn-bench.ps1` | 9.8 KB |
