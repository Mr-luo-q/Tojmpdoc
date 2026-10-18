#!/data/data/com.termux/files/usr/bin/bash
#
# Home Assistant 启停脚本（proot + Debian 容器方案）
#
#   bash ~/start-homeassistant.sh         启动（后台脱离运行）
#   bash ~/start-homeassistant.sh stop    停止
#   bash ~/start-homeassistant.sh status  查看状态
#   bash ~/start-homeassistant.sh log     查看日志尾部
#
# 关键实现说明：
#   必须用 Termux 侧的 setsid 把整个 `proot-distro login` 会话脱离。
#   proot 默认带 --kill-on-exit，login 会话一退出就会杀掉容器内所有进程，
#   所以在容器内部 fork（nohup/setsid 都在容器里执行）是无效的 ——
#   之前试过，日志连一行都来不及写。
#
set -uo pipefail

# run-as 下 PATH 不含 Termux 的 bin，必须显式设置，否则 proot-distro 找不到 proot
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

HOME_DIR="/data/data/com.termux/files/home"
VENV="$HOME_DIR/hass-venv"
CFG="$HOME_DIR/hass-config"
HALOG="$HOME_DIR/hass.log"
PORT=8123

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

lan_ip() {
  ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1
}

# 找出 HA 的 python 进程。用命令行内容匹配，因为容器内外进程名都是 python3
hass_pids() {
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *hass-venv/bin/hass*|*hass-venv/bin/python*hass*) echo "${d#/proc/}" ;; esac
  done
}

stop_ha() {
  local any=0
  # 先杀 proot 会话（它带 --kill-on-exit，退出时会清理容器内进程）
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *proot*hass-config*) kill -9 "${d#/proc/}" 2>/dev/null && any=1 ;; esac
  done
  for p in $(hass_pids); do
    kill -9 "$p" 2>/dev/null && any=1
  done
  if [ "$any" = "1" ]; then info "已停止 Home Assistant"; else warn "未发现运行中的 Home Assistant"; fi
}

status_ha() {
  local code ip
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then
    info "Home Assistant 正在运行（HTTP $code）"
    echo "  本机:   http://127.0.0.1:$PORT"
    ip="$(lan_ip)"
    [ -n "$ip" ] && echo "  局域网: http://$ip:$PORT"
    echo "  版本:   $(cat "$CFG/.HA_VERSION" 2>/dev/null || echo 未知)"
  else
    warn "Home Assistant 未响应（HTTP ${code:-000}）"
  fi
}

start_ha() {
  [ -x "$VENV/bin/hass" ] || { echo "[x] 找不到 $VENV/bin/hass" >&2; exit 1; }
  [ -f "$CFG/configuration.yaml" ] || { echo "[x] 找不到 $CFG/configuration.yaml" >&2; exit 1; }

  # 已在运行就直接报告
  if [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)" = "200" ]; then
    info "Home Assistant 已经在运行"
    status_ha
    return 0
  fi

  stop_ha >/dev/null 2>&1
  sleep 2

  info "正在启动（首次启动要 2~5 分钟，之后约 20~40 秒）..."
  # setsid 在 Termux 侧，把整个 login 会话脱离，HA 才能长期存活
  setsid proot-distro login debian -- \
    "$VENV/bin/hass" -c "$CFG" > "$HALOG" 2>&1 < /dev/null &

  local ok=0
  for i in $(seq 1 40); do
    sleep 8
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)
    case "$code" in 200|302) ok=1; break ;; esac
  done

  if [ "$ok" = "1" ]; then
    ip="$(lan_ip)"
    info "Home Assistant 已就绪"
    echo ""
    echo "  手机浏览器: http://127.0.0.1:$PORT"
    [ -n "$ip" ] && echo "  局域网:     http://$ip:$PORT"
    echo ""
    echo "  首次使用需在浏览器里创建管理员账户（数据仅存本机）"
    echo "  停止服务: bash ~/start-homeassistant.sh stop"
    echo "  查看日志: bash ~/start-homeassistant.sh log"
  else
    echo "[x] 启动超时，日志末尾：" >&2
    tail -20 "$HALOG" >&2
    exit 1
  fi
}

case "${1:-start}" in
  stop)   stop_ha ;;
  status) status_ha ;;
  log)    tail -40 "$HALOG" 2>/dev/null || echo "（无日志）" ;;
  *)      start_ha ;;
esac
