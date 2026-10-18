#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · llama-server 启停脚本（Redmi K70E / 天玑 8300 版）
#
# 与上一台手机（华为 Pura 70）那份的区别：
#   上一台是手工装的 llama-android 预编译包，二进制在 ~/llama-android/llama-b11146/，
#   需要自己设 LD_LIBRARY_PATH 并用 --path 指向单独下载的 Web UI。
#   这一台用的是 Termux 官方 llama-cpp 包，二进制在 /usr/bin 下，
#   依赖由包管理器管理，不需要手设库路径。
#
# 关键参数（均由 2026-10-09 的实测确定，见 CPU性能实测报告.md）：
#   -t 4    实测最优线程数。这台的拓扑是三簇
#           （cpu0-3 A510 2.2GHz / cpu4-6 A715 3.2GHz / cpu7 A720 3.35GHz），
#           -t 8 会让线程跨簇迁移，tg 从 14.6 掉到 7.8，损失一半以上。
#   -c 2048 1.5B 的 KV 缓存每 token 约 28 KiB，2048 上下文足够且省内存。
#   -ngl 0  明确禁用 GPU 卸载。Mali-G615 实测比 CPU 慢 3~19 倍
#           （int dot: 0，量化推理无硬件加速），必须固定为纯 CPU。
#
# 用法：
#   bash ~/start-server.sh              启动，默认 1.5B
#   MODEL=06 bash ~/start-server.sh     启动，用 0.6B（快一倍多）
#   THINK=1 bash ~/start-server.sh      允许思考模式（Qwen3 默认关闭）
#   bash ~/start-server.sh stop         停止
#   bash ~/start-server.sh status       查看状态与访问地址
#   bash ~/start-server.sh log          看日志尾部
#
# 可覆盖的环境变量：
#   MODEL=15|06     选模型（默认 15）
#   THREADS=4       线程数
#   CTX=2048        上下文长度
#   PORT=8080       端口
#   THINK=0|1       思考模式（默认 0）
#
set -uo pipefail

export PATH="/data/data/com.termux/files/usr/bin:$PATH"

H="/data/data/com.termux/files/home"
LOG="$H/server.log"

# 模型选择。四个模型的实测数据见 四模型架构与性能对比.md：
#   06  Qwen3-0.6B      tg 43 t/s   最快，浅上下文首选
#   15  Qwen2.5-1.5B    tg 19 t/s   上一代，通用
#   17  Qwen3-1.7B      tg 15 t/s   深上下文衰减重（d4096 掉 67%）
#   35  Qwen3.5-2B      tg 14 t/s   混合 SSM 架构，深上下文衰减仅 16%
#                                  长对话场景首选
case "${MODEL:-15}" in
  06|0.6|0.6b|qwen3-0.6)    MODEL_FILE="Qwen3-0.6B-Q4_K_M.gguf" ;;
  17|1.7|1.7b|qwen3-1.7)    MODEL_FILE="Qwen3-1.7B-Q4_K_M.gguf" ;;
  35|2.0|2b|qwen35|qwen3.5) MODEL_FILE="Qwen3.5-2B-Q4_K_M.gguf" ;;
  *)                        MODEL_FILE="qwen2.5-1.5b-instruct-q4_k_m.gguf" ;;
esac
M="$H/models/$MODEL_FILE"

PORT_ARG="${PORT:-8080}"
THREADS="${THREADS:-4}"

# 上下文长度。Qwen3.5-2B 支持 262144，但手机内存有限且实测 decode
# 随上下文衰减，所以默认仍取较小值；需要长对话时用 CTX=8192 显式指定。
case "${MODEL:-15}" in
  35|2.0|2b|qwen35|qwen3.5) CTX="${CTX:-4096}" ;;
  *)                        CTX="${CTX:-2048}" ;;
esac

# 思考模式。Qwen3 默认把 max_tokens 全花在思考上、content 留空，
# 表现为「模型不回答」。实测四种关法（见 提速调研报告.md）：
#   不加参数               content=""                   无效
#   --reasoning-budget 0   content="Okay, the user..."   无效
#   --reasoning off        content="2"                   有效
#   --chat-template-kwargs content="2"                   有效
# 采用最简洁的 --reasoning off。
if [ "${THINK:-0}" = "1" ]; then
  REASONING_ARGS=""
else
  REASONING_ARGS="--reasoning off"
fi

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 找出 llama-server 的 PID。用 /proc 遍历，避免依赖 ps 的参数差异
server_pids() {
  for d in /proc/[0-9]*; do
    [ -r "$d/comm" ] || continue
    [ "$(cat "$d/comm" 2>/dev/null)" = "llama-server" ] && echo "${d#/proc/}"
  done
}

lan_ip() {
  ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1
}

