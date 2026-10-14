#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 推理期间的核心频率与温度采样
#
# 为什么要测这个：
#   本机 pp（提示词处理，计算受限）只有 20.7 t/s，
#   而上一台华为 Pura 70 是 48~54 t/s，差 2.3 倍。
#   但本机 CPU 时钟更高（A715 3.2GHz vs 华为大核 2.3GHz），
#   指令集还更全（多了 sve2）。差距不该这么大。
#
#   两个待排除的假设：
#     假设 1  推理时核心没跑在最高频率（调度器压频或热限流）
#              验证：一边跑推理，一边连续采样 scaling_cur_freq
#     假设 2  scaling_max_freq 被系统压低
#              验证：读各核 scaling_max_freq 与 cpuinfo_max_freq 对比
#
# 用法：
#   bash termux-freq-sample.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
LOG="$HOME/freq-sample.log"

exec > "$LOG" 2>&1

echo "=============================================================="
echo " 一、静态：频率上限对不对"
echo "=============================================================="
for c in 0 4 6 7; do
  base="/sys/devices/system/cpu/cpu$c/cpufreq"
  cinf=$(cat "$base/cpuinfo_max_freq" 2>/dev/null)
  smax=$(cat "$base/scaling_max_freq" 2>/dev/null)
  smin=$(cat "$base/scaling_min_freq" 2>/dev/null)
  gov=$(cat "$base/scaling_governor" 2>/dev/null)
  avail=$(cat "$base/scaling_available_governors" 2>/dev/null)
  echo "cpu$c: cpuinfo_max=$(( ${cinf:-0} / 1000 ))MHz  scaling_max=$(( ${smax:-0} / 1000 ))MHz  scaling_min=$(( ${smin:-0} / 1000 ))MHz"
  echo "      governor=$gov  可用: $avail"
done

echo
echo "=============================================================="
echo " 二、动态：推理期间连续采样"
echo "=============================================================="
if [ ! -f "$MODEL" ]; then
  echo "模型不在，跳过"
  exit 1
fi

echo "在后台启动持续推理（pp512 n256 t4 r5，约 1~2 分钟）"
if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

llama-bench -m "$MODEL" -p 512 -n 256 -ngl 0 -t 4 -r 5 > "$HOME/freq-inference.log" 2>&1 &
BENCH_PID=$!
echo "推理进程 PID=$BENCH_PID"

# 等它真正爬起来（模型加载需要时间）
sleep 15

echo
echo "--- 每 2 秒采一次，共 20 次 ---"
printf '%-6s %-10s %-10s %-10s %-10s\n' "序号" "cpu0小核" "cpu4中核" "cpu6中核" "cpu7大核"
for i in $(seq 1 20); do
  vals=""
  for c in 0 4 6 7; do
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    if [ -n "$v" ]; then
      vals="$vals $(printf '%-10s' "$((v / 1000))MHz")"
    else
      vals="$vals $(printf '%-10s' "n/a")"
    fi
  done
  printf '%-6s%s\n' "$i" "$vals"
  sleep 2
done

echo
echo "--- 等待推理结束 ---"
wait $BENCH_PID 2>/dev/null
echo "推理完成"
echo
echo "--- 推理结果 ---"
grep -E '^\|' "$HOME/freq-inference.log" 2>/dev/null | grep -vE 'model|^-+' | head -6

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 看采样里 cpu4/cpu6/cpu7 是否稳定在 3200/3350 MHz 附近：

 是（稳定在高频）
     → 频率不是瓶颈。pp 偏低应归因于内存带宽或每周期吞吐，
       属于硬件差异，调参无法改善。

 否（明显低于 3200，例如 1500~2000 波动）
     → 调度器在有意识地压频省电。Android 的 schedutil 在小负载下
       会降频，而 llama.cpp 的推理负载特征（大量短时计算交替访存）
       可能被误判为轻负载。
       可行对策：换成 performance governor（需要 root），
       或用 taskset 把线程固定在少量核心上，让调度器认为负载集中。

 scaling_max_freq 明显低于 cpuinfo_max_freq
     → 系统已经在限频（可能是温度或厂商策略）。看电池温度确认。
EOF
