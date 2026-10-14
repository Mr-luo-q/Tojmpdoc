#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 提速复现第 0 步：环境快照（只读）
#
# 目的：在跑任何性能测试之前，把「设备是什么、运行时是什么、模型是哪一个」
# 固定下来。没有这份快照，后面所有 t/s 都无法说明是在什么对象上测的。
#
# 本脚本不安装软件、不停止服务、不修改模型，只读并落盘。
#
# 用法（电脑侧，经 run-as 以 Termux 应用身份执行）：
#   adb shell run-as com.termux /data/data/com.termux/files/home/scripts/termux-run.sh \
#       shell bash /data/data/com.termux/files/home/scripts/termux-speed-env.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

OUT_DIR="$HOME/speed-environment"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/env-snapshot.log"

exec > "$OUT" 2>&1

echo "############ 0. 采集时间与运行身份 ############"
date '+%Y-%m-%d %H:%M:%S %z'
echo "uid=$(id -u) user=$(id -un)"
echo "termux_prefix=$PREFIX"

echo
echo "############ 1. 系统与 SoC ############"
for p in ro.build.version.release ro.build.version.sdk ro.build.version.incremental \
         ro.soc.model ro.soc.manufacturer ro.product.model ro.product.device \
         ro.product.board ro.build.version.security_patch persist.sys.power.default.powermode \
         ro.thermal.iec.enable; do
  printf '%-42s = %s\n' "$p" "$(getprop $p 2>/dev/null)"
done
echo "kernel            = $(uname -r)"

echo
echo "############ 2. CPU 拓扑与特性 ############"
grep -m1 'Features' /proc/cpuinfo 2>/dev/null
echo "nproc = $(nproc 2>/dev/null)"
for c in 0 1 2 3 4 5 6 7; do
  max=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq 2>/dev/null)
  [ -n "${max:-}" ] && printf 'cpu%s max=%s kHz\n' "$c" "$max"
done

echo
echo "############ 3. 内存 ############"
grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null

echo
echo "############ 4. llama.cpp 与相关包版本 ############"
for pkg in llama-cpp llama-cpp-backend-vulkan llama-cpp-backend-opencl python libc++ \
           clang cmake libandroid-spawn; do
  printf '%-30s %s\n' "$pkg" "$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo '(未安装)')"
done
echo "--- llama-bench --version ---"
llama-bench --version 2>&1 | head -5
echo "--- 二进制哈希 ---"
for bin in llama-bench llama-cli llama-server; do
  [ -x "$HOME/../usr/bin/$bin" ] && sha256sum "$HOME/../usr/bin/$bin" 2>/dev/null
done

echo
echo "############ 5. llama-bench 支持的参数（决定复现脚本能否使用） ############"
llama-bench --help 2>&1

echo
echo "############ 6. 模型文件 ############"
ls -l "$HOME/models" 2>/dev/null
echo "--- sha256（大文件，需要一点时间） ---"
sha256sum "$HOME/models/Qwen3-0.6B-Q4_K_M.gguf" 2>/dev/null
sha256sum "$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" 2>/dev/null

echo
echo "############ 7. 是否有推理进程在跑 ############"
found=0
for d in /proc/[0-9]*; do
  [ -r "$d/comm" ] || continue
  name=$(cat "$d/comm" 2>/dev/null)
  case "$name" in
    llama-server|llama-cli|llama-bench|llama-completion)
      echo "RUNNING pid=${d#/proc/} name=$name"
      found=1
      ;;
  esac
done
[ "$found" = "0" ] && echo "没有可见的 llama 进程"

echo
echo "############ 8. 温度与电源节点（可能被权限拒绝） ############"
echo "--- /sys/class/thermal ---"
ls -1 /sys/class/thermal 2>&1 | head -8
for t in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$t" ] && echo "$t = $(cat "$t" 2>/dev/null)"
done
echo "--- /sys/class/power_supply ---"
ls -1 /sys/class/power_supply 2>&1 | head -8
for b in /sys/class/power_supply/battery/*; do
  [ -r "$b" ] && echo "$b = $(cat "$b" 2>/dev/null)"
done

echo
echo "############ 快照结束 ############"
echo "文件: $OUT"
