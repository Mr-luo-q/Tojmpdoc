#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 验证四模型能否正常推理出话
#
# 为什么单独做这一步：
#   性能基准（llama-bench）只测吞吐，不验证输出质量。
#   Qwen3 系列默认开启思考模式，会把 max_tokens 全花在思考上、
#   content 返回空字符串，表现为「模型不回答」。
#   Qwen3.5-2B 是新架构，也需要确认 llama.cpp 0.6.0 能正常处理。
#
# 参数说明：
#   必须用 -st（single-turn），不能用 -no-cnv
#   —— 后者在 llama.cpp 0.6.0 已被移除，加了会直接报
#      "error: invalid argument: -no-cnv" 且不做任何推理。
#
# 用法：
#   bash termux-verify-models.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

LOG="$HOME/verify-models.log"
exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

PROMPT="What is 2+2? Answer in one short sentence."

# 模型列表：名称 路径 是否默认开思考
check() {
  local label="$1" model="$2" extra="$3"
  echo "=============================================================="
  echo " $label"
  echo "=============================================================="
  if [ ! -f "$model" ]; then
    echo "  文件缺失"
    echo
    return
  fi
  echo "参数: -t 4 -c 2048 -n 64 -ngl 0 -st $extra"
  echo "--- 输出 ---"
  # shellcheck disable=SC2086
  llama-cli -m "$model" -t 4 -c 2048 -n 64 -ngl 0 -st $extra -p "$PROMPT" 2>&1 \
    | grep -viE '^(llama_|load_|print_info|init_|main:|system_info|sampler|generate|warming|common_|ggml_|build:|CUDA|Vulkan|Metal|warning:|error:)' \
    | grep -vE '^\s*$' \
    | tail -14
  echo
}

# Qwen2.5 不带思考模式
check "Qwen2.5-1.5B（无思考模式）" \
      "$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" ""

# Qwen3 系列默认开思考，跑两次：默认 vs 关闭
check "Qwen3-1.7B（默认，预期会思考）" \
      "$HOME/models/Qwen3-1.7B-Q4_K_M.gguf" ""

check "Qwen3-1.7B（关闭思考 --reasoning off）" \
      "$HOME/models/Qwen3-1.7B-Q4_K_M.gguf" "--reasoning off"

check "Qwen3.5-2B（默认）" \
      "$HOME/models/Qwen3.5-2B-Q4_K_M.gguf" ""

check "Qwen3.5-2B（关闭思考 --reasoning off）" \
      "$HOME/models/Qwen3.5-2B-Q4_K_M.gguf" "--reasoning off"

echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 四种可能的结果：

 A. 默认模式输出了「思考过程 + 最终答案」
     → 该模型默认开思考模式，服务端应用 --reasoning off

 B. 默认模式只有思考、没有答案（输出被 max_tokens 截断）
     → 典型的思考模式吃光 token，必须关闭

 C. --reasoning off 后输出简洁答案
     → 这是要写进 start-server.sh 的配置

 D. 报错或输出乱码
     → 该架构在当前 llama.cpp 版本上支持有问题，需要记录
EOF

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo
echo "日志: $LOG"
