#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 精简版性能采样（两次调用覆盖全部维度）
#
# 上一版设计过重（8 长度 x 3 重复 x 2 模型 + 4 组扫描），跑了十分钟还没出第一组。
# 这一版的原则：把要测的所有组合塞进尽量少的 llama-bench 调用里，
# 因为 llama-bench 的多值参数（-p a,b,c）会在**同一个进程内**依次测完，
# 省掉每次重新加载模型的固定开销。
#
# 两个模型各两条命令：
#   命令 1  固定短生成，扫提示词长度   → 得到 prefill 曲线 + 短生成的 decode 基线
#               -p 32,64,128,256,512,1024,2048,4096  -n 32
#   命令 2  固定短提示词，扫生成长度   → 得到 decode 曲线的稳定性
#               -p 128  -n 16,32,64,128,256,512
#
# 另外补一次上下文深度测试（测 KV 变长的影响），只在一个模型上做。
#
# 减少重复次数：-r 2（上一版 -r 3 太慢）。标准差仍足以判断数据质量。
# 保留 --no-warmup：避免预热与正式测量混在一起。
# 去掉 --delay：改为组间手动 sleep，控制更直接。
#
# 用法：
#   bash termux-perf-lean.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
LOG="$HOME/perf-lean.log"

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

echo "设备: $(getprop ro.soc.model 2>/dev/null)   内核: $(uname -r)"
echo "llama.cpp: $(llama-cli --version 2>&1 | head -1)"
echo "内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null)"
echo "固定: -ngl 0 (纯 CPU)  -t 4  -r 2  --no-warmup"

# ---------- 1.5B ----------
hdr "1.5B · prefill 曲线（-p 扫描，-n 固定 32）"
llama-bench -m "$M15" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 32,64,128,256,512,1024,2048,4096 -n 32 2>&1
sleep 5

hdr "1.5B · decode 曲线（-n 扫描，-p 固定 128）"
llama-bench -m "$M15" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 16,32,64,128,256,512 2>&1
sleep 5

# ---------- 0.6B ----------
hdr "0.6B · prefill 曲线（-p 扫描，-n 固定 32）"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 32,64,128,256,512,1024,2048,4096 -n 32 2>&1
sleep 5

hdr "0.6B · decode 曲线（-n 扫描，-p 固定 128）"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 16,32,64,128,256,512 2>&1
sleep 5

# ---------- 上下文深度 ----------
hdr "1.5B · 上下文深度影响（-d 预填充上下文再测）"
llama-bench -m "$M15" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 64 -d 0,512,1024,2048 2>&1
sleep 5

hdr "0.6B · 上下文深度影响"
llama-bench -m "$M06" -ngl 0 -t 4 -r 2 --no-warmup -o md \
  -p 128 -n 64 -d 0,512,1024,2048 2>&1
sleep 5

# ---------- 线程数确认 ----------
hdr "1.5B · 线程数确认（干净环境）"
llama-bench -m "$M15" -ngl 0 -r 2 --no-warmup -o md \
  -p 512 -n 128 -t 2,3,4,6,8 2>&1
sleep 5

hdr "0.6B · 线程数确认（干净环境）"
llama-bench -m "$M06" -ngl 0 -r 2 --no-warmup -o md \
  -p 512 -n 128 -t 2,3,4,6,8 2>&1

hdr "结束"
echo "频率:$(read_freq)"
echo "内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null)"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
