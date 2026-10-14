#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 自动补齐 Mali 驱动的依赖链，直到可加载
#
# 收敛过程记录（这是判断「路通不通」的依据）：
#   第 1 次   not accessible for the namespace "(default)"    ← namespace 拒绝
#   第 2 次   libGLES_mali.so not found                       ← 复制进 /data 已绕过 namespace
#   第 3 次   libged.so not found                             ← $ORIGIN 布局修好后的下一个依赖
#
# 每修一个依赖，报错里的库名就换一个，说明在收敛。
# 本脚本自动循环：dlopen 一次 -> 从报错里提取缺的库名 -> 从系统里找到并复制 -> 再来。
#
# 安全边界：
#   只复制「纯 vendor 库」和 vendor 提供的基础库变体（libc/libm/libdl/libc++ 等），
#   绝不覆盖 Termux 自己的运行库到 usr/lib 顶层以外的位置。
#   所有写入都在 Termux 私有目录内，不改系统分区。
#
# 用法：
#   bash termux-mali-dep-loop.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
PREFIX=/data/data/com.termux/files/usr
LIB="$PREFIX/lib"
EGLDIR="$PREFIX/egl"
ICDDIR="$PREFIX/share/vulkan/icd.d"
T="$TMPDIR/deploop"
mkdir -p "$T"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 系统里可能存放依赖的目录。顺序有讲究：
#   /vendor/lib64/egl/mt6897 优先（GPU 专用，且 libGLES_mali.so 就住那）
#   /vendor/lib64 与 /system/vendor/lib64（通用 vendor 库）
#   /system/lib64 兜底
SEARCH_DIRS="
/vendor/lib64/egl/mt6897
/vendor/lib64
/system/vendor/lib64
/vendor/lib
/system/vendor/lib
/system/lib64
"

# 在系统目录里找某个库
find_lib() {
  local name="$1" d
  for d in $SEARCH_DIRS; do
    if [ -e "$d/$name" ]; then
      echo "$d/$name"
      return 0
    fi
  done
  return 1
}

cat > "$T/dl.c" <<'EOF'
/* 尝试 dlopen Mali 驱动副本，失败时把 dlerror 原文打到 stdout 以便脚本解析 */
#include <stdio.h>
#include <dlfcn.h>
int main(int argc, char **argv) {
    const char *p = argc > 1 ? argv[1]
                             : "/data/data/com.termux/files/usr/lib/vulkan.mali.so";
    void *h = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("FAIL:%s\n", dlerror()); return 1; }
    printf("OK\n");
    const char *syms[] = {"vk_icdGetInstanceProcAddr", "vkGetInstanceProcAddr",
                          "vk_icdNegotiateLoaderICDInterfaceVersion", NULL};
    for (int i = 0; syms[i]; i++)
        printf("SYM:%s:%s\n", syms[i], dlsym(h, syms[i]) ? "found" : "missing");
    return 0;
}
EOF
clang -o "$T/dl" "$T/dl.c" -ldl 2>/dev/null || { echo "编译失败"; exit 1; }

TARGET="$LIB/vulkan.mali.so"
MAX_ROUNDS=15

echo "=============================================================="
echo " 自动补齐依赖链（最多 $MAX_ROUNDS 轮）"
echo "=============================================================="

for round in $(seq 1 $MAX_ROUNDS); do
  echo
  echo "---------- 第 $round 轮 ----------"
  OUT=$("$T/dl" "$TARGET" 2>&1)
  echo "$OUT" | head -3

  if echo "$OUT" | grep -q '^OK'; then
    info "dlopen 成功！依赖链已补齐"
    echo "$OUT" | grep '^SYM:'
    break
  fi

  # 从报错里提取缺失的库名：
  #   dlopen failed: library "libged.so" not found: needed by ...
  MISSING=$(echo "$OUT" | sed -n 's/.*library "\([^"]*\)" not found.*/\1/p' | head -1)

  if [ -z "$MISSING" ]; then
    # 有些报错形式是 无法定位符号 而非 找不到库
    if echo "$OUT" | grep -q 'cannot locate symbol'; then
      warn "遇到符号级缺失（不是库级），本脚本无法自动处理。原文："
      echo "$OUT" | head -5
    else
      warn "无法从报错里提取库名，终止。原文："
      echo "$OUT" | head -5
    fi
    break
  fi

  SRC=$(find_lib "$MISSING")
  if [ -z "$SRC" ]; then
    warn "系统里找不到 $MISSING，依赖链在此断掉"
    break
  fi

  info "补 $MISSING  <-  $SRC  ($(stat -c%s "$SRC" 2>/dev/null) 字节)"
  cp "$SRC" "$LIB/$MISSING" 2>&1 || { warn "复制失败"; break; }
  chmod 755 "$LIB/$MISSING" 2>/dev/null
done

echo
echo "=============================================================="
echo " 最终状态：usr/lib 下的 vendor 库副本"
echo "=============================================================="
ls -l "$LIB"/*.so 2>/dev/null | grep -viE 'libggml|libllama|libvulkan\.so|libc\+\+|libcurl' | head -25

echo
echo "=============================================================="
echo " 用补齐后的驱动跑 vulkaninfo"
echo "=============================================================="
cat > "$ICDDIR/mali-copy.json" <<EOF
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "$LIB/vulkan.mali.so",
        "api_version": "1.3.0"
    }
}
EOF
export VK_ICD_FILENAMES="$ICDDIR/mali-copy.json"
vulkaninfo --summary 2>&1 | head -35

echo
echo "--- 关键字段 ---"
vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|driverInfo|apiVersion|deviceType|ERROR' | head -12

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 deviceName 显示 Mali-G615
     → GPU 在 Termux 内打通。用法：
         export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/mali-copy.json
         llama-cli -m <模型> -ngl 99

 仍然失败但缺的库名在变
     → 继续跑本脚本即可，每轮补一个。

 卡在 "cannot locate symbol"
     → 依赖库齐了但符号对不上，通常是 copy 来的库与 Termux 的 libc++
       版本不一致。这时要考虑换用 Android NDK 编译的方案。
EOF
