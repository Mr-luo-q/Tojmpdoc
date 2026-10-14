#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 一键检查 llama-server 是否可用
#
# 用途：任何时候怀疑服务有问题，跑这一条就能看清全部状态。
#       覆盖服务进程、健康检查、Web UI 首页、静态资源、模型信息、
#       线程与上下文配置、以及局域网访问地址。
#
# 用法：
#   bash termux-check-server.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

PORT="${PORT:-8080}"
BASE="http://127.0.0.1:$PORT"

echo "=============================================================="
echo " 1 · 进程"
echo "=============================================================="
PIDS=""
for d in /proc/[0-9]*; do
  [ -r "$d/comm" ] || continue
  [ "$(cat "$d/comm" 2>/dev/null)" = "llama-server" ] && PIDS="$PIDS ${d#/proc/}"
done
if [ -n "${PIDS// /}" ]; then
  echo "  llama-server 运行中，PID:$PIDS"
else
  echo "  未运行。启动：bash ~/start-server.sh"
  exit 1
fi

echo
echo "=============================================================="
echo " 2 · 健康检查"
echo "=============================================================="
H=$(curl -s -m 6 "$BASE/health" 2>/dev/null)
echo "  GET /health  ->  ${H:-（无响应）}"

echo
echo "=============================================================="
echo " 3 · Web UI 首页"
echo "=============================================================="
CODE=$(curl -s -o "$TMPDIR/_ui.html" -w '%{http_code}' -m 15 "$BASE/" 2>/dev/null)
SIZE=$(stat -c%s "$TMPDIR/_ui.html" 2>/dev/null || echo 0)
echo "  GET /  ->  HTTP $CODE   ${SIZE} 字节"
if [ "$CODE" = "200" ] && [ "$SIZE" -gt 500 ]; then
  echo "  判定: Web UI 可用"
  # 确认是真 HTML 而不是错误页
  head -c 60 "$TMPDIR/_ui.html" 2>/dev/null | tr -d '\0' | sed 's/^/  开头: /'
  echo
else
  echo "  判定: Web UI 不可用（HTTP 415 通常表示缺 UI 资源）"
  echo "  修法: bash ~/scripts/termux-install-ui.sh && bash ~/start-server.sh"
fi

echo
echo "=============================================================="
echo " 4 · 静态资源"
echo "=============================================================="
for p in "/favicon.svg" "/pwa-192x192.png"; do
  c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$BASE$p" 2>/dev/null)
  s=$(curl -s -o /dev/null -w '%{size_download}' -m 10 "$BASE$p" 2>/dev/null)
  echo "  GET $p  ->  HTTP $c  ${s} 字节"
done

echo
echo "=============================================================="
echo " 5 · 当前加载的模型与配置"
echo "=============================================================="
curl -s -m 10 "$BASE/v1/models" 2>/dev/null \
  | tr ',' '\n' \
  | grep -oE '"(n_ctx|n_params|ftype|n_embd)":[^,}]*' \
  | sed 's/^/  /'
echo
echo "  服务端参数（来自启动脚本默认值）："
echo "    线程数 -t ${THREADS:-4}   上下文 -c ${CTX:-2048}   GPU 卸载 -ngl 0"

echo
echo "=============================================================="
echo " 6 · 访问地址"
echo "=============================================================="
IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
echo "  手机浏览器:   $BASE"
[ -n "$IP" ] && echo "  局域网:       http://$IP:$PORT"
echo "  OpenAI 兼容:  $BASE/v1/chat/completions"
echo
echo "  切换模型:  MODEL=06 bash ~/start-server.sh        （0.6B，最快）"
echo "  切换模型:  MODEL=17 bash ~/start-server.sh        （Qwen3-1.7B）"
echo "  切换模型:  MODEL=35 bash ~/start-server.sh        （Qwen3.5-2B，长上下文最优）"
echo "  停止服务:  bash ~/start-server.sh stop"
