#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 用「复制驱动进 /data」绕过 linker namespace
#
# 思路来源：
#   已证实的拦截机制是 Termux 进程的 linker namespace 不授予 /vendor/lib64。
#   但 namespace 规则是**按路径前缀**判断的，而 /data 在 permitted_paths 里。
#   所以如果把 Mali 驱动复制进 Termux 自己的 usr/lib/，再让 loader 从那里加载，
#   就绕过了路径限制。
#
# 为什么这个思路对 Mali 成立：
#   Mali 的 vulkan.mali.so 依赖只有五个——
#       libGLES_mali.so / libc++.so / libc.so / libm.so / libdl.so
#   其中 libGLES_mali.so 同目录就有，其余四个 Termux 都有。
#   它是纯 GPU 驱动，不需要 HIDL/AIDL 服务转发。
#
#   反例是系统的 libvulkan.so，它依赖 libvndksupport.so / libui.so /
#   libhidlbase.so 等 27 个库并要通过 hw_get_module 走 vendor 服务，
#   复制过来未必能工作。所以本脚本不去复制 loader，只复制驱动，
#   让 Termux 自己的 loader 按 ICD json 直接加载驱动副本。
#
# 用法：
#   bash termux-copy-mali-driver.sh
#
# 全部操作只写在 Termux 私有目录，不改系统任何东西。

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
LIB="$HOME/../usr/lib"
ICDDIR="$HOME/../usr/share/vulkan/icd.d"
T="$TMPDIR/copymali"
mkdir -p "$T"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

echo "=============================================================="
echo " 第 1 步 · 确认 Termux 的 Vulkan loader 是否还在"
echo "=============================================================="
ls -l "$LIB"/libvulkan* 2>&1
echo
if [ ! -e "$LIB/libvulkan.so.1" ] && [ ! -e "$LIB/libvulkan.so" ]; then
  warn "libvulkan 不在了，先重装 vulkan-loader-generic 与 vulkan-icd"
  pkg install -y vulkan-loader-generic vulkan-icd vulkan-tools 2>&1 | tail -8
  echo
  ls -l "$LIB"/libvulkan* 2>&1
fi

echo
echo "=============================================================="
echo " 第 2 步 · 复制 Mali 驱动与它的依赖进 Termux 私有目录"
echo "=============================================================="
# 源：vendor 分区的 Mali 驱动（读得到，只是不能 dlopen）
SRC_VK="/vendor/lib64/hw/mt6897/vulkan.mali.so"
SRC_GLES="/vendor/lib64/egl/mt6897/libGLES_mali.so"

info "复制前先确认可读与体积"
for f in "$SRC_VK" "$SRC_GLES"; do
  if [ -r "$f" ]; then
    echo "  可读  $f  $(stat -c%s "$f" 2>/dev/null) 字节"
  else
    echo "  不可读 $f   <-- 若这里失败，整个思路不成立"
  fi
done

info "复制 vulkan.mali.so → $LIB/"
cp "$SRC_VK" "$LIB/vulkan.mali.so" 2>&1 && echo "  完成" || echo "  失败"

info "复制 libGLES_mali.so → $LIB/"
# 46 MB，需要一点时间
cp "$SRC_GLES" "$LIB/libGLES_mali.so" 2>&1 && echo "  完成" || echo "  失败"

echo
echo "--- 复制结果与权限 ---"
ls -l "$LIB/vulkan.mali.so" "$LIB/libGLES_mali.so" 2>&1
chmod 755 "$LIB/vulkan.mali.so" "$LIB/libGLES_mali.so" 2>/dev/null

echo
echo "=============================================================="
echo " 第 3 步 · 验证副本本身的依赖能否被解析"
echo "=============================================================="
echo "--- 副本的 NEEDED ---"
readelf -d "$LIB/vulkan.mali.so" 2>/dev/null | grep -E 'NEEDED|RPATH|RUNPATH'
echo
echo "--- 逐个确认依赖在 Termux 里存在 ---"
for dep in libGLES_mali.so libc++.so libc.so libm.so libdl.so; do
  found=""
  for d in "$LIB" /system/lib64 "$HOME/../usr/lib"; do
    [ -e "$d/$dep" ] && found="$d/$dep" && break
  done
  if [ -n "$found" ]; then
    echo "  找到  $dep  ->  $found"
  else
    echo "  缺失  $dep   <-- 会导致加载失败"
  fi
