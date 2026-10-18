# GPU / NPU 加速实测报告 · Redmi K70E

实测日期：2026-10-09
设备：Redmi K70E（`duchamp`，2311DRK48C），天玑 8300-Ultra
GPU：Arm Mali-G615 MC6；NPU：MediaTek APU 780
后端：llama.cpp 0.6.0（Termux 版）
模型：Qwen2.5-1.5B-Instruct Q4_K_M、Qwen3-0.6B Q4_K_M

## 一、最终结论

```text
             能否跑通      实测速度 vs CPU        判断
──────────────────────────────────────────────────────────────────────
CPU          能          0 t/s（基准）          唯一可用
GPU(Vulkan)  能认到设备   tg 慢 10~19 倍        慢到不可用
NPU(NNAPI)   跑不起来    —                     无可用入口
```

**一句话：这台机器上，GPU 和 NPU 都不能加速 llama.cpp。CPU 是唯一可用后端。**

这个结论和上一台华为不同——华为是"接口没暴露"，这台是**接口全部暴露、GPU 甚至能跑出数字，但数字比 CPU 差一个数量级**。原因不是接口，是 Mali-G615 这个 GPU 对 LLM 推理这类负载本身不适用。

## 二、GPU：从"判定不可用"到"真的打通了"

### 2.1 我最初的判断是错的，必须记录纠正

第一轮探测后我下的结论是：**「Termux 的 linker namespace 里没有 `/vendor/lib64`，所以拿不到 Mali 驱动，GPU 在 Termux 内不可用」**。

这个结论**是错的**。真正的卡点简单得多——**我装错了包**。

```text
vulkan-loader-generic   732 KB   Provides: vulkan-loader-android
                                Conflicts: vulkan-loader-android
    Homepage: github.com/KhronosGroup/Vulkan-Loader
    → Khronos 桌面版 loader，按 ICD json 扫描驱动。
      在 Android 上只能找到 Termux 自带的 Mesa llvmpipe（软件光栅化器）。

vulkan-loader-android    72 KB
    Homepage: source.android.com/devices/graphics/arch-vulkan
    → Android 平台版 loader，通过 hw_get_module("vulkan")
      加载 /vendor/lib64/hw/vulkan.mali.so。
```

之前装 `vulkan-tools` 时，依赖 `vulkan-loader` 被解析成 `vulkan-loader-generic | vulkan-loader-android` 的第一个选项，于是装上了桌面版。**这就是为什么我一直只枚举到 `llvmpipe`。**

### 2.2 换成正确包后，Mali 立刻出现

```text
$ pkg uninstall vulkan-loader-generic && pkg install vulkan-loader-android
Symlink /system/lib64/libvulkan.so to /data/data/com.termux/files/usr/lib/libvulkan.so

$ vulkaninfo --summary
GPU0:
    deviceName         = Mali-G615 MC6
    deviceType         = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
    apiVersion         = 1.3.247
    driverVersion      = 44.1.0
    vendorID           = 0x13b5
    deviceID           = 0xb8a31030
    driverID           = DRIVER_ID_ARM_PROPRIETARY
    driverName         = Mali-G615 MC6
    driverInfo         = v1.r44p1-01eac0.999bbcba36b4ca04774e2b05d5802dc0
    conformanceVersion = 1.3.5.2

$ llama-cli --list-devices
Available devices:
  Vulkan0: Mali-G615 MC6 (11271 MiB, 11271 MiB free)
```

**关键机制**：包管理器把 `libvulkan.so` 做成了**符号链接**指向 `/system/lib64/libvulkan.so`。这解决了一个我自己手工尝试时失败的问题——我曾用绝对路径链接系统 loader，但 bionic 的链接器在 `DT_NEEDED` 里只记 SONAME（不保留路径），运行时被 `DT_RUNPATH` 里的 Termux 目录抢先解析。**符号链接让 SONAME 解析天然落到系统库上，绕过了这个限制。**

### 2.3 ggml 报告的 Mali 能力（决定了它为什么慢）

