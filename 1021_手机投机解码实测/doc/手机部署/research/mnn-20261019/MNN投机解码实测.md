# MNN 投机解码与 0.6B / 2B 本机实测

## 一、结论

MNN 3.6.1 有投机解码，但它的形态和 llama.cpp 的“小模型当草稿、大模型当目标”不是一回事。

```text
MNN 的 speculative_type
├─ lookahead    n-gram / 外接知识库出草稿，单模型即可开，任何正常导出的 MNN 模型都能用
├─ mtp          目标模型自带多 token 预测头，需要额外的 mtp.mnn
├─ eagle        目标模型配套的 EAGLE 头，需要 eagle.mnn / eagle_fc.mnn / eagle_d2t.mnn
├─ dflash       块扩散草稿头，需要 dflash.mnn / dflash_fc.mnn
└─ draftmodel   只有配置字段和读取函数，生成策略工厂里没有分支，属于死代码
```

所以“0.6B 当草稿 + 2B 当目标”这种组合在 MNN 里跑不起来。能跑的是：0.6B 和 2B 各自作为单模型，打开 lookahead。本机已经跑通，数据在第三节。

自然提示下不要默认开 lookahead：0.6B 慢 21%，2B 慢 23%。它只对“输出大量复用输入或知识库 n-gram”的任务有正收益，例如逐字复述、代码编辑、模板化文本。

## 二、本机环境与测试口径

| 项 | 值 |
|---|---|
| CPU | Intel Core Ultra 5 125H，14 核 18 线程 |
| 内存 | 31.6 GB |
| GPU | Intel Arc 核显，MNN 这轮只走 CPU |
| 系统 | Windows 11 26200 |
| 编译器 | Visual Studio 2026 Community，MSVC 14.51 |
| 构建 | CMake + Ninja，Release，`MNN_BUILD_LLM=ON`，`MNN_LOW_MEMORY=ON` |
| 线程 | 模型 config 里的 `thread_num=4`，四轮测试保持一致 |

模型来自 MNN 模型市场，均为 int4 权重：

| 模型 | 权重文件 | 大小 | 说明 |
|---|---|---:|---|
| Qwen3-0.6B-MNN | `llm.mnn.weight` | 450,810,338 B | 纯文本，28 层，hidden 1024 |
| Qwen3.5-2B-MNN | `llm.mnn.weight` | 1,176,647,702 B | qwen3_5，hidden 2048，带视觉权重，本轮只用文本部分 |

测试程序是 MNN 自带的 `llm_demo`，每个用例生成 64 token，读它打印的 `decode speed`。两条提示词：

```text
prompt-repeat.txt   要求模型逐字复述一段 79 token 的中文，输出会大量复用输入 n-gram
prompt-natural.txt  “用三句话解释什么是模型量化”，普通开放问答
```

lookahead 配置只加这些字段，其余沿用模型自带 config：

```json
{
  "speculative_type": "lookahead",
  "draft_predict_length": 4,
  "draft_match_strictness": "low",
  "draft_selection_rule": "freqxlen",
  "ngram_match_maxlen": 4,
  "ngram_update": true
}
```

## 三、原生 Windows 实测结果

单位均为 token/s，四线程，单次运行；prefill 是同一轮打印的提示处理速度。

| 模型 | 提示 | 基线 decode | lookahead decode | 变化 | 基线 prefill | lookahead prefill |
|---|---|---:|---:|---:|---:|---:|
| Qwen3-0.6B | 逐字复述 | 45.51 | **88.86** | **+95%** | 214.93 | 246.02 |
| Qwen3-0.6B | 自然问答 | 45.52 | 36.18 | −21% | 170.11 | 158.35 |
| Qwen3.5-2B | 逐字复述 | 19.73 | **29.68** | **+50%** | 94.92 | 84.79 |
| Qwen3.5-2B | 自然问答 | 20.13 | 15.51 | −23% | 64.49 | 65.41 |

两个模型的量级差异符合预期：0.6B 每 token 约 22 ms，2B 约 51 ms；2B 的权重读取量约为 0.6B 的 2.6 倍，decode 速度约为其 43%。

lookahead 的收益取决于草稿接受率。逐字复述时输入里已经有完整 n-gram，草稿几乎必中，所以 0.6B 接近翻倍；2B 只提升 50%，因为它的 tokenizer 把中文切成带空格的字符，4-gram 命中率低于 0.6B，且这轮 2B lookahead 提前遇到 EOS，只生成了 44 个 token（基线 64 个），t/s 仍按实际生成 token 数计算。

