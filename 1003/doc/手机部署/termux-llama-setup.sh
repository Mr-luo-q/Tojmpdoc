#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · Termux + llama.cpp 一键安装
#
# 用法（在 Termux 中）:
#   bash termux-llama-setup.sh                    # 只装 llama.cpp
#   bash termux-llama-setup.sh --model            # 同时下载 Qwen2.5-1.5B-Instruct (Q4_K_M)
#   bash termux-llama-setup.sh --model --blas     # 开启 OpenBLAS，prompt 处理更快
#
# 可重复执行：已装好的部分会跳过或增量更新。

set -euo pipefail

LLAMA_DIR="$HOME/llama.cpp"
MODEL_DIR="$HOME/models"
INSTALL_DIR="$HOME/.local"
WANT_MODEL=0
USE_BLAS=0
JOBS="$(nproc 2>/dev/null || echo 4)"

MODEL_FILE="qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_URLS=(
  "https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/$MODEL_FILE"
  "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/$MODEL_FILE"
)

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法: bash termux-llama-setup.sh [选项]

  --model       下载 Qwen2.5-1.5B-Instruct Q4_K_M (约 1.0 GB)
  --blas        安装 OpenBLAS 并启用，长 prompt 处理更快
  -j<N>         编译线程数，默认取 CPU 核心数
  -h, --help    显示本帮助
EOF
}

for arg in "$@"; do
  case "$arg" in
    --model) WANT_MODEL=1 ;;
    --blas)  USE_BLAS=1 ;;
    -j*)     JOBS="${arg#-j}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数: $arg（用 -h 查看用法）" ;;
  esac
done

[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] \
  || die "看起来不在 Termux 里，请在 Termux App 中运行本脚本。"

# 编译期间别让系统把 Termux 挂起
if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

info "更新软件源并安装编译依赖"
# dpkg 遇到 openssl.cnf 这类配置文件冲突时会停下来提问，脚本必须让它自动取默认值，
# 否则会一直挂在 "*** openssl.cnf (Y/I/N/O/D/Z) [default=N] ?" 这里不动。
PREFIX_DIR_SH="${PREFIX:-/data/data/com.termux/files/usr}"
mkdir -p "$PREFIX_DIR_SH/etc/apt/apt.conf.d"
cat > "$PREFIX_DIR_SH/etc/apt/apt.conf.d/99-noninteractive" <<'APTEOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APTEOF
export DEBIAN_FRONTEND=noninteractive
pkg update -y >/dev/null 2>&1 || warn "pkg update 有警告，继续"
pkg install -y git cmake clang make binutils curl openssl libandroid-execinfo

if [ "$USE_BLAS" = "1" ]; then
  info "安装 OpenBLAS"
  pkg install -y libopenblas
fi

info "获取 llama.cpp 源码到 $LLAMA_DIR"
if [ -d "$LLAMA_DIR/.git" ]; then
  git -C "$LLAMA_DIR" pull --ff-only || warn "拉取更新失败，使用当前源码继续"
else
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
fi

CMAKE_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
  -DLLAMA_BUILD_TESTS=OFF
)
if [ "$USE_BLAS" = "1" ]; then
  CMAKE_FLAGS+=(-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS)
fi

info "编译中（线程数 $JOBS，手机上通常 10~30 分钟，请保持电量充足）"
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" "${CMAKE_FLAGS[@]}"
cmake --build "$LLAMA_DIR/build" --config Release -j"$JOBS"
cmake --install "$LLAMA_DIR/build" >/dev/null

BIN_DIR="$INSTALL_DIR/bin"
[ -x "$BIN_DIR/llama-cli" ] || die "编译完成但没找到 llama-cli，请把上面的编译日志发我。"

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
      if curl -L --fail --retry 3 --retry-delay 2 -C - -o "$TARGET" "$url"; then
        break
      fi
      warn "这个源不可用，换下一个"
      rm -f "$TARGET"
    done
    if [ ! -f "$TARGET" ] || [ "$(stat -c%s "$TARGET" 2>/dev/null || echo 0)" -lt 500000000 ]; then
      rm -f "$TARGET"
      warn "自动下载失败，请手动下载后放到 $MODEL_DIR/"
      warn "仓库地址: https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF"
    fi
  fi
fi

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
hash -r 2>/dev/null || true

info "完成"
cat <<EOF

  可执行文件: $BIN_DIR
  模型目录:   $MODEL_DIR

新开一个终端会话（或执行 source ~/.bashrc）后可用：

  连续对话
    llama-cli -m $MODEL_DIR/$MODEL_FILE -c 4096 -t 4 -cnv

  单次提问
    llama-cli -m $MODEL_DIR/$MODEL_FILE -c 4096 -t 4 -n 512 -p "用一句话解释什么是量化"

  起一个 OpenAI 兼容服务（局域网内其他设备访问 http://<手机IP>:8080）
    llama-server -m $MODEL_DIR/$MODEL_FILE -c 4096 -t 4 --host 0.0.0.0 --port 8080

提示：-t 建议设成 CPU 大核数量（一般 4），设成核心总数反而更慢。
EOF
