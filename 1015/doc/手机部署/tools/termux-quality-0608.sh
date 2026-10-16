#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · Qwen3-0.6B 与 Qwen3.5-0.8B 的答案质量对照
#
# 为什么只跑三题：
#   速度对照回答「哪个快」，但快而答错没有意义。
#   题库里只有 01（JSON 抽取，total=41）、02（订单字段抽取）、06（17×23−19=372）
#   三题有唯一正确答案，可以一眼判对错；04/08 这类带长度与用词约束的题
#   需要人读，留在人工验收里，不混进自动对照。
#
# 参数写法注意（llama-cli 与 llama-bench 不同）：
#   禁止 KV 卸载     llama-cli 写 -nkvo（不带值），llama-bench 写 -nkvo 1
#   禁止算子卸载     llama-cli 只有 --no-op-offload，没有短别名
#   写错会在每一题上静默失败，整份日志只剩重复的错误行。
#
# 中文提示词用 -f 从文件读入，不走 shell 参数，避免编码被破坏。
#
# 用法：
#   bash termux-quality-0608.sh
# 产出：
#   ~/quality-0608.log

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
M08="$HOME/models/Qwen3.5-0.8B-Q4_K_M.gguf"
OUT="$HOME/quality-0608.log"

exec > "$OUT" 2>&1

# 固定参数：与测速用的标准口径一致，只把 -o json 换成交互式单轮提问。
COMMON="-ngl 0 -dev none -nkvo --no-op-offload -t 4 -c 2048 -fa off -ctk f16 -ctv f16 -n 128 -st --reasoning off"

echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "固定参数: $COMMON"
echo

for pair in "06:$M06" "08:$M08"; do
  tag="${pair%%:*}"
  model="${pair#*:}"
  echo "############################################################"
  echo "# 模型 $tag  $(basename "$model")"
  echo "############################################################"
  for q in 01 02 06; do
    echo
    echo "======================= 题$q ======================="
    # 只保留答案区：模型加载日志和指令说明都在这之前，与答案无关。
    llama-cli -m "$model" $COMMON -f "$HOME/prompts/题$q.txt" 2>&1 | tail -14
  done
  echo
done

echo "完成: $(date '+%Y-%m-%d %H:%M:%S')"
echo "日志: $OUT"