done

echo
echo "--- 直接 dlopen 副本（这是关键测试） ---"
cat > "$T/dl.c" <<'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    const char *p = "/data/data/com.termux/files/usr/lib/vulkan.mali.so";
    void *h = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("dlopen 失败:\n  %s\n", dlerror()); return 1; }
    printf("dlopen 成功 —— namespace 限制被绕过了\n");
    const char *syms[] = {"vk_icdGetInstanceProcAddr", "vkGetInstanceProcAddr",
                          "vk_icdNegotiateLoaderICDInterfaceVersion", NULL};
    for (int i = 0; syms[i]; i++)
        printf("   %-46s %s\n", syms[i], dlsym(h, syms[i]) ? "找到" : "未找到");
    return 0;
}
EOF
if clang -o "$T/dl" "$T/dl.c" -ldl 2>&1; then
  "$T/dl" 2>&1
else
  echo "编译失败"
fi

echo
echo "=============================================================="
echo " 第 4 步 · 写 ICD json 指向副本，重跑 vulkaninfo"
echo "=============================================================="
mkdir -p "$ICDDIR"
# 先把自带的 lvp（llvmpipe）ICD 挪开，避免它抢先被选中
if [ -f "$ICDDIR/lvp_icd.aarch64.json" ]; then
  mv "$ICDDIR/lvp_icd.aarch64.json" "$ICDDIR/lvp_icd.aarch64.json.bak" 2>/dev/null
  echo "已把 llvmpipe 的 ICD 改名为 .bak，它不会再被选中"
fi

cat > "$ICDDIR/mali-copy.json" <<EOF
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "$LIB/vulkan.mali.so",
        "api_version": "1.3.0"
    }
}
EOF
echo "已写入 $ICDDIR/mali-copy.json"
cat "$ICDDIR/mali-copy.json"

echo
echo "--- 用这个 ICD 跑 vulkaninfo ---"
export VK_ICD_FILENAMES="$ICDDIR/mali-copy.json"
vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|driverInfo|apiVersion|deviceType|GPU id|ERROR|error|WARNING|failed' | head -20

echo
echo "--- 不指定 ICD，看默认会选哪个 ---"
unset VK_ICD_FILENAMES
vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|apiVersion|failed|ERROR' | head -10

echo
echo "=============================================================="
echo " 第 5 步 · 若副本可用，测 llama.cpp 的 Vulkan 后端"
echo "=============================================================="
if command -v llama-cli >/dev/null 2>&1; then
  export VK_ICD_FILENAMES="$ICDDIR/mali-copy.json"
  echo "--- llama-cli --list-devices ---"
  llama-cli --list-devices 2>&1 | head -15
  echo
  echo "--- 直接跑 Vulkan 后端的最小验证 ---"
  MODEL=""
  for c in "$HOME/models"/*.gguf; do [ -f "$c" ] && MODEL="$c" && break; done
  if [ -n "$MODEL" ]; then
    echo "用模型: $MODEL"
    llama-bench -m "$MODEL" -p 128 -n 32 -ngl 99 2>&1 | tail -20
  else
    echo "~/models 下没有模型，跳过"
  fi
else
  echo "llama-cli 不在 PATH"
fi

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 第 3 步 dlopen 成功 + 第 4 步 vulkaninfo 显示 Mali
     → GPU 通了。之后所有 llama.cpp Vulkan 用法都要带：
           export VK_ICD_FILENAMES=$HOME/../usr/share/vulkan/icd.d/mali-copy.json

 第 3 步成功但 vulkaninfo 仍显示 llvmpipe 或报错
     → 驱动能加载，但 loader 与它的 ICD 接口协商有问题。
       这时看 vulkaninfo 的完整报错，通常是 ICD 接口版本或
       vk_icdNegotiateLoaderICDInterfaceVersion 的问题。

 第 3 步就失败（dlopen 报错）
     → 副本仍被 namespace 拒，或依赖没解析到。
       看报错里提到哪个库名，逐个补齐。
EOF
