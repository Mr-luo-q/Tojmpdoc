#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 只跑 Vulkan（Mali）基准，拿到 GPU 的第一批真实数字
#
# 背景：
#   GPU 已打通（vulkan-loader-android + Mali-G615 MC6）。
#   但上一轮对照基准因为两个 llama-bench 进程互相抢资源而作废
#   （pp512 测出 3.68 ± 2.22，标准差远大于均值）。
#   本脚本先只跑 Vulkan 一组，快速拿到可用数字。
#
# ggml 报告的 Mali 能力（来自 llama-bench 日志）：
#   fp16: 1   bf16: 0   fp4: 0
#   warp size: 16   shared memory: 32768
#   int dot: 0   matrix cores: none
#     → 没有矩阵核心，Vulkan 后端的 matmul 走不了 cooperative matrix
#
# 用法：
#   bash termux-gpu-only-bench.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

echo "=============================================================="
echo " 先确认没有残留进程"
echo "=============================================================="
ps -A 2>/dev/null | grep -i llama || echo "（无残留，环境干净）"
echo "内存: $(grep MemAvailable /proc/meminfo 2>/dev/null)"

echo
echo "=============================================================="
echo " 设备清单"
echo "=============================================================="
llama-cli --list-devices 2>&1 | head -5

echo
echo "=============================================================="
echo " Vulkan 全量卸载 -ngl 99（输出直连文件，不用管道）"
echo "=============================================================="
llama-bench -m "$MODEL" -p 512 -n 128 -ngl 99 -r 2 > "$HOME/gpu-99.log" 2>&1
echo "退出码 $?"
echo "--- 结果 ---"
grep -E '^\|' "$HOME/gpu-99.log" 2>/dev/null | grep -vE 'model|^-+'
echo "--- 后端能力行 ---"
grep -i 'ggml_vulkan' "$HOME/gpu-99.log" 2>/dev/null | head -3

echo
echo "=============================================================="
echo " Vulkan 部分卸载 -ngl 14"
echo "=============================================================="
llama-bench -m "$MODEL" -p 512 -n 128 -ngl 14 -r 2 > "$HOME/gpu-14.log" 2>&1
echo "退出码 $?"
grep -E '^\|' "$HOME/gpu-14.log" 2>/dev/null | grep -vE 'model|^-+'

echo
echo "=============================================================="
echo " CPU 基线 -ngl 0（对照，确认本轮环境干净）"
echo "=============================================================="
llama-bench -m "$MODEL" -p 512 -n 128 -ngl 0 -t 4 -r 2 > "$HOME/gpu-cpu.log" 2>&1
echo "退出码 $?"
grep -E '^\|' "$HOME/gpu-cpu.log" 2>/dev/null | grep -vE 'model|^-+'

echo
echo "=============================================================="
echo " 汇总（三组放在一起对比）"
echo "=============================================================="
for t in gpu-cpu gpu-14 gpu-99; do
  f="$HOME/$t.log"
  [ -f "$f" ] || continue
  echo "--- $t ---"
  grep -E '^\|' "$f" 2>/dev/null | grep -vE 'model|^-+'
done

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo
echo "完成"
