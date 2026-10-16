#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · llama-server 极简启停器（供电脑侧评分脚本调用）
#
# 为什么不用 ~/start-server.sh：
#   那个脚本面向日常使用，模型名是固定的四个代号，还带 Web UI 与端口判断。
#   评分脚本需要的是「给定任意模型绝对路径就能起、能停、能等健康检查」，
#   而且调用方在电脑上，必须避免任何需要嵌套引号的写法。
#   所以这里只接受位置参数，不读环境变量，不打印彩色输出。
#
# 用法：
#   termux-server-ctl.sh start <模型绝对路径> [端口] [off|on]  启动并等待就绪，打印 PID
#   termux-server-ctl.sh stop                          停止所有 llama-server
#   termux-server-ctl.sh wait <端口> [秒数]            单独等待健康检查
#   termux-server-ctl.sh status                        打印当前进程
#
# 固定参数说明：
#   -t 4         K70E 实测最优线程数，跨簇会掉 decode
#   -c 2048      评分题都很短，2048 足够且省内存
#   --jinja      让服务端按模型自带模板处理对话
#   --reasoning off  Qwen3 与 Qwen3.5 默认开思考模式；第三个位置参数给 on 时
#                    故意保留思考，用于对照「关掉思考是否导致算术题退化」

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

ACTION="${1:-status}"

# 进程查找：直接遍历 /proc，避免依赖 ps 的参数差异。
pids() {
  local d
  for d in /proc/[0-9]*; do
    [ -r "$d/comm" ] || continue
    [ "$(cat "$d/comm" 2>/dev/null)" = "llama-server" ] && echo "${d#/proc/}"
  done
}

do_stop() {
  local p
  for p in $(pids); do
    kill -15 "$p" 2>/dev/null
  done
  sleep 1
  for p in $(pids); do
    kill -9 "$p" 2>/dev/null
  done
  echo "stopped"
}

do_wait() {
  # 健康检查：/health 返回 ok 才算就绪，避免把「已监听」误判成「可推理」。
  local port="${1:-8080}" limit="${2:-60}" i
  for i in $(seq 1 "$limit"); do
    if curl -s -m 2 "http://127.0.0.1:$port/health" 2>/dev/null | grep -q '"ok"'; then
      echo "ready after ${i}s"
      return 0
    fi
    sleep 1
  done
  echo "timeout waiting for port $port"
  return 1
}

case "$ACTION" in
  start)
    MODEL="${2:?需要模型绝对路径}"
    PORT="${3:-8080}"
    REASONING="${4:-off}"
    if [ "$REASONING" = "on" ]; then
      REASONING_ARG=""
    else
      REASONING_ARG="--reasoning off"
    fi
    [ -f "$MODEL" ] || { echo "模型不存在: $MODEL"; exit 1; }
    do_stop >/dev/null
    if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi
    nohup llama-server -m "$MODEL" -t 4 -c 2048 -ngl 0 \
      --host 127.0.0.1 --port "$PORT" --jinja \
      --parallel 1 $REASONING_ARG > "$HOME/eval-server.log" 2>&1 &
    echo "pid=$!"
    do_wait "$PORT" 90
    ;;
  stop)
    do_stop
    ;;
  wait)
    do_wait "${2:-8080}" "${3:-60}"
    ;;
  status)
    for p in $(pids); do echo "llama-server $p"; done
    ;;
  *)
    echo "用法: termux-server-ctl.sh start|stop|wait|status" >&2
    exit 1
    ;;
esac
