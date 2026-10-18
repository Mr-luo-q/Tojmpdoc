#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 注意力配置的质量回归
#
# 用途：在采用 -fa on -ctk q8_0 -ctv q8_0 之前，确认 KV 量化没有把答案改坏。
# 同一批题、同一模型、同一线程数，只切换 KV 缓存类型，逐题对照输出。
#
# 中文提示词通过文件传入（-f），不走 shell 参数，避免编码被破坏。
#
# 用法：
#   bash termux-quality-check.sh <模型路径> <标签>
#   例如 bash termux-quality-check.sh ~/models/Qwen3-0.6B-Q4_K_M.gguf 06

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

MODEL="${1:?需要模型路径}"
TAG="${2:-model}"
OUT="$HOME/quality-$TAG.log"

exec > "$OUT" 2>&1

echo "模型: $MODEL"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "固定: -t 4 -ngl 0 -dev none -nkvo --no-op-offload -c 2048 -fa on -n 128 -st --reasoning off"

# 只挑有唯一正确答案的题：01/02 结构化输出，06 算术。
# 开放题（04/08）留人工判断，不放进自动对照。
# 必须关掉思考模式：Qwen3 默认把 max_tokens 全花在思考上，
# 96 token 的预算下六次输出全部停在推理段中间，一个字段都没输出。
# 这与服务端 start-server.sh 已经使用的 --reasoning off 是同一件事。
for kv in f16 q8_0; do
  for q in 01 02 06; do
    echo
    echo "======================= kv=$kv  题$q ======================="
    # llama-cli 会把模型加载日志与答案混在一起，这里只保留最后若干行答案区。
    # 注意：llama-bench 用 "-nkvo 1 -nopo 1"，llama-cli 则是不带值的开关，
    # 而且 -nopo 在 llama-cli 里没有短别名，必须写 --no-op-offload。
    llama-cli -m "$MODEL" -ngl 0 -dev none -nkvo --no-op-offload -t 4 -c 2048 \
      -fa on -ctk "$kv" -ctv "$kv" -n 128 -st --reasoning off \
      -f "$HOME/prompts/题$q.txt" 2>&1 | tail -20
  done
done

# 再补一条对照：关掉 FA、KV 保持 f16，作为「默认档」的答案基线。
echo
echo "======================= fa off + f16  题01（对照基线） ======================="
llama-cli -m "$MODEL" -ngl 0 -dev none -nkvo --no-op-offload -t 4 -c 2048 \
  -fa off -ctk f16 -ctv f16 -n 128 -st --reasoning off \
  -f "$HOME/prompts/题01.txt" 2>&1 | tail -20

echo
echo "文件: $OUT"
