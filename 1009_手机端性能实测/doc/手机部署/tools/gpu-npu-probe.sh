#!/system/bin/sh
#
# 手机部署 · GPU / NPU 能力探测脚本（纯 shell，无需 root，路径全部先判存在）
#
# 用法（电脑侧）:
#   adb shell sh /data/local/tmp/gpu-npu-probe.sh
# 用法（手机侧，Termux）:
#   sh ~/gpu-npu-probe.sh
#
# 设计原则：
#   1. 不写死任何路径，所有探测项先判存在再输出，避免不同机型报错刷屏
#   2. 分块输出，块与块之间用 ===== 分隔，便于报告里逐条引用
#   3. 只读操作，不改任何系统状态
#
# 输出块：
#   [1] 设备与 SoC 事实        [2] CPU 特性与拓扑
#   [3] GPU 驱动与图形 API     [4] GPU 计算接口（Vulkan/OpenCL/GLES）
#   [5] NPU / APU 驱动与节点    [6] NPU 软件栈（NNAPI / 厂商库 / 固件）
#   [7] 系统属性里的 AI 痕迹    [8] 汇总判断

echo "##### [1] 设备与 SoC 事实 #####"
getprop ro.product.model
getprop ro.product.brand
getprop ro.product.device
getprop ro.board.platform
getprop ro.soc.model
getprop ro.soc.manufacturer
getprop ro.hardware
getprop ro.hardware.chipname
getprop ro.build.version.release
getprop ro.build.version.sdk
getprop ro.product.cpu.abi
getprop ro.product.cpu.abilist
getprop ro.product.cpu.abilist64
getprop ro.build.version.security_patch
echo "--- kernel ---"
uname -a

echo
echo "##### [2] CPU 特性与拓扑 #####"
if [ -r /proc/cpuinfo ]; then
  # 只取 CPU 型号、架构和特性三行，避免整份 cpuinfo 太长
  grep -m1 -E '^(Hardware|model name|Processor)' /proc/cpuinfo
  grep -m1 -i 'Features' /proc/cpuinfo
  echo "cpuinfo 逻辑核数: $(grep -c ^processor /proc/cpuinfo)"
fi
echo "--- 各核最大频率 ---"
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
  [ -r "$f" ] || continue
  cpu=$(echo "$f" | cut -d/ -f6)
  echo "$cpu $(cat "$f")"
done
echo "--- 核心拓扑（同频分簇） ---"
for f in /sys/devices/system/cpu/cpu[0-9]*/topology/core_id; do
  [ -r "$f" ] || continue
  echo "$(echo "$f" | cut -d/ -f6) core_id=$(cat "$f")"
done

