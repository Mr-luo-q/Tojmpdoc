# termux-gpu-setup.sh 说明

## 这是什么

Termux 侧的 GPU 后端安装与验证脚本，为**天玑 8300 / Mali-G615** 这类 MediaTek + Arm Mali 平台写的。它解决一件事：把 llama.cpp 的 Vulkan 后端在 Termux 里跑起来，并验证它真的落到了 Mali GPU 上，而不是悄悄退回 CPU。

## 为什么不需要自己编译

这是本方案最关键的一个发现。上次那台华为 Pura 70 的结论是「官方不发 Android arm64 Vulkan 构建，上游对 Mali 系 GPU 的 Vulkan 后端还在修崩溃」，所以 GPU 这条路被判了死刑。

但 Termux 官方仓库里早就有现成的包：

```text
llama-cpp                      0.6.0    本体
llama-cpp-backend-vulkan       0.6.0    28 MB    Vulkan 后端，预编译
llama-cpp-backend-opencl       0.6.0     3 MB    OpenCL 后端
ollama + ollama-backend-vulkan 0.35.1           连 Ollama 都有 Vulkan 版

vulkan-tools                   1.4.365          提供 vulkaninfo
vulkan-loader-android          30               专为 Android 系统驱动写的加载器
clinfo                         3.1.26           查 Mali 的 OpenCL
shaderc / glslang / spirv-tools                 真要自己编时的着色器工具
```

`llama-cpp-backend-vulkan` 配合 `vulkan-loader-android`，走的是 Android 系统自带的 `/vendor/lib64/hw/vulkan.mali.so`。这条路绕开了「官方不发 Android Vulkan 构建」的死结，也绕开了「在手机上编译会在链接阶段因 libc++ ABI 不匹配失败」的老坑。

## 输入

| 参数 | 说明 |
|---|---|
| 无参数 | 安装 + 验证 + 跑基准 |
| `--check` | 只做能力检查，不装任何东西 |
| `--no-bench` | 装完不跑基准 |

## 输出

终端按八步打印结论，同时基准数据追加写入 `~/gpu-bench.log`。

## 八个步骤各自回答什么

```text
第 0 步  身份与 SELinux 上下文
         记录 uid、context、内核、ABI。对比 shell 身份的 u:r:shell:s0，
         Termux 是另一个域，可达性结论可能不同。

第 1 步  GPU 设备节点可达性
         用 dd 读 1 字节验证 /dev/mali0 能否真正 open。
         这一步失败，后面 Vulkan 一定跑不起来，根因就定位在这里。

第 2 步  图形驱动库可见性
         确认 /vendor/lib64/hw/vulkan.mali.so 与 libGLES_mali.so 可读。

第 3 步  安装
         pkg install llama-cpp llama-cpp-backend-vulkan vulkan-tools clinfo

第 4 步  vulkaninfo 验证
         deviceName 里出现 Mali → 驱动层通了
         没出现但没报错       → loader 没找到 ICD，查 vulkan-loader-android

第 5 步  clinfo 验证
         Mali 的第二条证据，OpenCL 与 Vulkan 是两套独立驱动路径。

第 6 步  llama.cpp 后端清单
         llama-cli --list-devices 是「ggml 是否真认到 GPU」的直接证据。
         列出 Vulkan 设备 → 后端库加载成功。

第 7 步  找模型
         依次找 ~/models 下的 1.5B 与 0.6B，找不到就跳过基准。

第 8 步  基准：CPU vs Vulkan
         组 1  -ngl 0   纯 CPU
         组 2  -ngl 99  Vulkan 全量卸载
         组 3  -ngl 16  Vulkan 半量卸载
         每组都测 pp（prompt processing，计算受限）与 tg（text generation，访存受限）
```

## 关键参数含义

| 参数 | 含义 |
|---|---|
| `-ngl N` | 卸载 N 层到 GPU，`0` 表示纯 CPU，`99` 表示全部卸载 |
| `-p 512` | 基准用的提示词长度，测 prefill 性能 |
| `-n 128` | 基准生成 token 数，测 decode 性能 |
| `-t 8` | CPU 线程数 |

## 预期结论与判读

```text
常见的三种结果

情况甲  pp 大幅变快、tg 持平或略慢
        → GPU 擅长大批量矩阵乘，这正是 prefill 的负载形态
        → 实用策略：只用 Vulkan 跑 prefill，decode 留在 CPU，
          或用 -ngl 部分层数折中

情况乙  pp 与 tg 都变快
        → 全量卸载即可，这是最理想的结果

情况丙  两者都变慢，或 Vulkan 初始化失败
        → 这个模型规模下 Vulkan 不划算。1.5B Q4_K_M 只有 1.1 GB，
          decode 是纯访存受限，GPU 的显存带宽优势体现不出来，
          反而多了主机与显存之间的搬运开销
```

## 不负责

不碰 NPU。NPU 的入口不是 Termux 包，而是 Android 的 NNAPI HAL，走 `termux-npu-probe.sh`。

## 对应文件

- `termux-gpu-setup.sh` 本脚本
- `termux-npu-probe.sh` NPU 可达性验证
- `tools/gpu-npu-probe.sh` 电脑侧硬件能力探测
- `tools/gpu-npu-reach.sh` 电脑侧可达性深探
