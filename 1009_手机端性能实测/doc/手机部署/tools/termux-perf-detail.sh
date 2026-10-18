#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 细粒度性能采样（prefill / decode 分离）
#
# 目标：产出可直接写进文档的详细数据，而不只是一个总 t/s。
#
# 为什么要把 prefill 与 decode 分开看：
#   prefill（提示词处理）是计算受限，影响因素是提示词长度、批大小、核心数
#   decode（逐 token 生成）是访存受限，影响因素是模型体积、上下文深度、内存带宽
#   两者对同一组参数的响应方向往往是相反的（例如线程数），
#   合在一起看会互相掩盖。
#
# 四组扫描：
#   A 提示词长度扫描    -p 32,64,128,256,512,1024,2048,4096   固定 -n 32
#   B 生成长度扫描      -n 16,32,64,128,256,512              固定 -p 128
#   C 上下文深度扫描    -d 0,512,1024,2048,4096              固定 -p 128 -n 64
#   D 批大小扫描        -b 64,128,256,512,1024               固定 -p 1024 -n 32
#
# 变量控制：
#   -ngl 0    纯 CPU（当前 loader 已是桌面版，不会接管张量分配）
#   -t 4      已实测的最优线程数
#   -r 3      每组重复 3 次，取平均与标准差
#   --no-warmup  去掉预热，避免预热与正式测量混在一起
#   --delay 2    组间留 2 秒，减少热累积
#
# 全程记录各核频率与温度，用于判断数据是否被降频污染。
#
# 用法：
#   bash termux-perf-detail.sh
#
# 输出：~/perf-detail.log（结构化文本，便于直接摘进文档）

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
LOG="$HOME/perf-detail.log"

exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# ---- 采样辅助 ----
read_freq() {
  local out=""
  for c in 0 4 7; do
    local v
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    out="$out cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$out"
}

section() {
  echo
  echo "############################################################"
  echo "# $*"
  echo "############################################################"
}

# 统一的 llama-bench 调用包装：打印前后频率，输出 markdown 表
bench() {
  local label="$1" model="$2"; shift 2
  echo
  echo "=== $label ==="
  echo "参数: $*"
  echo "跑前频率:$(read_freq)"
  # --no-warmup 让每一次测量都是独立冷启（模型仍在页缓存，但无预热计算）
  # -o md 输出 markdown 表，便于直接贴进文档
  llama-bench -m "$model" -ngl 0 -t 4 --no-warmup --delay 2 -o md "$@" 2>&1
  echo "跑后频率:$(read_freq)"
}

echo "############################################################"
echo "# 设备与环境"
echo "############################################################"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "SoC: $(getprop ro.soc.model 2>/dev/null)"
echo "内核: $(uname -r)"
echo "llama.cpp: $(llama-cli --version 2>&1 | head -1)"
echo "后端设备: $(llama-cli --list-devices 2>&1 | tail -2 | tr '\n' ' ')"
echo "内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null)"
echo "起始频率:$(read_freq)"
echo
echo "CPU 拓扑（已实测确证）:"
echo "  cluster0  cpu0-3  2200MHz  4x Cortex-A510"
echo "  cluster1  cpu4-6  3200MHz  3x Cortex-A715"
echo "  cluster2  cpu7    3350MHz  1x Cortex-A720"
echo
echo "固定参数: -ngl 0（纯 CPU）  -t 4（实测最优）  -r 3  --no-warmup  --delay 2"

section "A · 提示词长度扫描（测 prefill 随长度的变化）"
echo "固定 -n 32。关注 pp 列，看提示词变长时 t/s 是否上升（批量效率）还是下降（带宽/缓存压力）。"
bench "A1 · Qwen2.5-1.5B" "$M15" -p 32,64,128,256,512,1024,2048,4096 -n 32 -r 3
bench "A2 · Qwen3-0.6B"   "$M06" -p 32,64,128,256,512,1024,2048,4096 -n 32 -r 3

section "B · 生成长度扫描（测 decode 随长度的稳定性）"
echo "固定 -p 128。关注 tg 列，看生成变长时速度是否衰减（KV 增长导致）。"
bench "B1 · Qwen2.5-1.5B" "$M15" -p 128 -n 16,32,64,128,256,512 -r 3
bench "B2 · Qwen3-0.6B"   "$M06" -p 128 -n 16,32,64,128,256,512 -r 3

section "C · 上下文深度扫描（测 KV 缓存变长对 decode 的影响）"
echo "-d 表示预填充多少 token 作为上下文，再测 pp/tg。这是模拟长对话的关键指标。"
bench "C1 · Qwen2.5-1.5B" "$M15" -p 128 -n 64 -d 0,512,1024,2048,4096 -r 3
bench "C2 · Qwen3-0.6B"   "$M06" -p 128 -n 64 -d 0,512,1024,2048,4096 -r 3

section "D · 批大小扫描（测 prefill 的并行效率）"
echo "固定 -p 1024 -n 32。批越大单次矩阵乘越大，理论上 prefill 越快，但受缓存限制。"
bench "D1 · Qwen2.5-1.5B" "$M15" -p 1024 -n 32 -b 64,128,256,512,1024 -r 3
bench "D2 · Qwen3-0.6B"   "$M06" -p 1024 -n 32 -b 64,128,256,512,1024 -r 3

section "E · 线程数复测（在纯 CPU 环境下确认 -t 4 最优）"
echo "之前测线程数时环境里还有 Vulkan 后端干扰，这次是干净环境，重新确认。"
bench "E1 · Qwen2.5-1.5B" "$M15" -p 512 -n 128 -t 2,3,4,5,6,7,8 -r 3

section "F · 结构化输出（jsonl，便于后续分析）"
for m in "$M15" "$M06"; do
  echo
  echo "=== $(basename "$m") jsonl ==="
  llama-bench -m "$m" -ngl 0 -t 4 --no-warmup -r 3 -o jsonl \
      -p 128,512,2048 -n 32,128 2>&1
done

section "结束"
echo "跑完频率:$(read_freq)"
echo "内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null)"
echo "完成时间: $(date '+%Y-%m-%d %H:%M:%S')"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo
echo "日志: $LOG"
