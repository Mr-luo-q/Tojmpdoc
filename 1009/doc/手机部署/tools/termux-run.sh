#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · Termux 环境包装器
#
# 解决的问题：
#   adb shell run-as com.termux <命令> 不会带上 Termux 的 PATH/HOME/TMPDIR，
#   直接调用脚本会因为找不到 pkg、bash、apt 而失败。
#   而从 PowerShell 里嵌套引号去传环境变量极其脆弱（$PATH 会被当成盘符语法）。
#
# 做法：把环境设置固化成本脚本，电脑侧只需要
#   adb shell run-as com.termux /data/data/com.termux/files/home/scripts/termux-run.sh <真正的脚本> [参数...]
#   从而完全避开引号嵌套。
#
# 用法：
#   termux-run.sh gpu-check          跑 GPU 能力检查（不装东西）
#   termux-run.sh gpu                跑 GPU 安装 + 验证 + 基准
#   termux-run.sh npu                跑 NPU 可达性验证
#   termux-run.sh log                打印最近一次运行的日志
#   termux-run.sh shell <命令...>    在 Termux 环境里执行任意命令

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets
export TMPDIR=/data/data/com.termux/files/usr/tmp
export PREFIX=/data/data/com.termux/files/usr
export LANG=C.UTF-8

SCRIPTS="$HOME/scripts"
ACTION="${1:-help}"
shift 2>/dev/null || true

case "$ACTION" in
  gpu-check)
    exec bash "$SCRIPTS/termux-gpu-setup.sh" --check
    ;;
  gpu)
    exec bash "$SCRIPTS/termux-gpu-setup.sh"
    ;;
  npu)
    exec bash "$SCRIPTS/termux-npu-probe.sh"
    ;;
  log)
    # 打印最近一次跑的日志；没有日志时说明还没跑过
    for f in "$HOME/gpu-setup-out.log" "$HOME/gpu-bench.log"; do
      [ -f "$f" ] || continue
      echo "===== $f ====="
      tail -60 "$f"
      echo
    done
    ;;
  shell)
    # 把剩余参数当命令执行，便于临时排查
    exec bash -c "$*"
    ;;
  *)
    cat <<'EOF'
用法: termux-run.sh <动作>

  gpu-check        只做 GPU 能力检查，不安装任何东西
  gpu              安装 llama.cpp + Vulkan 后端，验证并跑基准
  npu              NPU 可达性三层验证
  log              打印最近一次运行的日志
  shell <命令>      在 Termux 环境里执行任意命令
EOF
    ;;
esac
