#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 验证 llama-server 的 Web UI 是否可用
#
# 背景：
#   官方 Android/Termux 的 llama-cpp 包不含内置 Web UI 资源。
#   缺资源时浏览器打开会返回 HTTP 415（44 字节），那是 gzip 相关的报错，
#   用户看到的是「Error: gzip is not supported by this browser」。
#   修法：下载 llama-<tag>-ui.tar.gz 并用 --path 指向解得的那一层目录。
#
# 本脚本做四项检查：
#   1. /health 服务是否活着
#   2. / 的 HTTP 状态码与响应体大小（200 + 较大字节数 = UI 可用）
#   3. 响应体开头是不是 HTML
#   4. 静态资源（_app 目录下的 js/css）能否取到
#
# 用法：
#   bash termux-verify-ui.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

PORT=8080
BASE="http://127.0.0.1:$PORT"
LOG="$HOME/verify-ui.log"

exec > "$LOG" 2>&1

echo "=============================================================="
echo " 1 · 服务健康"
echo "=============================================================="
echo "GET /health -> $(curl -s -m 5 "$BASE/health" 2>&1)"
echo

echo "=============================================================="
echo " 2 · 首页状态码与大小"
echo "=============================================================="
CODE=$(curl -s -o "$TMPDIR/ui-body.html" -w '%{http_code}' -m 15 "$BASE/" 2>/dev/null)
SIZE=$(stat -c%s "$TMPDIR/ui-body.html" 2>/dev/null || echo 0)
echo "GET /  ->  HTTP $CODE   ${SIZE} 字节"

if [ "$CODE" = "200" ] && [ "$SIZE" -gt 500 ]; then
  echo "判定: Web UI 可用"
else
  echo "判定: Web UI 不可用"
  echo "响应体内容（前 200 字节）:"
  head -c 200 "$TMPDIR/ui-body.html" 2>/dev/null
  echo
fi
echo

echo "=============================================================="
echo " 3 · 响应体是否为 HTML"
echo "=============================================================="
head -c 300 "$TMPDIR/ui-body.html" 2>/dev/null | tr -d '\0'
echo
echo

echo "=============================================================="
echo " 4 · 静态资源可访问性"
echo "=============================================================="
for p in "/favicon.svg" "/manifest.json" "/pwa-192x192.png"; do
  c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$BASE$p" 2>/dev/null)
  s=$(curl -s -o /dev/null -w '%{size_download}' -m 10 "$BASE$p" 2>/dev/null)
  echo "  GET $p  ->  HTTP $c  ${s} 字节"
done
# _app 目录下的实际文件名要动态找
echo
echo "--- _app 目录下的资源抽样（从 index.html 里提取引用） ---"
grep -o '_app/[^"]*\.\(js\|css\)' "$TMPDIR/ui-body.html" 2>/dev/null | head -3 | while read -r asset; do
  c=$(curl -s -o /dev/null -w '%{http_code}' -m 15 "$BASE/$asset" 2>/dev/null)
  s=$(curl -s -o /dev/null -w '%{size_download}' -m 15 "$BASE/$asset" 2>/dev/null)
  echo "  GET /$asset  ->  HTTP $c  ${s} 字节"
done
echo

echo "=============================================================="
echo " 5 · 服务端日志里的 UI 相关记录"
echo "=============================================================="
grep -iE 'serving|ui|static|path' "$HOME/server.log" 2>/dev/null | tail -8
echo

echo "=============================================================="
echo " 结论"
echo "=============================================================="
if [ "$CODE" = "200" ] && [ "$SIZE" -gt 500 ]; then
  cat <<EOF
 Web UI 已就绪。
   手机浏览器: http://127.0.0.1:$PORT
   局域网:     http://$(ifconfig 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1):$PORT
 EOF
else
  cat <<EOF
 Web UI 仍不可用（HTTP $CODE）。
 排查顺序：
   1. 确认 ~/.llama-ui-path 的内容指向含 index.html 的目录
        cat ~/.llama-ui-path
        ls \$(cat ~/.llama-ui-path)/index.html
   2. 确认服务是用 --path 启动的（看上面第 5 节的日志）
   3. 若日志里没有 --path，重新运行 bash ~/start-server.sh
 EOF
fi

echo
echo "日志: $LOG"
