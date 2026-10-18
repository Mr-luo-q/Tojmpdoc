#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 绕 namespace 的第二次尝试：按 $ORIGIN/../egl 摆目录
#
# 上一次失败的原因（重要，bionic 的真实行为）：
#   复制到 usr/lib/ 后 dlopen 报错变了性质——
#       之前：not accessible for the namespace "(default)"     ← namespace 拒绝
#       现在：library "libGLES_mali.so" not found               ← 找不到文件
#   说明「复制进 /data」这一步已经成功绕过 namespace，剩下的是目录布局问题。
#
#   Mali 驱动自己有 RUNPATH=$ORIGIN/../egl，靠它定位 libGLES_mali.so。
#   驱动原来在 /vendor/lib64/hw/mt6897/，$ORIGIN/../egl 正好是 /vendor/lib64/egl/。
#   我们把两个文件平铺进 usr/lib/，$ORIGIN/../egl 就指向了不存在的 usr/egl/。
#
# 修法：把 libGLES_mali.so 放到 usr/egl/，与 usr/lib/ 平级，
#       正好满足 $ORIGIN/../egl 的相对关系。
#
#   Termux 目录布局            对应关系
#   usr/lib/vulkan.mali.so     $ORIGIN
#   usr/egl/libGLES_mali.so    $ORIGIN/../egl
#
# 用法：
#   bash termux-mali-origin-fix.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
PREFIX=/data/data/com.termux/files/usr
LIB="$PREFIX/lib"
EGLDIR="$PREFIX/egl"
ICDDIR="$PREFIX/share/vulkan/icd.d"
T="$TMPDIR/originfix"
mkdir -p "$T"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 第 1 步 · 建立 \$ORIGIN/../egl 需要的目录并放入驱动"
echo "=============================================================="
mkdir -p "$EGLDIR"
# 若 usr/lib/ 下已有平铺的副本，直接移动过去，避免重复占 46 MB
if [ -f "$LIB/libGLES_mali.so" ]; then
  info "把 usr/lib/libGLES_mali.so 移到 usr/egl/（符合 \$ORIGIN/../egl）"
  mv "$LIB/libGLES_mali.so" "$EGLDIR/libGLES_mali.so" 2>&1 || \
    cp "$LIB/libGLES_mali.so" "$EGLDIR/libGLES_mali.so"
elif [ -r /vendor/lib64/egl/mt6897/libGLES_mali.so ]; then
  info "从 vendor 分区复制 libGLES_mali.so 到 usr/egl/"
  cp /vendor/lib64/egl/mt6897/libGLES_mali.so "$EGLDIR/libGLES_mali.so"
fi
chmod 755 "$EGLDIR/libGLES_mali.so" 2>/dev/null

echo "--- 目录布局确认 ---"
echo "\$ORIGIN 位置:      $LIB/vulkan.mali.so"
echo "\$ORIGIN/../egl 位置: $EGLDIR/libGLES_mali.so"
ls -l "$LIB/vulkan.mali.so" "$EGLDIR/libGLES_mali.so" 2>&1

echo
echo "--- 用 realpath 验证相对关系确实成立 ---"
# 从 vulkan.mali.so 的目录出发，拼出 ../egl/libGLES_mali.so
ORIGIN_DIR=$(dirname "$LIB/vulkan.mali.so")
RESOLVED="$ORIGIN_DIR/../egl/libGLES_mali.so"
if [ -e "$RESOLVED" ]; then
  echo "解析成功: $RESOLVED"
  echo "实际文件: $(readlink -f "$RESOLVED" 2>/dev/null)"
else
  echo "解析失败: $RESOLVED 不存在"
fi

echo
echo "=============================================================="
echo " 第 2 步 · 再测 dlopen 副本"
echo "=============================================================="
cat > "$T/dl.c" <<'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    const char *p = "/data/data/com.termux/files/usr/lib/vulkan.mali.so";
    void *h = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("dlopen 失败:\n  %s\n", dlerror()); return 1; }
    printf("dlopen 成功 —— Mali 驱动副本已可加载\n");
    const char *syms[] = {"vk_icdGetInstanceProcAddr", "vkGetInstanceProcAddr",
                          "vk_icdNegotiateLoaderICDInterfaceVersion",
                          "vk_icdGetPhysicalDeviceProcAddr", NULL};
    for (int i = 0; syms[i]; i++)
        printf("   %-46s %s\n", syms[i], dlsym(h, syms[i]) ? "找到" : "未找到");
    return 0;
}
EOF
if clang -o "$T/dl" "$T/dl.c" -ldl 2>&1; then
  "$T/dl" 2>&1
fi

echo
echo "=============================================================="
echo " 第 3 步 · vulkaninfo 用这个 ICD 枚举"
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
echo "VK_ICD_FILENAMES=$VK_ICD_FILENAMES"
echo
echo "--- vulkaninfo --summary ---"
vulkaninfo --summary 2>&1 | head -40

echo
echo "--- 只看设备名与驱动 ---"
vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|driverInfo|apiVersion|ERROR' | head -12

echo
echo "=============================================================="
echo " 第 4 步 · 若 Mali 出现，跑 llama.cpp Vulkan 后端"
echo "=============================================================="
export VK_ICD_FILENAMES="$ICDDIR/mali-copy.json"
if command -v llama-cli >/dev/null 2>&1; then
  echo "--- llama-cli --list-devices ---"
  llama-cli --list-devices 2>&1 | head -15
else
  echo "llama-cli 不在 PATH"
fi

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 三种可能的结果与含义：

 A. dlopen 成功 + vulkaninfo 显示 Mali-G615
     → GPU 在 Termux 内打通。
       之后所有 Vulkan 用法都要带：
           export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/mali-copy.json

 B. dlopen 成功但 vulkaninfo 仍失败
     → 驱动能加载，但 ICD 接口协商不过。
       看 vulkaninfo 的完整报错定位（常见是接口版本或 loader 版本不匹配）。

 C. dlopen 仍失败，报错的库名换成了别的
     → 继续按同样的办法补齐那个库。
       每修一个依赖，报错里的库名就会变一次，这是收敛的信号。
EOF
