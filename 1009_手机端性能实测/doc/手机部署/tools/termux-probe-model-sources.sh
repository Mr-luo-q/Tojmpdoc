#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 探测模型下载源并搜索候选仓库
#
# 背景：
#   电脑侧连不上 HuggingFace 与 GitHub（"无法连接到远程服务器"），
#   手机侧可以（之前实测 9.55 MB/s 直连 GitHub）。
#   所以模型必须让手机自己下载。
#
# 本脚本做三件事：
#   1. 逐个测试下载源的可达性（ModelScope / HF 镜像 / HF 官方 / GitHub）
#   2. 在可达的源上搜索候选仓库（Qwen3-1.7B 与 Qwen3.5-2B 的 GGUF）
#   3. 对找到的仓库列出文件清单与体积，供选择量化档位
#
# 注意 Qwen3.5 的命名存在不确定性（"Qwen3.5" 与 "Qwen3_5" 都有写法），
# 所以搜索用多个关键词，不假定具体仓库名。
#
# 用法：
#   bash termux-probe-model-sources.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

LOG="$HOME/model-sources.log"
exec > "$LOG" 2>&1

echo "探测时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# ---------- 1. 源可达性 ----------
echo "=============================================================="
echo " 一 · 下载源可达性"
echo "=============================================================="
probe() {
  local name="$1" url="$2"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 15 -L "$url" 2>/dev/null)
  local t
  t=$(curl -s -o /dev/null -w '%{time_total}' -m 15 -L "$url" 2>/dev/null)
  printf '  %-34s HTTP %-4s  %.2f s\n' "$name" "${code:-ERR}" "${t:-0}"
}

probe "ModelScope 主站"        "https://modelscope.cn"
probe "ModelScope API"         "https://modelscope.cn/api/v1/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF"
probe "HF 官方"                "https://huggingface.co"
probe "hf-mirror.com"          "https://hf-mirror.com"
probe "GitHub"                 "https://github.com"
probe "GitHub API"             "https://api.github.com"
echo

# ---------- 2. 搜索候选仓库 ----------
echo "=============================================================="
echo " 二 · 搜索候选仓库（HF 镜像优先，手机可直连）"
echo "=============================================================="
search_hf() {
  local label="$1" q="$2"
  echo "--- $label  关键词: $q ---"
  local out
  out=$(curl -s -m 25 "https://hf-mirror.com/api/models?search=$q&limit=12" 2>/dev/null)
  if [ -z "$out" ]; then
    echo "  （无响应）"
  else
    # 只抽 id 字段，避免输出过长
    echo "$out" | tr ',' '\n' | grep -o '"id":"[^"]*"' | sed 's/"id":"//; s/"$//' | head -12 | sed 's/^/  /'
  fi
  echo
}

search_hf "Qwen3 1.7B GGUF"    "Qwen3-1.7B-GGUF"
search_hf "Qwen3 1.7B 任意"    "Qwen3-1.7B"
search_hf "Qwen3.5 2B GGUF"    "Qwen3.5-2B-GGUF"
search_hf "Qwen3.5 2B 点号变体" "Qwen3_5-2B"
search_hf "Qwen3.5 2B 任意"    "Qwen3.5-2B"

# ---------- 3. 已确认的候选仓库文件清单 ----------
echo "=============================================================="
echo " 三 · 候选仓库的文件清单"
echo "=============================================================="
list_repo() {
  local repo="$1"
  echo "--- $repo ---"
  local out
  out=$(curl -s -m 25 "https://hf-mirror.com/api/models/$repo" 2>/dev/null)
  if [ -z "$out" ]; then
    echo "  （无响应或仓库不存在）"
    echo
    return
  fi
  # 抽出所有 .gguf 文件名
  echo "$out" | tr ',' '\n' | grep -o '"rfilename":"[^"]*\.gguf"' | sed 's/"rfilename":"//; s/"$//' | head -15 | sed 's/^/  /'
  echo
}

# 这些是搜索结果里可能出现的仓库，逐个列文件
for r in \
  "Qwen/Qwen3-1.7B-GGUF" \
  "unsloth/Qwen3-1.7B-GGUF" \
  "bartowski/Qwen_Qwen3-1.7B-GGUF" \
  "Qwen/Qwen3.5-2B-GGUF" \
  "unsloth/Qwen3.5-2B-GGUF" \
  "diodel/Qwen3.5-2B-Q4_K_M-GGUF" ; do
  list_repo "$r"
done

# ---------- 4. 本地已有的模型 ----------
echo "=============================================================="
echo " 四 · 本地现有模型"
echo "=============================================================="
ls -lh "$HOME/models/" 2>/dev/null | tail -n +2 | awk '{print "  " $9 "  " $5}'
echo

echo "=============================================================="
echo " 结论写法"
echo "=============================================================="
cat <<'EOF'
 从第二、三节挑出「确实存在且手机可达」的仓库，再用 curl 直接下载。
 下载命令示例（Q4_K_M 档）：
   curl -L --fail -o ~/models/Qwen3-1.7B-Q4_K_M.gguf \
     https://hf-mirror.com/<repo>/resolve/main/<文件名>

 注意 Qwen3.5 若只有 Base 版而无 Instruct 版，
 对话效果会明显差（Base 未做指令微调），需要留意区分。
EOF

echo
echo "日志: $LOG"
