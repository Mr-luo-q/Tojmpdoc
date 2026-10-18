#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 下载 Qwen3-1.7B 与 Qwen3.5-2B 的 Q4_K_M 量化
#
# 为什么选这两个源与档位：
#   源    unsloth 的两个 GGUF 仓库量化档位最全
#         （Qwen/Qwen3-1.7B-GGUF 只有 Q8_0 一个档，无法控制变量）
#   档位  Q4_K_M，与手机上已有的 Qwen2.5-1.5B 和 Qwen3-0.6B 同档，
#         这样四个模型的对比才公平
#
# 网络说明：
#   手机可直连 ModelScope（0.17 s）与 GitHub（4.42 s），
#   hf-mirror.com 可达但响应慢（15 s），HF 官方不可达。
#   所以用 hf-mirror.com，并给足超时与重试。
#
# 用法：
#   bash termux-get-models.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

MIRROR="https://hf-mirror.com"
LOG="$HOME/get-models.log"
exec > "$LOG" 2>&1

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

mkdir -p "$HOME/models"

# 下载函数：带断点续传与体积校验
# 参数: 输出文件名 仓库 仓库内文件名 期望最小体积(MB)
fetch() {
  local out="$1" repo="$2" file="$3" minsize="$4"
  local target="$HOME/models/$out"
  local url="$MIRROR/$repo/resolve/main/$file"

  echo "=============================================================="
  echo " $out"
  echo "=============================================================="
  echo "来源: $url"

  # 已有则检查体积
  if [ -f "$target" ]; then
    local have
    have=$(( $(stat -c%s "$target" 2>/dev/null || echo 0) / 1024 / 1024 ))
    if [ "$have" -ge "$minsize" ]; then
      info "已存在且体积合格（${have} MB），跳过"
      echo
      return 0
    else
      warn "已存在但体积不足（${have} MB < ${minsize} MB），续传"
    fi
  fi

  # -C - 断点续传；--retry 应对镜像偶发中断
  if curl -L --fail -C - --retry 5 --retry-delay 3 --retry-all-errors \
       -o "$target" "$url" 2>&1 | tail -3; then
    local sz
    sz=$(( $(stat -c%s "$target" 2>/dev/null || echo 0) / 1024 / 1024 ))
    if [ "$sz" -ge "$minsize" ]; then
      info "完成: ${sz} MB"
    else
      warn "下载后体积偏小（${sz} MB），可能不完整"
    fi
  else
    warn "下载失败"
  fi
  echo
}

echo "开始: $(date '+%H:%M:%S')"
echo "磁盘余量: $(df -h "$HOME" 2>/dev/null | tail -1)"
echo

# Qwen3-1.7B Q4_K_M 约 1.1 GB
fetch "Qwen3-1.7B-Q4_K_M.gguf" \
      "unsloth/Qwen3-1.7B-GGUF" \
      "Qwen3-1.7B-Q4_K_M.gguf" 900

# Qwen3.5-2B Q4_K_M 约 1.3 GB
fetch "Qwen3.5-2B-Q4_K_M.gguf" \
      "unsloth/Qwen3.5-2B-GGUF" \
      "Qwen3.5-2B-Q4_K_M.gguf" 1000

echo "=============================================================="
echo " 模型目录现状"
echo "=============================================================="
ls -lh "$HOME/models/" 2>/dev/null | tail -n +2 | awk '{printf "  %-40s %s\n", $9, $5}'
echo
echo "磁盘余量: $(df -h "$HOME" 2>/dev/null | tail -1)"
echo "完成: $(date '+%H:%M:%S')"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
