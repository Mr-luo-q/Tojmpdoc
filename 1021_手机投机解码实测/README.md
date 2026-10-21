# 1021_手机投机解码实测

主题：Redmi K70E 上的 MNN lookahead 与 llama.cpp draft 两套投机解码实测

本目录共 16 个文件，来自 手机部署。核心结论：MNN lookahead 在逐字复述上让 0.6B 从 46.59 提到 127.22 t/s（2.73 倍）、2B 从 22.30 提到 45.55 t/s（2.04 倍）；llama.cpp draft 在同一场景反而只有基线的 0.62–0.68 倍；字面“0.6B 草稿 + 2B 目标”因词表不匹配无法启动。

## 文档（3）

| 文件 | 原路径 | 内容 |
| --- | --- | --- |
| [手机MNN-lookahead实测.md](<doc/手机部署/手机MNN-lookahead实测.md>) | `手机MNN-lookahead实测.md` | 手机端 0.6B / 2B 的 lookahead 扫长度、原始速度与上限 |
| [手机llama投机解码实测.md](<doc/手机部署/手机llama投机解码实测.md>) | `手机llama投机解码实测.md` | 手机端 llama.cpp draft 的失败复现、接受率与温度漂移 |
| [MNN投机解码实测.md](<doc/手机部署/research/mnn-20261019/MNN投机解码实测.md>) | `research/mnn-20261019/MNN投机解码实测.md` | 电脑端 MNN lookahead 基线，含源码分支与 draftmodel 死代码 |

## 原始数据（4）

| 文件 | 内容 |
| --- | --- |
| [phone-mnn-results-1.csv](<doc/手机部署/research/mnn-20261019/spec-test/phone-mnn-results-1.csv>) | 主矩阵：0.6B 四档草稿 × 两提示，2B 三档草稿 × 两提示 |
| [phone-mnn-results-2.csv](<doc/手机部署/research/mnn-20261019/spec-test/phone-mnn-results-2.csv>) | 草稿 8 的补充重复与 12/16 的失败记录 |
| [phone-mnn-results-3.csv](<doc/手机部署/research/mnn-20261019/spec-test/phone-mnn-results-3.csv>) | 2B 自然问答补测（5 次基线 / 草稿 4 / 草稿 8） |
| [phone-llama-results.csv](<doc/手机部署/research/mnn-20261019/spec-test/phone-llama-results.csv>) | llama.cpp 基线 / 草稿长度 1 / 草稿长度 2 的三次重复 |

## 配置（8）

| 目录 | 文件 |
| --- | --- |
| `model/Qwen3-0.6B-MNN/` | `config_phone_base.json`、`config_phone_lookahead2.json`、`config_phone_lookahead4.json`、`config_phone_lookahead8.json` |
| `model/Qwen3.5-2B-MNN/` | 同上四份 |

四份配置的差异只有 `speculative_type`、`draft_predict_length` 和对应的采样字段；基线也统一成 `greedy`，避免采样噪声混进对比。

## 口径

手机是 Redmi K70E（2311DRK48C），Android 16，11.6 GB 内存；MNN 3.6.1 Android arm64 静态二进制；两个模型都是 int4；`thread_num=4`；每次生成 48 token；温度 24.5 → 29.2°C。lookahead 的草稿来自 prompt n-gram，不加载第二个模型；llama.cpp 的草稿是真实的 Qwen3-0.6B 前向，这是两组结果方向相反的根本原因。

细节、失败边界和复现命令见两份手机报告。