stop_server() {
  local any=0
  for p in $(server_pids); do
    kill -15 "$p" 2>/dev/null && { info "已停止 PID $p"; any=1; }
  done
  sleep 1
  # 还活着就强杀
  for p in $(server_pids); do
    kill -9 "$p" 2>/dev/null && { info "强制停止 PID $p"; any=1; }
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
    echo "  兼容接口: http://127.0.0.1:$PORT_ARG/v1/chat/completions"
    echo "  线程数:   $THREADS   上下文: $CTX   模型: $MODEL_FILE"
    if [ "$(curl -s -m 3 http://127.0.0.1:$PORT_ARG/health 2>/dev/null)" ]; then
      echo "  健康检查: $(curl -s -m 3 http://127.0.0.1:$PORT_ARG/health 2>/dev/null)"
    else
      warn "  健康检查无响应（可能仍在加载模型）"
    fi
  else
    warn "llama-server 未运行，用 'bash ~/start-server.sh' 启动"
  fi
}

case "${1:-start}" in
  stop)   stop_server; exit 0 ;;
  status) status_server; exit 0 ;;
  log)    tail -40 "$LOG" 2>/dev/null || warn "没有日志文件"; exit 0 ;;
esac

command -v llama-server >/dev/null 2>&1 || {
  echo "[x] 找不到 llama-server。先装：pkg install llama-cpp" >&2; exit 1; }

[ -f "$M" ] || {
  echo "[x] 找不到模型 $M" >&2
  echo "    ~/models 下现有：" >&2
  ls -1 "$H/models" 2>/dev/null | sed 's/^/      /' >&2
  exit 1
}

stop_server >/dev/null 2>&1
sleep 1

# Web UI 资源。官方包不含内置界面，缺了浏览器打开会报 HTTP 415。
# 路径记在 ~/.llama-ui-path，由 termux-install-ui.sh 写入。
# 注意 ui.tar.gz 解开后内部多一层 tag 目录（llama-b11429/），指错一层同样 415。
UI_ARGS=""
if [ -f "$H/.llama-ui-path" ]; then
  UI_DIR="$(cat "$H/.llama-ui-path" 2>/dev/null)"
  if [ -n "$UI_DIR" ] && [ -f "$UI_DIR/index.html" ]; then
    UI_ARGS="--path $UI_DIR"
    info "Web UI: $UI_DIR"
  else
    warn "~/.llama-ui-path 指向的目录里没有 index.html，界面将不可用"
  fi
else
  warn "未找到 ~/.llama-ui-path，浏览器打开会报 HTTP 415"
  warn "先运行：bash ~/scripts/termux-install-ui.sh"
fi

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# -ngl 0 显式禁用 GPU：Mali 实测比 CPU 慢 3~19 倍，绝不能用
# REASONING_ARGS 与 UI_ARGS 需要按空格拆开，所以不加引号
# shellcheck disable=SC2086
nohup llama-server -m "$M" -t "$THREADS" -c "$CTX" -ngl 0 \
  --host 0.0.0.0 --port "$PORT_ARG" --jinja --metrics \
  $UI_ARGS $REASONING_ARGS > "$LOG" 2>&1 &

info "正在启动 $MODEL_FILE（首次加载约 2~5 秒）..."
ok=0
for i in $(seq 1 15); do
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
  echo "  线程数:     $THREADS（实测最优，勿改）"
  echo "  上下文:     $CTX"
  if [ -z "$REASONING_ARGS" ]; then echo "  思考模式:   开启"; else echo "  思考模式:   关闭"; fi
  echo ""
  echo "  手机浏览器: http://127.0.0.1:$PORT_ARG"
  [ -n "$ip" ] && echo "  局域网:     http://$ip:$PORT_ARG"
  echo ""
  echo "  切换模型（四个已实测，见 四模型架构与性能对比.md）："
  echo "    MODEL=06 bash ~/start-server.sh   Qwen3-0.6B    tg 43 t/s  最快"
  echo "    MODEL=15 bash ~/start-server.sh   Qwen2.5-1.5B  tg 19 t/s  通用"
  echo "    MODEL=17 bash ~/start-server.sh   Qwen3-1.7B    tg 15 t/s  深上下文衰减重"
  echo "    MODEL=35 bash ~/start-server.sh   Qwen3.5-2B    tg 14 t/s  长对话首选"
  echo "  停止服务:  bash ~/start-server.sh stop"
  echo "  查看状态:  bash ~/start-server.sh status"
  echo "  全面自检:  bash ~/scripts/termux-check-server.sh"
  echo "  日志:      bash ~/start-server.sh log"
else
  echo "[x] 启动失败，日志末尾：" >&2
  tail -20 "$LOG" >&2
  exit 1
fi
