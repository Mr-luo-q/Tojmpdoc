#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 修复 Termux 软件包与 libc++ 版本不匹配
#
# 症状：
#   运行 vulkaninfo 或 llama-cli 时报
#     CANNOT LINK EXECUTABLE: cannot locate symbol
#     "_ZNSt6__ndk113__hash_memoryEPKvm"
#   这个符号是 std::__ndk1::__hash_memory(void const*, unsigned long)。
#
# 根因：
#   Termux 官方 v0.118.3 的 bootstrap 快照比较老，其中的 libc++_shared.so
#   不导出 __hash_memory；而仓库里的 llama-cpp 0.6.0、vulkan-tools 1.4.365
#   是后来用新版 libc++ 编译的，引用了该符号。
#
#   注意这与「在手机上编译 llama.cpp 失败」是两回事：
#     编译失败 = 源码与工具链 ABI 不匹配，无解
#     本次现象 = 已编译好的包与运行库版本不匹配，升级即可
#
# 解决：
#   1. 全量升级（pkg upgrade）把 libc++ 与所有依赖拉到仓库当前版本
#   2. 验证 libc++_shared.so 是否导出该符号
#   3. 重测 vulkaninfo 与 llama-cli
#
# 用法：
#   bash termux-fix-libcxx.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

NEEDLE="_ZNSt6__ndk113__hash_memoryEPKvm"
LIBCXX="/data/data/com.termux/files/usr/lib/libc++_shared.so"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 第 1 步 · 记录修复前的版本与符号状态"
echo "=============================================================="
echo "libc++ 包版本: $(dpkg -s libc++ 2>/dev/null | grep '^Version' || echo '(未查到)')"
echo "llama-cpp 版本: $(dpkg -s llama-cpp 2>/dev/null | grep '^Version' || echo '(未查到)')"
echo "vulkan-tools 版本: $(dpkg -s vulkan-tools 2>/dev/null | grep '^Version' || echo '(未查到)')"
echo "libc++_shared.so 大小: $(stat -c%s "$LIBCXX" 2>/dev/null)"
echo
echo "--- 修复前：libc++_shared.so 是否导出 $NEEDLE ---"
if strings "$LIBCXX" 2>/dev/null | grep -q "$NEEDLE"; then
  echo "已导出（那问题不在 libc++，需要另找原因）"
  BEFORE=yes
else
  echo "未导出  ← 这就是链接失败的根因"
  BEFORE=no
fi

echo
echo "=============================================================="
echo " 第 2 步 · 全量升级"
echo "=============================================================="
info "pkg upgrade -y（含 libc++ 与全部依赖，可能几分钟）"
# -o Dpkg::Options 让配置文件冲突时优先用包内新版本，避免交互卡住
pkg upgrade -y \
  -o Dpkg::Options::="--force-confnew" \
  -o Dpkg::Options::="--force-confdef" 2>&1 | tail -40

echo
echo "=============================================================="
echo " 第 3 步 · 验证符号是否补上"
echo "=============================================================="
echo "libc++ 包版本: $(dpkg -s libc++ 2>/dev/null | grep '^Version' || echo '(未查到)')"
echo "libc++_shared.so 大小: $(stat -c%s "$LIBCXX" 2>/dev/null)"
if strings "$LIBCXX" 2>/dev/null | grep -q "$NEEDLE"; then
  echo "✅ libc++_shared.so 现在导出了 $NEEDLE"
  AFTER=yes
else
  echo "❌ 仍然没有导出，全量升级没解决这个问题"
  AFTER=no
fi

echo
echo "=============================================================="
echo " 第 4 步 · 重测 vulkaninfo"
echo "=============================================================="
if command -v vulkaninfo >/dev/null 2>&1; then
  if vulkaninfo --summary >/tmp/vk.txt 2>&1; then
    echo "✅ vulkaninfo 运行成功"
    grep -iE 'deviceName|driverName|driverInfo|apiVersion|deviceType|GPU id|deviceID|vendorID' /tmp/vk.txt | head -20
  else
    echo "❌ vulkaninfo 仍然失败："
    head -5 /tmp/vk.txt
  fi
else
  warn "vulkaninfo 不在 PATH"
fi

echo
echo "=============================================================="
echo " 第 5 步 · 重测 llama.cpp 后端枚举"
echo "=============================================================="
if command -v llama-cli >/dev/null 2>&1; then
  echo "--- llama-cli --list-devices ---"
  llama-cli --list-devices 2>&1 | head -25
  echo
  echo "--- llama-cli --version ---"
  llama-cli --version 2>&1 | head -6
else
  warn "llama-cli 不在 PATH"
fi

echo
echo "=============================================================="
echo " 第 6 步 · 重测 clinfo（Mali OpenCL）"
echo "=============================================================="
if command -v clinfo >/dev/null 2>&1; then
  clinfo 2>&1 | grep -iE 'Platform Name|Device Name|Device Type|Device Version|Max compute units|Global memory size' | head -16
else
  warn "clinfo 不在 PATH"
fi

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
echo "修复前导出符号: $BEFORE"
echo "修复后导出符号: $AFTER"
if [ "$AFTER" = "yes" ]; then
  echo "→ libc++ 版本不匹配问题已解决，可以继续跑 GPU 基准"
else
  echo "→ 仍未解决，下一步应单独重装 libc++："
  echo "     pkg install --reinstall libc++"
  echo "   若仍无效，说明仓库中的包与该 bootstrap 存在系统性不兼容，"
  echo "   需要换成 F-Droid 版 Termux 或手动替换 bootstrap。"
fi
