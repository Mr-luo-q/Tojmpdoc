#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 补齐 Token 速率详表的空缺项（精简版）
#
# 为什么只有两组：
#   前面已经拿到 1.5B 的完整 prefill 曲线（pp32~pp2048）。
#   这一版只补两处空缺：
#     1. decode 曲线（-n 扫描），两个模型都要
#     2. 上下文深度影响（-d 扫描），两个模型都要
#
#   已刻意砍掉的项：
#     · -p 4096   实测单档要 10 分钟以上且效率低下，收益不值
#     · -r 3      降到 -r 2，标准差已经足够小（实测 ±0.01~0.06）
#     · 线程数 2/3 与 5/7 的精确值
#       4/6/8 的对比已经足够支撑「-t 4 最优」的结论
#
# 用法：
#   bash termux-perf-fill.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
LOG="$HOME/perf-fill.log"

exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

read_freq() {
  local out=""
  for c in 0 4 7; do
    local v
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    out="$out cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$out"
}

hdr() {
  echo
  echo "############################################################"
  echo "# $*"
  echo "############################################################"
  echo "频率:$(read_freq)"
  echo
}

echo "设备: $(getprop ro.soc.model 2>/dev/null)"
echo "固定: -ngl 0  -t 4  -r 2  --no-warmup"
echo "开始: $(date '+%H:%M:%S')"

# ---- decode 曲线：固定短提示词，扫生成长度 ----
hdr "1.5B · decode 曲线（-p 128，-n 16~512）"
llama-bench -m "$M15" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 16,32,64,128,256,512 2>&1
sleep 3

hdr "0.6B · decode 曲线（-p 128，-n 16~512）"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 16,32,64,128,256,512 2>&1
sleep 3

# ---- 上下文深度：模拟长对话 ----
hdr "1.5B · 上下文深度影响（-d 0~2048）"
llama-bench -m "$M15" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 64 -d 0,512,1024,2048 2>&1
sleep 3

hdr "0.6B · 上下文深度影响（-d 0~2048）"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 64 -d 0,512,1024,2048 2>&1
sleep 3

# ---- 0.6B 的 prefill 曲线（1.5B 已有） ----
hdr "0.6B · prefill 曲线（-n 32，-p 32~2048）"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 32,64,128,256,512,1024,2048 -n 32 2>&1

hdr "结束"
echo "频率:$(read_freq)"
echo "完成: $(date '+%H:%M:%S')"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