WSL 里用同一份源码、同一批模型做过交叉验证，趋势一致，数值有 ±10% 左右浮动：

| 用例 | WSL decode | 原生 decode |
|---|---:|---:|
| 0.6B 复述基线 | 45.55 | 45.51 |
| 0.6B 复述 lookahead | 87.10 | 88.86 |
| 0.6B 自然 lookahead | 40.30 | 36.18 |
| 2B 复述基线 | 19.95 | 19.73 |
| 2B 复述 lookahead | 33.30 | 29.68 |
| 2B 自然 lookahead | 17.57 | 15.51 |

WSL 不是 MNN 的要求，只是第一次构建时的捷径：Windows 的 `cl.exe` 没进 PATH，`vswhere` 也不在默认位置，我先用现成的 WSL Ubuntu 编了 Linux 版。后来确认本机装了 VS 2026 的 C++ 工具链，就用 MSVC 原生重编了一遍；上表主数据全部来自原生 Windows，WSL 只作为对照。

## 四、为什么“0.6B 草稿 + 2B 目标”在 MNN 里不通

生成策略工厂只认四个字符串：

```cpp
// transformers/llm/engine/src/speculative_decoding/generate.cpp
if (config->speculative_type() == "lookahead") {
    res.reset(new LookaheadGeneration(...));
} else if (config->speculative_type() == "mtp") {
    res.reset(new MtpGeneration(...));
} else if (config->speculative_type() == "eagle") {
    res.reset(new EagleGeneration(...));
} else if (config->speculative_type() == "dflash") {
    res.reset(new DFlashGeneration(...));
} else {
    res.reset(new ArGeneration(...));   // draftmodel 会落到这里，退化成普通自回归
}
```

`llmconfig.hpp` 里确实有 `draft_model()` 和“speculative_type 设为 draftmodel 时填草稿模型路径”的注释，但全仓库没有第二个地方读它。把 `speculative_type` 写成 `draftmodel` 不会报错，只会静默地按普通自回归跑，这点很容易误判。

EAGLE 看起来最接近“小模型草稿”，但它要求的是与目标模型隐藏维度对齐、专门训练过的 EAGLE 头，不是任意一个 0.6B 语言模型。导出时要走 `llmexport.py --eagle_path`，而且当前映射只覆盖 `llama` 和 `qwen3` 两类模型；Qwen3.5 会落到默认的 `LlamaEagle`，是否兼容没有验证。MTP 和 DFlash 同样需要目标模型配套的专用头。

如果目标就是“0.6B 草稿 + 2B 目标”的经典 draft-model 投机解码，应该用 llama.cpp 的 `--model-draft`，不是 MNN。MNN 这条线要么单模型 lookahead，要么给 2B 目标找/训一个 EAGLE 头。

## 五、复现

原生构建：

```bat
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
cd /d D:\mnn-native\src
cmake -S . -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DMNN_BUILD_LLM=ON -DMNN_LOW_MEMORY=ON -DMNN_BUILD_TEST=OFF ^
  -DMNN_BUILD_CONVERTER=OFF -DMNN_BUILD_QUANTOOLS=OFF ^
  -DMNN_BUILD_SHARED_LIBS=ON -DMNN_OPENCL=OFF -DMNN_VULKAN=OFF
cmake --build build-win --target llm_demo llm_bench -j 18
```

运行：

```powershell
cd D:\mnn-native\src\build-win
.\llm_demo.exe D:\mnn-native\models\Qwen3-0.6B-MNN\config_lookahead.json D:\mnn-native\prompt-repeat.txt 64
```

模型下载与 WSL 构建脚本在本目录：

| 文件 | 作用 |
|---|---|
| `download-mnn-models.ps1` | 从 ModelScope 拉取两个模型的全部文件 |
| `build-mnn-wsl.sh` | 在 WSL 内解包并构建 `llm_demo` / `llm_bench` |
| `spec-test/` | 两条提示词与四份 config 变体 |

## 六、未验证与风险

本轮只测了四线程、int4、单次运行，没有扫 2/8 线程、Q4 与 Q8、KV 量化、FlashAttention 开关，也没有测持续负载后的热衰减。2B 是带视觉塔的 qwen3_5 模型，本轮只走文本，视觉权重没有参与；Arc 核显没有接入 MNN，所有数字都是 CPU。lookahead 的收益对任务极其敏感，换一条提示词就可能从 +95% 变成 −21%，不能把复述场景的数字当成通用加速比。