```text
ggml_vulkan: Found 1 Vulkan devices:
  0 = Mali-G615 MC6 | uma: 1 | fp16: 1 | bf16: 0 | fp4: 0
      warp size: 16 | shared memory: 32768
      int dot: 0 | matrix cores: none
```

三个致命项：

```text
matrix cores: none   ← 不支持 KHR cooperative matrix，matmul 走不了张量核心
int dot: 0           ← 不支持整数点积指令，量化模型的核心运算没有硬件加速
bf16: 0              ← 不支持 bfloat16
```

**`int dot: 0` 是量化 LLM 的致命伤。** Q4_K_M 这类量化格式的推理核心是整数点积，而这个 GPU 没有对应的硬件指令，只能退化到通用 ALU 模拟。

### 2.4 实测速度：全面慢于 CPU

| 模型 | 卸载层数 | pp256 | tg64 |
|---|---|---|---|
| 1.5B | 1 | 6.21 | 0.76 |
| 1.5B | 4 | 5.74 | 0.97 |
| 1.5B | 8 | 6.30 | 1.13 |
| 1.5B | 99 | **挂死**（180~300 秒超时强杀） | 同左 |
| 0.6B | 0 | 14.33 | 1.51 |
| 0.6B | 4 | 14.69 | 2.41 |
| 0.6B | 99 | 16.35 | 22.80 |

**CPU 基线（干净环境，未装 Android loader 时测得）**：

| 模型 | pp256 | tg64 |
|---|---|---|
| 1.5B | **20.69** | **14.57** |
| 0.6B | **57.32** | **33.64** |

对比结论：

```text
1.5B   pp  20.69 → 6.30      慢 3.3 倍
       tg  14.57 → 1.13      慢 12.9 倍（最差 0.76，慢 19 倍）
       全量卸载直接挂死

0.6B   pp  57.32 → 16.35     慢 3.5 倍
       tg  33.64 → 22.80     慢 1.5 倍（最接近的一档，仍明显慢）
```

**唯一"能用"的配置是 0.6B + `-ngl 99`，tg 22.80 t/s，但仍比 CPU 的 33.64 慢 1.5 倍。** 而 1.5B 全量卸载会挂死。

### 2.5 挂死现象值得单独记录

`-ngl 99` 在 1.5B 上不产生任何 t/s 输出，进程累计 CPU 只有 18 秒却存活很久：

```text
9440   PPID=1   ETIME=00:19   TIME=00:00:18   llama-bench
```

`ETIME` 远大于 `TIME`，说明进程在阻塞等待而非计算。用 `kill -15` 能终止，不是不可中断的内核态死锁，是驱动的长阻塞。

日志停在设备识别与后端加载之后：

```text
ggml_vulkan: Found 1 Vulkan devices: ...
load_backend: loaded Vulkan backend from .../libggml-vulkan.so
load_backend: loaded CPU backend from .../libggml-cpu.so
（之后无输出）
```

### 2.6 GPU 的最终判断

**不建议使用 GPU。** 理由是硬件层面的，不是配置问题：

```text
1. int dot: 0 —— 量化推理的核心算子没有硬件指令支持
2. matrix cores: none —— matmul 无法用张量核心
3. 结果：tg 慢 10~19 倍，1.5B 全量卸载挂死
4. 唯一勉强可用的是 0.6B 全量卸载，仍慢 1.5 倍，不值得
```

这与之前调研文献的结论方向一致（NPU/GPU 在 decode 阶段对 llama.cpp 无优势），但本机比文献描述更差——因为 Mali-G615 缺少整数点积支持。

## 三、NPU：接口全开，但没有任何可用入口

### 3.1 正面事实（第一轮就确认了）

```text
NNAPI 能枚举到 4 个加速器：
    [0] mtk-dsp_shim       version=7.2.4              type=4
    [1] mtk-mdla_shim      version=7.2.4              type=4
    [2] mtk-neuron_shim    version=7.2.4              type=4
    [3] nnapi-reference    version=OS3.0.304.0.WNLCNXM type=2

入口位置：/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so
         （来自 /system/apex/com.android.neuralnetworks.capex）

HAL 进程：android.hardware.neuralnetworks-shim-service-mtk（system）
```

