# gpu-npu-probe.sh 说明

## 这是什么

手机端 GPU / NPU 能力探测脚本。**纯 shell，不需要 root**，用 `adb shell` 或 Termux 都能跑。它回答的是「这台手机有什么算力硬件」——即硬件与外设层的存在性。

配套的 `gpu-npu-reach.sh` 回答的是另一个问题：「我这个身份能不能用」。两者必须一起看，因为 Android 上**文件权限位**和 **SELinux 域策略**是两道独立的门，只看第一道会得出错误结论。

## 输入

无参数。所有探测路径都先判存在再输出，缺失的项不会报错，只打印「不存在」。

## 输出

按八个分块顺序打印，每块以 `##### [n] 标题 #####` 开头：

```text
[1] 设备与 SoC 事实        型号、平台代号、SoC、内核版本、ABI
[2] CPU 特性与拓扑         指令集特性、各核最大频率、core_id 分簇
[3] GPU 驱动与图形 API     /dev 下的 GPU 节点、devfreq、图形权限手册、EGL/Vulkan 库位置
[4] GPU 计算接口           libvulkan、OpenCL 厂商库、Vulkan HAL
[5] NPU / APU 驱动与节点   /dev 下加速器节点、/sys 下的加速器类、/sys/module 里已加载模块
[6] NPU 软件栈             NNAPI 声明、厂商 AI 运行库、NPU 固件
[7] 系统属性里的 AI 痕迹   getprop 里所有含 ai/npu/apu/mdla 的属性
[8] 汇总判断               把关键结论浓缩成一行行
```

最后一块 `[8] 汇总判断` 是给人和模型快速抓重点用的，不必回头翻前七块。

## 读到什么信号代表什么

```text
/dev/mali0                       存在 → GPU 驱动起来了
/dev/dri/card0                   存在 → 有 DRM 显示节点
ro.hardware.vulkan = mali        → Vulkan 走后端是 Mali 驱动
android.hardware.vulkan.compute-0.prebuilt.xml
                                 → 系统正式声明支持 Vulkan 计算，不是"没暴露"
/vendor/lib64/libOpenCL.so       → Mali 的 OpenCL 可能可用
/vendor/lib64/libneuron_runtime.so
                                 → 厂商 NPU 运行时库存在
init.svc.neuralnetworks_hal_service_shim_mtk = running
                                 → NNAPI HAL 在跑，说明有标准入口
/dev/apusys                     存在 → MediaTek APU 驱动已加载
```

## 不负责

不做可达性验证。`/dev/apusys` 的权限位可能是 `crw-rw-rw-`，看起来人人可写，但实际 open 会被 SELinux 拒绝。**判断「能不能用」必须跑 `gpu-npu-reach.sh`。**

## 实测记录（Redmi K70E / 天玑 8300-Ultra / Android 14）

```text
SoC              MT6897 = 天玑 8300-Ultra
内核             6.1.138-android14-11
SELinux          Enforcing
CPU 特性         sve sve2 svei8mm svebf16 i8mm bf16 asimddp sha512
各核上限         cpu0-3  2.2GHz    cpu4-6  3.2GHz    cpu7  3.35GHz

GPU              /dev/mali0 (crw-rw-rw-)、/dev/dri/card0
                 驱动 mali_kbase_mt6897_r44
                 Vulkan 1.3 + compute 权限手册齐备
                 /vendor/lib64/egl/mt6897/libGLES_mali.so  46 MB
                 /vendor/lib64/hw/vulkan.mali.so
NPU              /dev/apusys (crw-rw-rw-)、/dev/apuext、/dev/apusys_sapu
                 mdla-tx-rpmsg / mvpu-tx-rpmsg 等 20 余条 rpmsg 通道
                 NNAPI HAL 运行中
                 libneuron_runtime.so / libapu_mdw.so / libtflite_mtk.so 齐备
                 固件 /vendor/etc/nn/ot/neuron_detection.mdla*
```

## 对应文件

- `tools/gpu-npu-probe.sh` 本脚本
- `tools/gpu-npu-reach.sh` 可达性深探（第二轮）
- `tools/probe-gpu-npu.ps1` 电脑侧驱动脚本，负责推送并执行本脚本
