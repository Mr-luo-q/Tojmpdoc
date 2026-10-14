#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 下载并安装 llama.cpp 的 Web UI 资源
#
# 为什么需要这一步：
#   浏览器打开 http://127.0.0.1:8080 返回 HTTP 415（44 字节），
#   这是官方 Android/Termux 包不含内置 UI 资源的表现。
#   需要单独下载 llama-<tag>-ui.tar.gz 并让 llama-server 用 --path 指向它。
#
# 上一个坑（上一台手机踩过，这里同样适用）：
#   ui.tar.gz 解开后内部可能多一层 tag 目录，
#   --path 指错一层同样是 415。所以先看结构再决定指向哪一层。
#
# 下载在手机上执行（电脑侧连不上 GitHub，手机侧可以）。
#
# 用法：
#   bash termux-install-ui.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

TAG="b11429"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-ui.tar.gz"
UIDIR="$HOME/llama-ui"
TAR="$HOME/ui.tar.gz"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 下载 UI 资源"
echo "=============================================================="
if [ -f "$TAR" ] && [ "$(stat -c%s "$TAR" 2>/dev/null || echo 0)" -gt 1000000 ]; then
  info "已存在 $TAR，跳过下载"
else
  info "从 GitHub 下载（约 3 MB，手机直连）"
  curl -L --fail --retry 3 --retry-delay 2 -o "$TAR" "$URL" || {
    echo "[x] 下载失败。可换镜像或稍后重试。" >&2; exit 1; }
fi
echo "文件: $TAR  $(stat -c%s "$TAR") 字节"

echo
echo "=============================================================="
echo " 包内结构（决定 --path 指向哪一层）"
echo "=============================================================="
echo "--- 前 20 条 ---"
tar -tzf "$TAR" 2>&1 | head -20
echo "--- 条目总数 ---"
tar -tzf "$TAR" 2>&1 | wc -l

echo
echo "=============================================================="
echo " 解压"
echo "=============================================================="
rm -rf "$UIDIR"
mkdir -p "$UIDIR"
tar -xzf "$TAR" -C "$UIDIR" || { echo "[x] 解压失败" >&2; exit 1; }

echo "--- 解压后的目录树（前两层） ---"
find "$UIDIR" -maxdepth 2 -type d 2>/dev/null | head -10
echo
echo "--- 找 index.html 的实际位置 ---"
FOUND=""
for p in "$UIDIR/index.html" "$UIDIR"/*/index.html "$UIDIR"/*/*/index.html; do
  if [ -f "$p" ]; then
    FOUND="$(dirname "$p")"
    break
  fi
done
if [ -n "$FOUND" ]; then
  info "index.html 所在目录: $FOUND"
else
  warn "没找到 index.html，列出实际内容排查："
  find "$UIDIR" -maxdepth 3 | head -25
  exit 1
fi

echo
echo "=============================================================="
echo " 写入 UI 路径到服务脚本"
echo "=============================================================="
# 把找到的路径记到一个文件，供 start-server.sh 读取
echo "$FOUND" > "$HOME/.llama-ui-path"
info "已记录到 ~/.llama-ui-path: $FOUND"

echo
echo "--- 目录内容抽样（确认是完整的 Web 资源） ---"
ls -1 "$FOUND" | head -15
echo "  文件总数: $(find "$FOUND" -type f | wc -l)"

echo
echo "=============================================================="
echo " 下一步"
echo "=============================================================="
cat <<EOF
 UI 路径已确定: $FOUND

 现在需要重启服务让它生效：
     bash ~/start-server.sh stop
     bash ~/start-server.sh

 重启后浏览器打开 http://127.0.0.1:8080 应当看到聊天界面。
 若仍报 415，说明 --path 指错了一层，检查上面的 "index.html 所在目录"。
EOF
