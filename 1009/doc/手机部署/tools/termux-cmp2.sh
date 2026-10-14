#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 后端对比（直出 markdown，不经 Python 管道）
#
# 为什么不用 Python 解析：
#   上一版把 llama-bench 的 jsonl 管道给 python 做整形，
#   但整套调用是从 PowerShell 发出的，多层引号被反复改写，
#   调试成本远高于收益。改成让 llama-bench 直出 markdown 表，
#   结果人工读取，反而更可靠。
#
# 保留 jsonl 原始输出到单独文件，需要精确耗时（avg_ns）时可再取。
#
# 四个测试组（参数完全一致，便于横向对比）：
#   1.5B CPU (-ngl 0)   与   1.5B GPU (-ngl 8)
#   0.6B CPU (-ngl 0)   与   0.6B GPU (-ngl 99)
#
# GPU 用哪个 ngl：
#   1.5B 全量卸载（-ngl 99）实测会挂死，所以用 -ngl 8
#   0.6B 全量卸载可用，所以用 -ngl 99（这是 GPU 最好的情况）
#
# 统一参数：-p 128 -n 64 -r 3 --no-warmup
#
# 用法：
#   bash termux-cmp2.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
LOG="$HOME/cmp2.log"
P=" -p 128 -n 64 -r 3 --no-warmup"

exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

freq() {
  local o=""
  for c in 0 4 7; do
    local v
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    o="$o cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$o"
}

banner() {
  echo
  echo "=============================================================="
  echo " $*"
  echo "=============================================================="
  echo "频率:$(freq)"
  echo
}

echo "对比开始: $(date '+%H:%M:%S')"
echo "统一参数:$P"

# ---------------- CPU ----------------
banner "一 · CPU 后端"
echo "loader: $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备: $(llama-cli --list-devices 2>&1 | tail -1)"
echo

echo "--- 1.5B CPU (-ngl 0) ---"
llama-bench -m "$M15" -t 4 -ngl 0 -o md $P
echo
echo "--- 0.6B CPU (-ngl 0) ---"
llama-bench -m "$M06" -t 4 -ngl 0 -o md $P

# ---------------- 切到 GPU ----------------
banner "二 · 切换到 GPU（vulkan-loader-android）"
pkg uninstall -y vulkan-loader-generic >/dev/null 2>&1
pkg install -y vulkan-loader-android >/dev/null 2>&1
echo "loader: $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备:"
llama-cli --list-devices 2>&1 | tail -2
echo

echo "--- 1.5B GPU (-ngl 8，全量 99 会挂死故用 8) ---"
timeout -s KILL 420 llama-bench -m "$M15" -t 4 -ngl 8 -o md $P
RC=$?
[ "$RC" = "137" ] && echo "（超时挂死，无数据）"
echo
echo "--- 0.6B GPU (-ngl 99，全量卸载) ---"
timeout -s KILL 420 llama-bench -m "$M06" -t 4 -ngl 99 -o md $P
RC=$?
[ "$RC" = "137" ] && echo "（超时挂死，无数据）"
echo
echo "--- 0.6B GPU (-ngl 8，部分卸载对照) ---"
timeout -s KILL 420 llama-bench -m "$M06" -t 4 -ngl 8 -o md $P

# ---------------- GPU 能力 ----------------
banner "三 · GPU 能力清单（解释性能差距）"
llama-bench -m "$M06" -t 4 -ngl 99 -p 16 -n 1 -r 1 2>&1 | grep -i 'ggml_vulkan' | head -3

# ---------------- 恢复 ----------------
banner "四 · 恢复纯 CPU 环境"
pkg uninstall -y vulkan-loader-android >/dev/null 2>&1
pkg install -y vulkan-loader-generic >/dev/null 2>&1
echo "loader: $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备: $(llama-cli --list-devices 2>&1 | tail -1)"

banner "结束"
echo "完成: $(date '+%H:%M:%S')"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