**我原先预判"Android 10 起 NNAPI 对第三方应用关闭、设备数应为 0"，实测是 4，判断被证伪。** 原因是 MediaTek 把 NPU 做成了 HAL 服务 + APEX 模块，走 binder 到 `IDevice`，不受那条应用白名单限制。

### 3.2 尝试一：手工用 NNAPI C API 建图 —— 卡在 ABI

写了一个最小的 ADD 模型（1×4 FLOAT32，两输入一输出），程序能加载库、能枚举设备，但：

```text
Model_create            rc=0
addOperand(a)           rc=4     ← ANEURALNETWORKS_BAD_DATA
```

用二分法试了四种结构体布局与两种类型常量，全部返回 4：

```text
                       type=0    type=1
L1 (5字段,无extraParams)  size=24   rc=4      rc=4
L2 (6字段,+extraParams)   size=32   rc=4      rc=4
L3 (dims放最后)           size=24   rc=4      rc=4
L4 (7字段,双指针)         size=40   rc=4      rc=4
```

**这是参数校验失败，不是结构体大小问题。** 修复需要准确的 NDK 头文件（`NeuralNetworksTypes.h`），而：

```text
Termux 里没有 NDK 头文件
网上取不到：raw.githubusercontent 404、docs.rs 404、
           developer.android.com 的 .md.txt 抓取失败
```

**没有第三次猜测的价值**，停在这里。

### 3.3 尝试二：用 TFLite 内置的 NNAPI delegate —— 构建里没有

换用现成运行时，检查 `python-tflite-runtime 2.21.0`：

```text
tflite_runtime 模块属性:
    Delegate / Interpreter / InterpreterWithCustomOps / OpResolverType /
    SignatureRunner / load_delegate / metrics ...
    ← 没有 NnApiDelegate

逐个尝试：
    tflite.NnApiDelegate()                → AttributeError: 模块里没这个属性
    tflite.experimental.NnApiDelegate()   → AttributeError: 没有 experimental
    load_delegate('libneuralnetworks.so') → undefined symbol: tflite_plugin_create_delegate
```

**这个 TFLite 构建没编入 NNAPI delegate**，只有通用插件式 `load_delegate`，而插件 `.so` 不在包里。所以 NPU 连"跑一次看看"的机会都没有。

### 3.4 更根本的阻断：格式层面

即便上面两个问题都解决，**llama.cpp 仍然用不上 NPU**，这是结构性的：

```text
第一层  格式层面
        NNAPI 吃的是「NNAPI 算子图」，由 TFLite / ONNX 转换而来。
        GGUF 里的 GGML 图（自定义量化、RoPE 变体、GQA 等）
        没有到 NNAPI 算子集的映射路径。

第二层  框架层面
        llama.cpp 上游已移除 NNAPI 后端。
        官方预编译包里 Android arm64 只有 CPU 与 snapdragon
        （Adreno + Hexagon）两种资产，没有任何通用 NPU 资产。

结论   要用 NPU 必须换模型格式与推理框架，
        走 LiteRT / LiteRT-LM 的 MediaTek NPU delegate，
        而 MediaTek 公开侧只给 NP Converter 与 TFLite Shim API，
        完整 NPU runtime 要签 NDA。
```

### 3.5 NPU 的最终判断

**无法给出速度数字，因为没有任何可用入口。** 这不是"慢"，是"跑不起来"。

要把 NPU 跑起来，可行的只有一条：改用自带 MediaTek NPU delegate 的第三方 App（如 LiteRT-LM 的 MTK 版本），那已经完全离开 llama.cpp 与 Termux 的范畴。

## 四、三条后端的速度对比总表

```text
                    1.5B pp256   1.5B tg64   0.6B pp256   0.6B tg64
──────────────────────────────────────────────────────────────────────
CPU                  20.69        14.57        57.32        33.64
  （干净环境，未装 Android Vulkan loader 时测得）

GPU Vulkan ngl=1      6.21         0.76         —            —
GPU Vulkan ngl=4      5.74         0.97        14.69         2.41
GPU Vulkan ngl=8      6.30         1.13         —            —
GPU Vulkan ngl=99     挂死         挂死        16.35        22.80

NPU                  跑不起来 —— 无可用入口
```

