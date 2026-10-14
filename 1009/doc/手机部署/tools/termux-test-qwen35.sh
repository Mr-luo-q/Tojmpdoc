#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 验证 Qwen3.5-2B 的混合架构在实际使用中的表现
#
# 已确认的架构事实（GGUF 元数据）：
#   Qwen3.5-2B 含一整套 SSM 字段，是「注意力 + 状态空间」混合架构
#       full_attention_interval = 4      每 4 层插 1 层全注意力
#       ssm.conv_kernel = 4
#       ssm.group_count = 16
#       ssm.state_size  = 128
#       ssm.time_step_rank = 16
#   上下文 262144，rope.freq_base 1e7，key/value_length 256
#
# 与 Qwen3-1.7B（纯注意力）的关键差异：
#   Qwen3.5 的 SSM 层是串行递归，prefill 无法大批量并行 → 浅上下文吃亏
#   但 SSM 的 KV 占用是固定大小（不随上下文增长）→ 深上下文应有优势
#
# 本脚本测三件事：
#   1. 真实推理能否跑通（新架构，先确认不崩）
#   2. 深上下文下的对比（SSM 的主场）
#   3. 实际对话效果（中文问答，看输出质量）
#
# 用法：
#   bash termux-test-qwen35.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M17="$HOME/models/Qwen3-1.7B-Q4_K_M.gguf"
M35="$HOME/models/Qwen3.5-2B-Q4_K_M.gguf"
LOG="$HOME/qwen35-test.log"
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

echo "开始: $(date '+%H:%M:%S')"
echo "频率:$(freq)"
echo

# ---------- 1. 真实推理能否跑通 ----------
echo "############################################################"
echo "# 一 · 实际推理验证（英文提示，避免 shell 编码问题）"
echo "############################################################"
# 注意：不要用 -no-cnv，llama.cpp 0.6.0 已移除这个参数，
# 加了会直接报 "error: invalid argument: -no-cnv" 而不做任何推理。
# -st（single-turn）配合 -p 提供提示词即可答完退出。
for m in "$M17" "$M35"; do
  echo "--- $(basename "$m") ---"
  llama-cli -m "$m" -t 4 -c 2048 -n 48 -ngl 0 -st \
    -p "What is 2+2? Answer in one short sentence." 2>&1 \
    | grep -viE '^(llama_|load_|print_info|init_|main:|system_info|sampler|generate|warming|common_|ggml_|build:|CUDA|Vulkan|Metal|warning:)' \
    | grep -vE '^\s*$' | tail -12
  echo
done

# ---------- 2. 深上下文对比（SSM 主场） ----------
echo "############################################################"
echo "# 二 · 上下文深度对比（-d 扫描）"
echo "############################################################"
echo "参数: -p 128 -n 64 -r 2 --no-warmup -t 4 -ngl 0"
echo "说明: SSM 的 KV 占用固定，理论上深上下文下 Qwen3.5 的衰减应更小"
echo
for m in "$M17" "$M35"; do
  echo "--- $(basename "$m") ---"
  llama-bench -m "$m" -t 4 -ngl 0 -p 128 -n 64 -d 0,512,2048,4096 -r 2 --no-warmup -o md 2>&1 \
    | grep -E '^\|' | grep -vE 'model|^-+'
  echo "  频率:$(freq)"
  echo
done

# ---------- 3. 长提示词对比 ----------
echo "############################################################"
echo "# 三 · 长提示词对比（prefill 是 SSM 的弱项）"
echo "############################################################"
echo "参数: -p 2048 -n 32 -r 2 --no-warmup -t 4 -ngl 0"
echo
for m in "$M17" "$M35"; do
  echo "--- $(basename "$m") ---"
  timeout -s KILL 600 llama-bench -m "$m" -t 4 -ngl 0 -p 2048 -n 32 -r 2 --no-warmup -o md 2>&1 \
    | grep -E '^\|' | grep -vE 'model|^-+'
  rc=$?
  [ "$rc" = "137" ] && echo "  （超时）"
  echo
done

echo "完成: $(date '+%H:%M:%S')"
echo "频率:$(freq)"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
