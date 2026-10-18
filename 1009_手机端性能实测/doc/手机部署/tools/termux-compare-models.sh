#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 四个模型的架构对比与性能实测
#
# 要回答的两件事：
#   1. 架构差异：Qwen3-1.7B 与 Qwen3.5-2B 的模型结构哪里不同
#      （用户提到"结构本身有区别"，需要把差异落到具体字段上）
#   2. 性能差异：四个模型在同一条件下的 prefill / decode 速率
#
# 四个模型（全部 Q4_K_M，同档位才可比）：
#   qwen2.5-1.5b-instruct    1.07 GB   上一代
#   Qwen3-0.6B               0.38 GB   已有
#   Qwen3-1.7B               1.06 GB   本次新增
#   Qwen3.5-2B               1.22 GB   本次新增
#
# 架构信息的获取方式：
#   llama-server 的 /v1/models 接口会返回 meta 字段，含 n_ctx、n_embd、
#   n_params、ftype 等，但不含层数、注意力头数、KV 头数（GQA 比例）。
#   这些要另找途径：llama.cpp 加载模型时的日志会打印部分信息，
#   或用 gguf 元数据读取。本脚本先用 llama-server 接口拿能拿到的，
#   再尝试从模型加载日志里补。
#
# 用法：
#   bash termux-compare-models.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

LOG="$HOME/compare-models.log"
exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

M25="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
M17="$HOME/models/Qwen3-1.7B-Q4_K_M.gguf"
M35="$HOME/models/Qwen3.5-2B-Q4_K_M.gguf"

freq() {
  local o=""
  for c in 0 4 7; do
    local v
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    o="$o cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$o"
}

echo "对比开始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "SoC: $(getprop ro.soc.model 2>/dev/null)"
echo "频率:$(freq)"
echo

# ============================================================
echo "############################################################"
echo "# 一 · 模型文件与体积"
echo "############################################################"
for m in "$M25" "$M06" "$M17" "$M35"; do
  [ -f "$m" ] || { echo "  缺失: $m"; continue; }
  printf '  %-42s %10d 字节  %6.1f MB\n' \
    "$(basename "$m")" "$(stat -c%s "$m")" \
    "$(echo "scale=1; $(stat -c%s "$m") / 1048576" | bc 2>/dev/null || echo 0)"
done
echo

# ============================================================
echo "############################################################"
echo "# 二 · 架构参数（从 llama.cpp 加载日志提取）"
echo "############################################################"
# llama-cli 加载模型时会打印架构摘要，含 n_layer / n_head / n_head_kv 等
for m in "$M25" "$M06" "$M17" "$M35"; do
  [ -f "$m" ] || continue
  echo "--- $(basename "$m") ---"
  # -n 0 表示不生成，只看加载日志
  llama-cli -m "$m" -n 0 -st -p "x" 2>&1 \
    | grep -iE 'n_layer|n_head|n_embd|n_vocab|n_ctx|arch|model type|model params|model size|ftype|n_ff|n_rot|GQA|kv' \
    | head -20 | sed 's/^/    /'
  echo
done

# ============================================================
echo "############################################################"
echo "# 三 · 四模型性能实测（统一参数）"
echo "############################################################"
echo "参数: -p 128 -n 64 -r 3 --no-warmup -t 4 -ngl 0"
echo "频率:$(freq)"
echo

for m in "$M25" "$M06" "$M17" "$M35"; do
  [ -f "$m" ] || continue
  echo "--- $(basename "$m") ---"
  llama-bench -m "$m" -t 4 -ngl 0 -p 128 -n 64 -r 3 --no-warmup -o md 2>&1 \
    | grep -E '^\|' | grep -vE 'model|^-+'
  echo "  频率:$(freq)"
  echo
done

# ============================================================
echo "############################################################"
echo "# 四 · 长提示词与长生成的补充测量"
echo "############################################################"
echo "参数: -p 512 -n 128 -r 2 --no-warmup -t 4 -ngl 0"
echo
for m in "$M17" "$M35"; do
  [ -f "$m" ] || continue
  echo "--- $(basename "$m") ---"
  llama-bench -m "$m" -t 4 -ngl 0 -p 512 -n 128 -r 2 --no-warmup -o md 2>&1 \
    | grep -E '^\|' | grep -vE 'model|^-+'
  echo
done

echo "完成: $(date '+%H:%M:%S')"
echo "频率:$(freq)"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
