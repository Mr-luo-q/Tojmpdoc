#!/data/data/com.termux/files/usr/bin/bash
#
# 启动 llama-server 并选择模型
#
#   bash ~/start-server.sh              用默认模型（1.5B，质量优先）
#   MODEL=06 bash ~/start-server.sh     用 0.6B（速度优先，快约 3 倍）
#   THINK=1 bash ~/start-server.sh      允许思考（默认关闭，见下）
#   bash ~/start-server.sh stop         停止服务
#   bash ~/start-server.sh status       查看状态
#
# 可用环境变量覆盖：
#   MODEL=15|06     选模型（默认 15）
#   THREADS=8       线程数
#   CTX=2048        上下文长度
#   PORT=8080       端口
#   THINK=0|1       是否允许思考模式（默认 0）
#
set -uo pipefail

# 保证 curl / ifconfig 等命令能解析到
# （通过 adb run-as 调用时 PATH 可能不含 Termux 的 bin 目录）
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

# 推导家目录。通过 adb run-as 调用时 $HOME 可能是 /data/user/0/com.termux，
# 并非 Termux 的实际家目录，所以优先用脚本自身路径 + 硬编码兜底。
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
H="$(dirname "$SELF_DIR")"
[ -d "$H/llama-android" ] || H="/data/data/com.termux/files/home"
[ -d "$H/llama-android" ] || H="$HOME"

D="$H/llama-android/llama-b11146"
UI="$H/llama-android/ui/llama-b11146"
LOG="$H/server.log"

# 模型选择。实测数据见 提速调研报告.md：
#   1.5B  decode 17~22 t/s，温升 +36°C
#   0.6B  decode 50~52 t/s，温升 +18°C（需关闭思考模式，否则回答为空）
case "${MODEL:-15}" in
  06|0.6|0.6b|qwen3) MODEL_FILE="Qwen3-0.6B-Q4_K_M.gguf" ;;
  *)                  MODEL_FILE="qwen2.5-1.5b-instruct-q4_k_m.gguf" ;;
esac
M="$H/models/$MODEL_FILE"

PORT_ARG="${PORT:-8080}"
THREADS="${THREADS:-8}"
CTX="${CTX:-2048}"

# 思考模式。Qwen3 默认会把 max_tokens 全花在思考上、content 留空，
# 所以默认在服务端关掉，不必每次提问都加 /no_think。
#
# 实测四种关法（Qwen3-0.6B，问 "What is 2+2?"，max_tokens=60）：
#   不加参数                content=""                    finish=length  无效
#   --reasoning-budget 0    content="Okay, the user..."   finish=length  无效
#   --reasoning off         content="2"                   finish=stop    有效
#   --chat-template-kwargs  content="2"                   finish=stop    有效
# 采用最简洁的 --reasoning off。需要思考能力时用 THINK=1 启动。
if [ "${THINK:-0}" = "1" ]; then
  REASONING_ARGS=""
else
  REASONING_ARGS="--reasoning off"
fi

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

server_pids() {
  for d in /proc/[0-9]*; do
    [ -r "$d/comm" ] || continue
    [ "$(cat "$d/comm" 2>/dev/null)" = "llama-server" ] && echo "${d#/proc/}"
  done
}

lan_ip() {
  ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1
}

current_model() {
  grep -o 'models/[^ ]*' "$LOG" 2>/dev/null | tail -1 | sed 's|models/||'
}

stop_server() {
  local any=0
  for p in $(server_pids); do
    kill -9 "$p" 2>/dev/null && { info "已停止 PID $p"; any=1; }
  done
  [ "$any" = "0" ] && warn "没有正在运行的 llama-server"
}

status_server() {
  local pids ip
  pids="$(server_pids | tr '\n' ' ')"
  if [ -n "${pids// /}" ]; then
    info "llama-server 正在运行：PID $pids"
    echo "  本机:     http://127.0.0.1:$PORT_ARG"
    ip="$(lan_ip)"
    [ -n "$ip" ] && echo "  局域网:   http://$ip:$PORT_ARG"
    echo "  当前模型: $(current_model)"
    if [ -z "$REASONING_ARGS" ]; then
      echo "  思考模式: 开启"
    else
      echo "  思考模式: 关闭（--reasoning off）"
    fi
  else
    warn "llama-server 未运行，用 'bash ~/start-server.sh' 启动"
  fi
}

case "${1:-start}" in
  stop)   stop_server; exit 0 ;;
  status) status_server; exit 0 ;;
esac

[ -f "$D/llama-server" ] || { echo "[x] 找不到 $D/llama-server，请先运行 termux-llama-prebuilt.sh" >&2; exit 1; }
[ -f "$M" ] || {
  echo "[x] 找不到模型 $M" >&2
  echo "    可用的模型：" >&2
  ls -1 "$H/models" 2>/dev/null | sed 's/^/      /' >&2
  exit 1
}
[ -f "$UI/index.html" ] || warn "找不到 Web 界面资源（$UI），服务仍可用，但浏览器打开会报错"

stop_server >/dev/null 2>&1
sleep 1

# Android 的 bionic linker 不支持 $ORIGIN RPATH，必须显式设置库搜索路径
export LD_LIBRARY_PATH="$D:/data/data/com.termux/files/usr/lib"

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# REASONING_ARGS 需要按空格拆开传给 llama-server，所以不加引号
# shellcheck disable=SC2086
nohup "$D/llama-server" -m "$M" -t "$THREADS" -c "$CTX" \
  --host 0.0.0.0 --port "$PORT_ARG" --jinja --path "$UI" --metrics \
  $REASONING_ARGS > "$LOG" 2>&1 &

info "正在启动 $MODEL_FILE（首次加载模型约 2~5 秒）..."
ok=0
for i in $(seq 1 20); do
  sleep 2
  if curl -s -m 3 "http://127.0.0.1:$PORT_ARG/health" 2>/dev/null | grep -q ok; then
    ok=1
    break
  fi
done

if [ "$ok" = "1" ]; then
  ip="$(lan_ip)"
  info "服务已就绪"
  echo ""
  echo "  模型:       $MODEL_FILE"
  if [ -z "$REASONING_ARGS" ]; then
    echo "  思考模式:   开启"
  else
    echo "  思考模式:   关闭"
  fi
  echo "  手机浏览器: http://127.0.0.1:$PORT_ARG"
  [ -n "$ip" ] && echo "  局域网:     http://$ip:$PORT_ARG"
  echo ""
  echo "  切换模型:  MODEL=06 bash ~/start-server.sh"
  echo "  开启思考:  THINK=1 bash ~/start-server.sh"
  echo "  停止服务:  bash ~/start-server.sh stop"
  echo "  查看状态:  bash ~/start-server.sh status"
  echo "  日志:      $LOG"
else
  echo "[x] 启动失败，日志末尾：" >&2
  tail -20 "$LOG" >&2
  exit 1
fi