echo
echo "##### [3] GPU 驱动与图形 API #####"
echo "--- /dev 下的 GPU 设备节点 ---"
ls -l /dev/mali* /dev/kgsl* /dev/dri/* /dev/pvr* /dev/gpu* 2>/dev/null
echo "--- devfreq 里的 GPU 频率接口 ---"
ls -d /sys/class/devfreq/*gpu* /sys/class/devfreq/*mali* /sys/class/devfreq/*gpufreq* 2>/dev/null
for d in /sys/class/devfreq/*gpu* /sys/class/devfreq/*mali*; do
  [ -d "$d" ] || continue
  echo "$d: available=$(cat "$d/available_frequencies" 2>/dev/null) cur=$(cat "$d/cur_freq" 2>/dev/null)"
done
echo "--- Android 声明的图形特性 ---"
getprop | grep -iE 'gles|vulkan|egl|gpu|mali' | head -40
echo "--- /vendor/etc/permissions 里与图形/算力有关的手册 ---"
ls /vendor/etc/permissions/ 2>/dev/null | grep -iE 'gles|vulkan|egl|neural|npu|apu|ai|dnn|opencl'
echo "--- EGL / Vulkan 实现库在哪 ---"
ls -l /vendor/lib64/egl/ /system/lib64/egl/ /vendor/lib/egl/ 2>/dev/null
find /vendor/lib64 /vendor/lib /system/lib64 -maxdepth 1 -iname '*vulkan*' 2>/dev/null

echo
echo "##### [4] GPU 计算接口 #####"
echo "--- 系统里自带的 Vulkan 工具/加载器 ---"
ls -l /system/lib64/libvulkan.so /vendor/lib64/libvulkan.so 2>/dev/null
echo "--- OpenCL 厂商库（Mali 计算常走这里） ---"
find /vendor/lib64 /vendor/lib /system/lib64 /system/vendor/lib64 -maxdepth 2 -iname '*OpenCL*' -o -maxdepth 2 -iname '*libmali*' 2>/dev/null
echo "--- Vulkan HAL ---"
getprop | grep -iE 'vulkan|opencl|gles'
ls /vendor/lib64/hw/vulkan.* /vendor/lib/hw/vulkan.* 2>/dev/null

echo
echo "##### [5] NPU / APU 驱动与节点 #####"
echo "--- /dev 下的加速器节点（APU / NPU / DSP / VPU） ---"
ls -l /dev/ | grep -iE 'apu|npu|vpu|dsp|mdla|mvpu|mtk|neu|tflite|edma|scp|tinysys|gz|mtk_aov' 2>/dev/null
ls -l /dev/*apu* /dev/*npu* /dev/*dsp* /dev/*mdla* /dev/*vpu* /dev/*mtk* /dev/*scp* 2>/dev/null
echo "--- /sys 下的加速器类 ---"
ls -d /sys/class/*apu* /sys/class/*npu* /sys/class/*mdla* /sys/class/*vpu* /sys/class/*dsp* /sys/class/*scp* /sys/class/*tinysys* 2>/dev/null
echo "--- /proc 下的驱动痕迹 ---"
for k in mdla mtk_apu apusys apu mtk_mdla mtk_vpu mtk-scp scp; do
  if grep -qi "$k" /proc/devices 2>/dev/null; then echo "/proc/devices 命中: $k"; fi
done
grep -iE 'mdla|apu|npu|vpu|dsp|scp' /proc/devices 2>/dev/null
echo "--- /sys/module 下已加载的加速器模块 ---"
ls /sys/module/ 2>/dev/null | grep -iE 'mdla|apu|npu|vpu|dsp|scp|mali|kgsl|gz'
echo "--- 内核命令行里的加速器开关 ---"
cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep -iE 'mdla|apu|npu|vpu|dsp|scp'
echo "--- SELinux 当前模式 ---"
getenforce 2>/dev/null

echo
echo "##### [6] NPU 软件栈（NNAPI / 厂商库 / 固件） #####"
echo "--- NNAPI 加速器声明（Android 的 NPU 标准入口） ---"
getprop | grep -i neural
ls /vendor/etc/nnapi* /vendor/etc/*neural* /system/etc/nnapi* 2>/dev/null
find /vendor/lib64/hw /vendor/lib/hw /system/lib64/hw -iname '*neural*' -o -iname '*nnapi*' -o -iname '*nn_*' 2>/dev/null
echo "--- 厂商 AI 运行库 ---"
find /vendor/lib64 -maxdepth 2 \( -iname '*neuron*' -o -iname '*neuropilot*' -o -iname '*nnapi*' -o -iname '*mdla*' -o -iname '*apu*' -o -iname '*tflite*' -o -iname '*dla*' \) 2>/dev/null
echo "--- NPU 固件 ---"
find /vendor/firmware /vendor/etc/firmware -maxdepth 2 -iname '*apu*' -o -maxdepth 2 -iname '*mdla*' -o -maxdepth 2 -iname '*dsp*' -o -maxdepth 2 -iname '*vpu*' 2>/dev/null
ls /vendor/firmware/ 2>/dev/null | head -40

echo
echo "##### [7] 系统属性里的 AI 痕迹 #####"
getprop | grep -iE 'ai|neural|apu|npu|mdla|neuro|dla|tflite' | head -60

echo
echo "##### [8] 汇总判断 #####"
echo "GPU 节点: $(ls /dev/mali* /dev/kgsl* /dev/dri/* 2>/dev/null | tr '\n' ' ')"
echo "Vulkan 库: $(ls /vendor/lib64/libvulkan.so /system/lib64/libvulkan.so 2>/dev/null | tr '\n' ' ')"
echo "OpenCL 库: $(find /vendor/lib64 -maxdepth 2 -iname '*OpenCL*' 2>/dev/null | tr '\n' ' ')"
echo "NNAPI 库: $(find /vendor/lib64/hw /system/lib64/hw -iname '*neural*' 2>/dev/null | tr '\n' ' ')"
echo "APU/NPU 节点: $(ls /dev/*apu* /dev/*npu* /dev/*mdla* /dev/*vpu* 2>/dev/null | tr '\n' ' ')"
echo "##### 探测结束 #####"