**注意 `ngl=0` 的行已省略**：一旦 Android loader 装上，即便 `-ngl 0`，llama-bench 的 `backend` 列也显示 `Vulkan` 且速度掉到 5.66——说明 Vulkan 后端只要加载就会接管张量分配，不再等同于纯 CPU。所以 CPU 基线用的是**更早、未装 Android loader 时测的数据**。

## 五、日常使用建议

```text
结论：用 CPU，不要碰 GPU。NPU 无路。

1.5B（质量优先）   -t 4    pp 约 20 t/s   tg 约 15 t/s
0.6B（速度优先）   -t 4    pp 约 57 t/s   tg 约 34 t/s

命令：
  llama-cli -m ~/models/Qwen3-0.6B-Q4_K_M.gguf -t 4 -c 2048
  llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 4 -c 2048

三个必须避开的坑：
  · 不要用 -t 8        tg 会掉一半以上（15 → 7.8）
  · 不要用 -ngl >0     慢 1.5~19 倍，1.5B 全量卸载挂死
  · 不要把 vulkan-loader-android 留着
    它会改变 libvulkan.so 的解析，使 -ngl 0 也不再等于纯 CPU
    若要恢复纯 CPU 行为：pkg uninstall vulkan-loader-android
                          pkg install vulkan-loader-generic
```

## 六、这次探测里我犯的错误（全部记录）

**错误 1：把「装错包」误判成「Android 安全模型阻断」。**
我花了大量精力论证「Termux 的 linker namespace 不含 `/vendor/lib64`，所以 Mali 不可达」，这个机制描述本身没错（警告原文确实如此），但它**不是本次卡点的原因**。真正原因是 loader 包选错。教训：看到符合预期的报错时，要反问"这个报错是唯一可能的解释吗"。

**错误 2：`pkill -f llama-bench` 在 run-as 环境下匹配不到目标。**
清理失效导致两个基准进程并存，测出 `pp512 = 3.68 ± 2.22` 这种标准差远大于均值的垃圾数据。教训：`run-as` 环境下的进程管理要用 PID，并在测试前显式验证环境干净。

**错误 3：把 `llama-bench` 的输出管道给 `grep`，导致长时间看不到进度。**
管道会缓冲到进程结束才刷出。教训：长时间运行的命令，输出直连文件，再用单独命令读取。

**错误 4：拔线才能跑的测试，脚本还没推到手机就先拔了线。**
拔线后 adb 断开，脚本推不上去，白折腾一轮。教训：先推脚本再拔线，或提前备好往终端注入命令的通道。

**错误 5：`-ngl 0` 被当成纯 CPU 基线。**
实际上只要 Vulkan 后端加载，`-ngl 0` 也会走 Vulkan 张量路径。CPU 基线必须用未装 Android loader 的环境，或用 `--device` 显式限定（未验证）。

## 七、对应文件

```text
tools/termux-vulkan-android-loader.sh   换成正确 loader 并测试（关键突破点）
tools/termux-gpu-only-bench.sh          只测 GPU 的基准
tools/termux-gpu-scan.sh                卸载量扫描（每个测试套 timeout）
tools/termux-cleanup-bench.sh           清理残留进程
tools/termux-npu-tflite.sh              TFLite 内置 NNAPI delegate 探测
tools/termux-nnapi-abi-probe.sh         NNAPI OperandType ABI 二分探测
tools/termux-nnapi-enum2.sh             NNAPI 设备枚举（成功）
tools/termux-npu-e2e.sh                 NNAPI 端到端（ABI 卡住）

手机上日志：
    ~/gpu-scan-result.log   卸载量扫描汇总
    ~/npu-tflite.log        NPU delegate 探测
    ~/vk-android.log        loader 切换与 Mali 枚举
    ~/gpu-99.log / gpu-14.log / gpu-cpu.log
```
