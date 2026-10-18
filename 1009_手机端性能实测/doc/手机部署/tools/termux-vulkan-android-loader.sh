#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 切换到 vulkan-loader-android，把 Mali 接上来
#
# 关键发现（来自 Termux 仓库的包元数据）：
#
#   vulkan-loader-generic   732 KB   Provides: vulkan-loader-android
#                                   Conflicts: vulkan-loader-android
#       Homepage: github.com/KhronosGroup/Vulkan-Loader
#       → Khronos 桌面版 loader，按 ICD json 扫描驱动。
#         在 Android 上只找得到 Termux 自带的 Mesa llvmpipe。
#
#   vulkan-loader-android    72 KB
#       Homepage: source.android.com/devices/graphics/arch-vulkan
#       → Android 平台版 loader，通过 hw_get_module("vulkan")
#         加载 /vendor/lib64/hw/vulkan.mali.so。
#
#   两个包 Conflicts，装了一个另一个会被移除。
#   之前装 vulkan-tools 时依赖被解析成 vulkan-loader，
#   而 vulkan-loader 的依赖是 "vulkan-loader-generic | vulkan-loader-android"，
#   apt 选了前者 —— 这就是一直只枚举到 llvmpipe 的原因。
#
# 本脚本做：
#   1. 卸载 generic，安装 android 版
#   2. 确认 libvulkan.so 变成了 Android 版（体积约 270 KB，SONAME=libvulkan.so）
#   3. 用 vulkaninfo 枚举，看是否出现 Mali
#   4. 若成功，立刻测 llama.cpp 的 Vulkan 后端并跑基准
#
# 用法：
#   bash termux-vulkan-android-loader.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
LIB="$HOME/../usr/lib"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 第 0 步 · 当前 loader 是哪一个"
echo "=============================================================="
ls -l "$LIB"/libvulkan* 2>&1
echo
if [ -e "$LIB/libvulkan.so.1.4.365" ]; then
  echo "判定：当前是 vulkan-loader-generic（有 libvulkan.so.1.4.365）"
  IS_GENERIC=1
else
  echo "判定：当前不是 generic 版"
  IS_GENERIC=0
fi

echo
echo "=============================================================="
echo " 第 1 步 · 卸载 generic，安装 android 版"
echo "=============================================================="
info "卸载 vulkan-loader-generic（会同时影响 vulkan-tools，稍后重装）"
pkg uninstall -y vulkan-loader-generic 2>&1 | tail -5

info "安装 vulkan-loader-android"
pkg install -y vulkan-loader-android 2>&1 | tail -8

echo
echo "--- 切换后的库形态 ---"
ls -l "$LIB"/libvulkan* 2>&1

echo
echo "--- SONAME 与依赖（确认是 Android 版） ---"
REAL=$(readlink -f "$LIB/libvulkan.so" 2>/dev/null)
echo "libvulkan.so -> $REAL"
if [ -n "$REAL" ] && [ -e "$REAL" ]; then
  echo "体积: $(stat -c%s "$REAL") 字节"
  readelf -d "$REAL" 2>/dev/null | grep -E 'SONAME|NEEDED' | head -12
fi

echo
echo "=============================================================="
echo " 第 2 步 · 确保 vulkaninfo 还在"
echo "=============================================================="
if ! command -v vulkaninfo >/dev/null 2>&1; then
  info "重装 vulkan-tools（注意：它可能又把 generic 拉回来，装完再检查）"
  pkg install -y vulkan-tools 2>&1 | tail -4
  echo
  echo "--- 检查 generic 是否被重新拉回 ---"
  if [ -e "$LIB/libvulkan.so.1.4.365" ]; then
    warn "vulkan-tools 把 generic 又装回来了，重新卸载"
    pkg uninstall -y vulkan-loader-generic 2>&1 | tail -3
    pkg install -y vulkan-loader-android 2>&1 | tail -3
  fi
  ls -l "$LIB"/libvulkan* 2>&1
fi

echo
echo "=============================================================="
echo " 第 3 步 · vulkaninfo 枚举（关键判据：Mali 还是 llvmpipe）"
echo "=============================================================="
unset VK_ICD_FILENAMES
if command -v vulkaninfo >/dev/null 2>&1; then
  echo "--- vulkaninfo --summary ---"
  vulkaninfo --summary 2>&1 | head -45
  echo
  echo "--- 关键字段 ---"
  vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|driverInfo|apiVersion|deviceType|ERROR|WARNING' | head -15
else
  warn "vulkaninfo 仍不可用"
fi

echo
echo "=============================================================="
echo " 第 4 步 · 若 Mali 出现，测 llama.cpp Vulkan 后端"
echo "=============================================================="
echo "--- llama-cli --list-devices ---"
llama-cli --list-devices 2>&1 | head -20
echo
echo "--- 若列出了 Vulkan 设备，跑基准对比 CPU ---"
MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
if [ -f "$MODEL" ]; then
  echo "=== CPU 基线（-ngl 0，-t 4）==="
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 0 -t 4 -r 3 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
  echo
  echo "=== Vulkan 全量卸载（-ngl 99）==="
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 99 -r 3 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
  echo
  echo "=== Vulkan 半量卸载（-ngl 14）==="
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 14 -r 3 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
else
  warn "模型不在，跳过基准"
fi

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 deviceName 出现 Mali-G615
     → GPU 打通。接下来的速度对比看第 4 步的 CPU vs Vulkan 两行数字。

 仍是 llvmpipe
     → loader 换了但配置未生效。检查：
       · /system/lib64/libvulkan.so 是否可读
       · 是否有残留的 VK_ICD_FILENAMES 指向 Mesa

 报 "not accessible for the namespace"
     → loader 确实去开了 Mali 但被 namespace 拒。
       这与之前看到的限制是同一个，说明即便是 Android 版 loader，
       在 Termux 进程内仍受 namespace 约束。
EOF
