#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · GPU（Mali-G615 via Vulkan）与 CPU 的速度对比
#
# 前提（已实测确认）：
#   vulkaninfo 枚举到 Mali-G615 MC6，driverID=DRIVER_ID_ARM_PROPRIETARY
#   apiVersion 1.3.247，driverVersion 44.1.0
#   llama-cli --list-devices 输出：
#       Vulkan0: Mali-G615 MC6 (11271 MiB, 11271 MiB free)
#   → ggml 的 Vulkan 后端已接上 Mali
#
# 本脚本要回答的唯一问题：这个 1.5B 模型上，GPU 比 CPU 快还是慢。
#
# 设计上修掉上一版的缺陷：
#   上一版把 llama-bench 的输出管道给了 grep，管道会缓冲到进程结束，
#   导致长时间看不到任何进度。本版让输出直接重定向到文件，
#   再用单独的命令读取，进度可见。
#
# 用法：
#   bash termux-gpu-vs-cpu.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

echo "=============================================================="
echo " 环境确认"
echo "=============================================================="
echo "libvulkan.so -> $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
llama-cli --list-devices 2>&1 | head -6
echo
echo "内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null || echo 'n/a')"

# 每组一个独立日志文件，输出直连文件不经管道，保证进度可见
run() {
  local tag="$1"; shift
  local out="$HOME/bench-$tag.log"
  echo
  echo "=============================================================="
  echo " $tag"
  echo " 输出文件: $out"
  echo "=============================================================="
  # 显式重定向到文件，不经管道
  llama-bench "$@" > "$out" 2>&1
  local rc=$?
  echo "退出码: $rc"
  # 跑完立刻把结果打出来
  grep -E '^\|' "$out" 2>/dev/null | grep -vE 'model|^-+' || tail -8 "$out"
}

echo
info "开始。先跑 CPU 基线（-ngl 0）"
run cpu15 -m "$MODEL" -p 512 -n 128 -ngl 0 -t 4 -r 2

info "再跑 Vulkan 全量卸载（-ngl 99）"
run vk99-15 -m "$MODEL" -p 512 -n 128 -ngl 99 -r 2

info "再跑 Vulkan 部分卸载（-ngl 14，约三分之一层）"
run vk14-15 -m "$MODEL" -p 512 -n 128 -ngl 14 -r 2

echo
echo "=============================================================="
echo " 0.6B 上重复 CPU vs Vulkan"
echo "=============================================================="
run cpu06 -m "$M06" -p 512 -n 128 -ngl 0 -t 4 -r 2
run vk99-06 -m "$M06" -p 512 -n 128 -ngl 99 -r 2

echo
echo "=============================================================="
echo " 汇总"
echo "=============================================================="
for t in cpu15 vk99-15 vk14-15 cpu06 vk99-06; do
  f="$HOME/bench-$t.log"
  [ -f "$f" ] || continue
  echo "--- $t ---"
  grep -E '^\|' "$f" 2>/dev/null | grep -vE 'model|^-+'
done

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo
echo "全部完成"
