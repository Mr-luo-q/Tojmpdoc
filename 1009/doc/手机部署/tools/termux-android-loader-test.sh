#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 把 Android 平台 loader 与 Termux 程序接起来（决定性实验）
#
# 背景（已由 termux-system-vulkan-test.sh 证实）：
#   /system/lib64/libvulkan.so          SONAME=libvulkan.so
#       依赖 libvndksupport / libhardware / libui / libSurfaceFlingerProp 等，
#       是 Android 平台 loader，通过 hw_get_module("vulkan") 加载
#       /vendor/lib64/hw/vulkan.mali.so
#
#   Termux 的 libvulkan.so.1.4.365      SONAME=libvulkan.so.1
#       只依赖 libdl/libc，是桌面 loader，在 Android 上只找得到
#       自带的 Mesa llvmpipe（软件光栅化）
#
#   两者哈希、体积、SONAME 全不同，是两个独立实现。
#
# 上一轮实验为什么没看出差别：
#   clang 用 -L/system/lib64 -lvulkan 时，NEEDED 记录的是裸 SONAME
#   "libvulkan.so"，运行时被 DT_RUNPATH 里的 Termux 目录抢先解析，
#   所以两组实验其实都跑在 Termux loader 上。
#
# 本轮修法：
#   用绝对路径链 /system/lib64/libvulkan.so，让 ELF 的 NEEDED 直接记录完整路径。
#   同时把 ANDROID_ROOT / ANDROID_DATA 等补上，
#   因为系统 loader 靠这些变量定位 HAL 与图形环境。
#
# 用法：
#   bash termux-android-loader-test.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
T="$TMPDIR/andvk"
mkdir -p "$T"

cat > "$T/andvk.c" <<'EOF'
/* 枚举 Vulkan 物理设备，同时打印自己的 RUNPATH 解析结果，
   用来确认这次真的链上了系统 loader。
   关键：程序会打印从 /proc/self/maps 读到的 libvulkan 实际加载路径。*/
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

/* 从 /proc/self/maps 里找出实际加载的 libvulkan，验证链的是哪一份 */
static void which_libvulkan(void) {
    FILE *f = fopen("/proc/self/maps", "r");
    if (!f) return;
    char line[512];
    printf("--- 实际加载的 libvulkan ---\n");
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "libvulkan")) printf("    %s", line);
    }
    fclose(f);
}

int main(void) {
    which_libvulkan();

    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "andvk";
    app.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app;

    VkInstance inst = VK_NULL_HANDLE;
    VkResult r = vkCreateInstance(&ci, NULL, &inst);
    printf("vkCreateInstance -> %d\n", r);
    if (r != VK_SUCCESS) return 1;

    uint32_t n = 0;
    r = vkEnumeratePhysicalDevices(inst, &n, NULL);
    printf("物理设备数量 -> %u\n", n);
    if (n == 0) { printf("没有物理设备\n"); return 2; }

    VkPhysicalDevice devs[8];
    uint32_t cap = n > 8 ? 8 : n;
    vkEnumeratePhysicalDevices(inst, &cap, devs);
    for (uint32_t i = 0; i < cap; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devs[i], &p);
        printf("设备[%u] 名称=%s  API=%u.%u.%u  类型=%d\n", i, p.deviceName,
               VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion),
               VK_VERSION_PATCH(p.apiVersion), p.deviceType);
    }
    return 0;
}
EOF

echo "=============================================================="
echo " 编译：绝对路径链接系统 loader"
echo "=============================================================="
# 绝对路径是本次实验的关键，不能用 -l
if clang -o "$T/andvk" "$T/andvk.c" \
     /system/lib64/libvulkan.so \
     -I/data/data/com.termux/files/usr/include \
     -Wl,-rpath,/system/lib64 2>&1; then
  echo "编译成功"
else
  echo "编译失败"
  exit 1
fi

echo
echo "--- NEEDED 是否记录了绝对路径 ---"
readelf -d "$T/andvk" 2>/dev/null | grep -E 'NEEDED|RUNPATH'

echo
echo "=============================================================="
echo " 运行：补齐 Android 环境变量后调用"
echo "=============================================================="
# 系统 loader 依赖这些变量定位 HAL 与图形环境；
# Termux 默认不设它们，所以要显式补上。
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export ANDROID_RUNTIME_ROOT=/apex/com.android.runtime
export ANDROID_TZDATA_ROOT=/apex/com.android.tzdata
export ANDROID_ART_ROOT=/apex/com.android.art
export ANDROID_I18N_ROOT=/apex/com.android.i18n

"$T/andvk" 2>&1

echo
echo "=============================================================="
echo " 判读"
echo "=============================================================="
cat <<'EOF'
 期望看到三行关键信息：

 1. 「实际加载的 libvulkan」应指向 /system/lib64/libvulkan.so
       若仍指向 /data/data/com.termux/files/usr/lib/...，
       说明 RUNPATH 没生效，绝对路径链接没起作用。

 2. 「设备」名称应出现 Mali
       出现 Mali-*        → 找到正确路径，GPU 在 Termux 内可用
       仍是 llvmpipe      → 系统 loader 也拿不到 Mali，到此为止

 3. 若报 linker namespace 错误，且缺少的库在 /system/lib64 内
       说明该库不在 permitted_paths 覆盖范围内，
       这条路需要「用 Android NDK 编译」才能绕过
       （NDK 产物是原生 Android 可执行文件，运行在正确的 namespace 里）
EOF
