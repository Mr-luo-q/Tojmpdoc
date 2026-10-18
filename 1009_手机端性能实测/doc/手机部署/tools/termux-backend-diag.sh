#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · llama.cpp 后端加载诊断
#
# 要回答的问题：
#   llama-cli --list-devices 输出 "Available devices: (none)"，
#   连 CPU 后端都没认到。但 libggml-cpu.so 与 libggml-vulkan.so 都已安装。
#
# 可能的原因，逐条验证：
#   a) ggml 后端是运行时动态注册的，需要 libggml-*.so 能被 dlopen
#   b) 后端注册依赖 ggml_backend_load_all()，它会扫特定目录
#   c) libggml-vulkan.so 自身链接失败（缺 ICD loader 或 libc++ 符号）
#   d) Vulkan loader 找不到 ICD（Android 用 /vendor/lib64/hw/vulkan.mali.so）
#   e) Termux 的 GGML_BACKEND_PATH 环境变量未设
#
# 用法：
#   bash termux-backend-diag.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

LIB=/data/data/com.termux/files/usr/lib
T="$TMPDIR/diag"
mkdir -p "$T"

echo "=============================================================="
echo " 第 1 步 · 装了哪些 ggml 后端库"
echo "=============================================================="
ls -l "$LIB"/libggml*.so 2>/dev/null
echo
echo "--- 各后端的 SONAME 与依赖 ---"
for so in "$LIB"/libggml-vulkan.so "$LIB"/libggml-cpu.so "$LIB"/libggml.so; do
  [ -e "$so" ] || continue
  echo "== $(basename "$so")"
  if command -v readelf >/dev/null 2>&1; then
    readelf -d "$so" 2>/dev/null | grep -E 'SONAME|NEEDED|RPATH|RUNPATH'
  else
    echo "   (readelf 不可用)"
  fi
done

echo
echo "=============================================================="
echo " 第 2 步 · 直接用 linker 加载 libggml-vulkan.so（看缺什么符号）"
echo "=============================================================="
# linker64 加载 .so 时会打印它解析不到的符号或库
for so in "$LIB"/libggml-vulkan.so "$LIB"/libggml-cpu.so; do
  [ -e "$so" ] || continue
  echo "== $(basename "$so")"
  /system/bin/linker64 "$so" 2>&1 | head -6 | sed 's/^/   /'
  echo
done

echo
echo "=============================================================="
echo " 第 3 步 · Vulkan loader 与 ICD 的状态"
echo "=============================================================="
echo "--- 系统里的 ICD 描述文件（Android 走 hw 目录）---"
ls -l /vendor/lib64/hw/vulkan.*.so 2>/dev/null
echo
echo "--- 有没有 ICD json（桌面 Linux 靠这个，Android 不一定有）---"
ls -l /vendor/etc/vulkan/ /system/etc/vulkan/ 2>/dev/null
echo
echo "--- Termux 提供的 vulkan loader 包 ---"
dpkg -l 2>/dev/null | grep -iE 'vulkan|shaderc|glslang' | awk '{print $2, $3}'
echo
echo "--- Termux 的 libvulkan.so 是哪个 ---"
ls -l "$LIB"/libvulkan* 2>/dev/null
echo
echo "--- 这个 libvulkan 能否加载 ---"
for v in "$LIB"/libvulkan.so.1 "$LIB"/libvulkan.so; do
  [ -e "$v" ] || continue
  echo "== $v"
  /system/bin/linker64 "$v" 2>&1 | head -4 | sed 's/^/   /'
done

