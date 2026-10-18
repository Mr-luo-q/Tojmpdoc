#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 一次性安装 llama.cpp（Android arm64 预编译，零编译）
#
# 用法（在 Termux 中）:
#   bash termux-llama-prebuilt.sh              # 装 llama.cpp
#   bash termux-llama-prebuilt.sh --model      # 顺带下载 Qwen2.5-1.5B Q4_K_M
#
# 为什么用预编译而不是自己编译：
#   在手机上编译 llama.cpp 会在链接阶段失败：
#     ld.lld: error: undefined reference: std::__ndk1::__hash_memory(...)
#   原因是 Termux 的 clang 21 与该 libc++ 版本的 ABI 不匹配。
#   官方 CI 用 Android NDK 出的 llama-*-bin-android-arm64.tar.gz 是 bionic 版本，
#   和 Termux 完全兼容，下载 72 MB 约 10 秒即可用。
#
# 重要：Android 的 bionic linker 不支持 $ORIGIN RPATH，
#   所以不能直接运行解压出来的二进制（会报 library not found），
#   必须通过设置 LD_LIBRARY_PATH 的包装脚本调用。

set -euo pipefail

BUILD_TAG="b11146"
PKG="llama-${BUILD_TAG}-bin-android-arm64.tar.gz"
SHA256="b0d154dffd3b012cac34830349725a0ee3fb6eb5e11c8aac18527b3357a79687"
BASE_URL="https://github.com/ggml-org/llama.cpp/releases/download/${BUILD_TAG}"
LLAMA_DIR="$HOME/llama-android/$BUILD_TAG"
BIN_DIR="$HOME/.local/bin"
MODEL_DIR="$HOME/models"
MODEL_FILE="qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_URLS=(
  "https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/$MODEL_FILE"
  "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/$MODEL_FILE"
)
WANT_MODEL=0

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --model) WANT_MODEL=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "未知参数: $arg" ;;
  esac
done

[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] \
  || die "看起来不在 Termux 里，请在 Termux App 中运行本脚本。"

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

info "安装 curl / tar"
pkg install -y curl tar openssl >/dev/null 2>&1 || warn "pkg install 有警告，继续"

info "下载 Android arm64 预编译包（约 72 MB）"
TMP="$HOME/$PKG"
curl -L --fail --retry 3 -o "$TMP" "$BASE_URL/$PKG" \
  || die "下载失败，请检查网络或换一个 GitHub 加速方式"

info "校验 SHA256"
ACTUAL=$(sha256sum "$TMP" | awk '{print $1}')
[ "$ACTUAL" = "$SHA256" ] || die "校验失败：期望 $SHA256，实际 $ACTUAL"
info "校验通过"

info "解压到 $LLAMA_DIR"
mkdir -p "$HOME/llama-android"
tar -xzf "$TMP" -C "$HOME/llama-android"
rm -f "$TMP"
[ -x "$LLAMA_DIR/llama-cli" ] || die "解压后没找到 llama-cli"

info "安装分发器到 $BIN_DIR"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/llama-dispatcher" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
LLAMA_DIR=$LLAMA_DIR
export LD_LIBRARY_PATH="\$LLAMA_DIR:/data/data/com.termux/files/usr/lib"
NAME=\$(basename "\$0")
exec "\$LLAMA_DIR/\$NAME" "\$@"
EOF
chmod 755 "$BIN_DIR/llama-dispatcher"

# 为每个可执行文件建软链接（用 Termux 的 ln，/system/bin/ln 在 app 私有目录会失败）
for f in "$LLAMA_DIR"/llama* "$LLAMA_DIR"/ggml-rpc-server; do
  case "$f" in *.so*) continue ;; esac
  [ -x "$f" ] || continue
  n=$(basename "$f")
  rm -f "$BIN_DIR/$n"
  ln -sf llama-dispatcher "$BIN_DIR/$n"
done
info "已安装 $(ls "$BIN_DIR" | wc -l) 个命令"

if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
  info "已把 $BIN_DIR 写入 ~/.bashrc"
fi

mkdir -p "$MODEL_DIR"
if [ "$WANT_MODEL" = "1" ]; then
  TARGET="$MODEL_DIR/$MODEL_FILE"
  if [ -f "$TARGET" ] && [ "$(stat -c%s "$TARGET" 2>/dev/null || echo 0)" -gt 500000000 ]; then
    info "模型已存在，跳过下载：$TARGET"
  else
    for url in "${MODEL_URLS[@]}"; do
      info "下载模型：$url"
      if curl -L --fail --retry 3 -C - -o "$TARGET" "$url"; then break; fi
      warn "这个源不可用，换下一个"; rm -f "$TARGET"
    done
  fi
fi

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
hash -r 2>/dev/null || true

info "完成"
cat <<EOF

  可执行文件: $BIN_DIR（llama-cli / llama-server 等）
  模型目录:   $MODEL_DIR

  llama-cli 与 llama-server 的区别（重要）:
    llama-cli    启动后是带边框的交互界面（> 提示符），
                 退出用 /exit，别用 Ctrl+C 之外的乱按
    llama-server 是 HTTP 服务，不显示对话界面，
                 要用 curl 或浏览器访问

  单次提问（会退出并打印速度）:
    llama-cli -m $MODEL_DIR/$MODEL_FILE -t 8 -c 2048 -n 128 -st -p "你的问题"

  交互对话:
    llama-cli -m $MODEL_DIR/$MODEL_FILE -t 8 -c 2048

  起 OpenAI 兼容服务:
    llama-server -m $MODEL_DIR/$MODEL_FILE -t 8 -c 2048 --host 0.0.0.0 --port 8080 --jinja

  验证服务:
    curl http://127.0.0.1:8080/health
EOF
