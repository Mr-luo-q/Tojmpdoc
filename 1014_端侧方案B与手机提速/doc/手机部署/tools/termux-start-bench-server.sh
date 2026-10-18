#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 实验用 llama-server 启动器
#
# 目的：为「首字延迟 / 前缀缓存」这类必须走真实 HTTP 的测量提供受控服务。
# 与日常 start-server.sh 的区别：
#   · 端口默认 8081，不与日常 8080 服务冲突，可以同时存在
#   · 参数全部显式写出（FA、KV 类型、线程、GPU 关闭），不依赖默认值
#   · 日志写到独立文件，便于与结果目录一起归档
#
# 用法：
#   bash termux-start-bench-server.sh <模型路径> [端口] [fa] [kv]
#   bash termux-start-bench-server.sh ~/models/Qwen3-0.6B-Q4_K_M.gguf 8081 on q8_0
#   bash termux-start-bench-server.sh stop 8081

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

ACTION="${1:?用法: termux-start-bench-server.sh <模型路径> [端口] [fa] [kv] 或 stop <端口>}"

# 停止模块：只结束命令行里带 --port 指定端口的那个 llama-server。
stop_server() {
  local port="$1" found=0
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    if tr '\0' ' ' < "$d/cmdline" 2>/dev/null | grep -q -- "--port $port"; then
      echo "停止 pid=${d#/proc/} (port=$port)"
      kill -15 "${d#/proc/}" 2>/dev/null && found=1
    fi
  done
  [ "$found" = "0" ] && echo "端口 $port 上没有找到 llama-server"
}

if [ "$ACTION" = "stop" ]; then
  stop_server "${2:-8081}"
  exit 0
fi

MODEL="$ACTION"
PORT="${2:-8081}"
FA="${3:-on}"
KV="${4:-f16}"
LOG="$HOME/bench-server-$PORT.log"

# 单实例保护：同端口已有服务时先停掉，避免两个进程抢核。
stop_server "$PORT"
sleep 1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# -ngl 0 与 --device none 双重禁用 GPU：本机装着 Vulkan 后端，
# 只写 -ngl 0 不足以保证张量留在 CPU。
# --parallel 1 保证单序列，缓存行为可解释。
# --reasoning off 关闭 Qwen3 默认思考，否则首字延迟测的是思考文本前缀。
# shellcheck disable=SC2086
nohup llama-server -m "$MODEL" \
  -t 4 -tb 4 -c 4096 -b 512 -ub 128 \
  -ngl 0 --device none --no-kv-offload --no-op-offload \
  -fa "$FA" -ctk "$KV" -ctv "$KV" \
  --jinja --reasoning off --parallel 1 --metrics \
  --host 127.0.0.1 --port "$PORT" \
  > "$LOG" 2>&1 &

echo "启动中：模型=$(basename "$MODEL") 端口=$PORT fa=$FA kv=$KV"
for i in $(seq 1 30); do
  sleep 2
  if curl -s -m 3 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q ok; then
    echo "就绪：http://127.0.0.1:$PORT"
    echo "日志：$LOG"
    exit 0
  fi
done

echo "启动失败，日志末尾："
tail -20 "$LOG"
exit 1