echo
echo "=============================================================="
echo " 第 4 步 · ggml 的动态后端加载机制"
echo "=============================================================="
echo "--- ggml 会扫描的目录（编译期写死的默认值）---"
strings "$LIB"/libggml-base.so 2>/dev/null | grep -iE 'ggml.*backend|\.so$|GGML_BACKEND' | head -20
echo
echo "--- 相关环境变量 ---"
env | grep -iE 'GGML|VULKAN|LD_LIBRARY|ADSP' || echo "(无)"
echo
echo "--- ggml-backend 的注册函数符号 ---"
for so in "$LIB"/libggml-base.so "$LIB"/libggml.so; do
  [ -e "$so" ] || continue
  echo "== $(basename "$so")"
  if command -v nm >/dev/null 2>&1; then
    nm -D --defined-only "$so" 2>/dev/null | grep -iE 'backend_load|backend_reg' | head -10
  else
    strings "$so" 2>/dev/null | grep -iE '^ggml_backend_(load|reg)' | head -10
  fi
done

echo
echo "=============================================================="
echo " 第 5 步 · 手动指定后端路径再试一次"
echo "=============================================================="
# ggml 支持 GGML_BACKEND_PATH 指定搜索目录
export GGML_BACKEND_PATH="$LIB"
echo "GGML_BACKEND_PATH=$GGML_BACKEND_PATH"
echo "--- llama-cli --list-devices ---"
llama-cli --list-devices 2>&1 | head -20
echo
echo "--- 带 --device 参数显式指定（新版 llama.cpp 支持）---"
llama-cli --list-devices --device Vulkan0 2>&1 | head -10

echo
echo "=============================================================="
echo " 第 6 步 · 直接测 Vulkan 设备枚举（绕过 ggml）"
echo "=============================================================="
# 写一个最小 Vulkan 程序：只调 vkCreateInstance + vkEnumeratePhysicalDevices
# 这是判断「Vulkan 本身能不能用」与「ggml 集成有没有问题」的分界线
cat > "$T/vk-test.c" <<'EOF'
/* 最小 Vulkan 探测：只枚举物理设备并打印名称。
   用来区分「Vulkan 驱动不可用」与「ggml 没接上 Vulkan」。 */
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

int main(void) {
    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "vk-test";
    app.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app;

    VkInstance inst = VK_NULL_HANDLE;
    VkResult r = vkCreateInstance(&ci, NULL, &inst);
    printf("vkCreateInstance -> %d (%s)\n", r, r == VK_SUCCESS ? "OK" : "FAIL");
    if (r != VK_SUCCESS) return 1;

    uint32_t n = 0;
    r = vkEnumeratePhysicalDevices(inst, &n, NULL);
    printf("vkEnumeratePhysicalDevices 数量 -> %u (rc=%d)\n", n, r);
    if (n == 0) { printf("没有物理设备 —— Vulkan 驱动层没通\n"); return 2; }

    VkPhysicalDevice devs[8];
    if (n > 8) n = 8;
    vkEnumeratePhysicalDevices(inst, &n, devs);

    for (uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devs[i], &p);
        printf("设备[%u] 名称=%s  API=%u.%u.%u  驱动版本=0x%08x\n", i,
               p.deviceName,
               VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion),
               VK_VERSION_PATCH(p.apiVersion), p.driverVersion);
    }
    vkDestroyInstance(inst, NULL);
    return 0;
}
EOF

# 优先用 termux 的 vulkan 头文件和加载器编译
if command -v clang >/dev/null 2>&1; then
  if [ -f /data/data/com.termux/files/usr/include/vulkan/vulkan.h ]; then
    echo "编译中（链接 Termux 的 libvulkan）..."
    if clang -o "$T/vk-test" "$T/vk-test.c" -lvulkan 2>&1; then
      echo "--- 运行结果 ---"
      "$T/vk-test" 2>&1
    else
      echo "编译失败"
    fi
  else
    echo "缺少 Vulkan 头文件，需要: pkg install vulkan-headers"
    echo "当前 include 目录:"
    ls /data/data/com.termux/files/usr/include/ 2>/dev/null | grep -i vulkan || echo "  (无 vulkan 目录)"
  fi
else
  echo "clang 不可用"
fi

echo
echo "=============================================================="
echo " 诊断结束"
echo "=============================================================="
