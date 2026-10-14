#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · HTTP 接口端到端计时（含首字延迟 TTFT）
#
# 为什么要单独测这个：
#   llama-bench 给的是「纯计算」的分阶段 t/s，它排除了 HTTP 层、
#   prompt 模板套用、token 采样等开销。用户真实感受到的是走接口的延迟，
#   两者可能差不少。本脚本测真实请求的三个关键时间：
#
#       TTFT  首字延迟（time to first token）
#             从发出请求到收到第一个 token，主要被 prefill 决定
#       decode 速度
#             首字之后每秒产出多少 token
#       总耗时
#
# 实现方式：
#   用 curl 的 -w 拿到精确的时间分解，关键字段：
#       time_starttransfer   开始传输第一个字节的时间 ≈ TTFT（非流式下就是全部生成完）
#       time_total           整个请求耗时
#   非流式请求拿不到真正的 TTFT（要等全部生成完才返回），
#   所以同时发一个「只生成 1 个 token」的请求来近似 TTFT，
#   再用「生成 N 个 token 的耗时」减去它，估算 decode 速度。
#
# 用法：
#   bash termux-http-timing.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

PORT=8080
URL="http://127.0.0.1:$PORT/v1/chat/completions"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
LOG="$HOME/http-timing.log"

exec > "$LOG" 2>&1

echo "=============================================================="
echo " 服务状态确认"
echo "=============================================================="
echo "健康检查: $(curl -s -m 5 http://127.0.0.1:$PORT/health 2>&1)"
echo "当前模型: $(curl -s -m 8 http://127.0.0.1:$PORT/v1/models 2>&1 | grep -o '"model":"[^"]*"' | head -1)"
echo

echo "=============================================================="
echo " Web UI 可访问性"
echo "=============================================================="
for p in "/" "/index.html"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "http://127.0.0.1:$PORT$p" 2>/dev/null)
  size=$(curl -s -o /dev/null -w '%{size_download}' -m 10 "http://127.0.0.1:$PORT$p" 2>/dev/null)
  echo "  GET $p  ->  HTTP $code   ${size} bytes"
done
echo
echo "（若 / 返回 200 且有较大字节数，说明内置 Web UI 可用；"
echo "  若返回 404 或 0 字节，说明这个构建未内置界面，需另装 UI 资源）"
echo

# 计时辅助：发一次请求并打印时间分解
# 参数: 标签 最大生成token数 提示词
timed_request() {
  local label="$1" maxtok="$2" prompt="$3"
  local body
  body=$(cat <<EOF
{
  "messages": [{"role":"user","content":"$prompt"}],
  "max_tokens": $maxtok,
  "temperature": 0,
  "stream": false
}
EOF
)
  echo "--- $label（max_tokens=$maxtok）---"
  local out
  out=$(curl -s -m 300 -X POST "$URL" \
        -H 'Content-Type: application/json' \
        -d "$body" \
        -w '\n__TIMING__ namelookup=%{time_namelookup} connect=%{time_connect} starttransfer=%{time_starttransfer} total=%{time_total} size=%{size_download}\n' 2>&1)

  # 拆出计时行与内容
  echo "$out" | grep '^__TIMING__' | sed 's/^__TIMING__ /  计时: /'
  # 从 JSON 响应里取 usage 字段（token 计数）
  local json
  json=$(echo "$out" | grep -v '^__TIMING__')
  echo "$json" | grep -o '"usage":{[^}]*}' | sed 's/^/  用量: /'
  # 取回复内容的前 60 字，确认请求真的成功
  echo "$json" | grep -o '"content":"[^"]*"' | head -1 | cut -c1-90 | sed 's/^/  回答: /'
  echo
}

echo "=============================================================="
echo " 一、当前模型（1.5B）的真实请求计时"
echo "=============================================================="
# 用不同生成长度做差值，估算纯 decode 速度
timed_request "极短生成（近似 TTFT）" 1   "Say hi."
timed_request "短生成"                 32  "Say hi."
timed_request "中生成"                 128 "Write a short paragraph about the ocean."

echo "=============================================================="
echo " 二、切到 0.6B 重测"
echo "=============================================================="
echo "（切换模型会重启服务，约 5 秒）"
bash "$HOME/start-server.sh" >/dev/null 2>&1 <<< ""
MODEL=06 bash "$HOME/start-server.sh" 2>&1 | tail -6
echo

timed_request "极短生成（近似 TTFT）" 1   "Say hi."
timed_request "短生成"                 32  "Say hi."
timed_request "中生成"                 128 "Write a short paragraph about the ocean."

echo "=============================================================="
echo " 判读方法"
echo "=============================================================="
cat <<'EOF'
 从计时行里读三个值：

   starttransfer   第一字节到达时间。max_tokens=1 时它最接近纯 TTFT
                    （提示词处理 + 首 token 采样 + 网络往返）。
   total           整请求耗时。
   size            响应字节数，用来确认响应不是空的。

 估算 decode 速度：
     decode_tps ≈ (max_tokens_大 - max_tokens_小) / (total_大 - total_小)

 与 llama-bench 的差异：
     llama-bench 的 pp/tg 是纯计算值，排除了 HTTP 与采样开销。
     这里的数字应当略低于 llama-bench，差值就是接口层的代价。
     若差得很多（超过 30%），说明接口层有额外负担值得排查。

 同时对比 1.5B 与 0.6B：
     0.6B 的 TTFT 应明显更低（权重小，prefill 更快），
     decode 也更快，但差距不如权重体积比那么大。
EOF

echo
echo "日志: $LOG"
