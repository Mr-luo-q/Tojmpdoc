#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 验证「改用系统 libvulkan.so」能否拿到 Mali
#
# 已知事实（termux-mali-attach.sh 的结论）：
#   Termux 进程的 linker namespace 是 "(default)"，
#   permitted_paths 里没有 /vendor/lib64，因此
#     dlopen /vendor/lib64/hw/vulkan.mali.so        → 被 namespace 拒绝
#     dlopen /vendor/lib64/egl/mt6897/libGLES_mali.so → 被 namespace 拒绝
#
#   但 /system/lib64 在 permitted_paths 里，所以
#     dlopen /system/lib64/libvulkan.so             → 成功，且能取到 vkGetInstanceProcAddr
#
# 因此关键问题是：
#   链「系统的 libvulkan.so」而不是「Termux 的 libvulkan.so」，
#   枚举出来的物理设备是 Mali 还是 llvmpipe？
#
# 原理：系统的 libvulkan.so 是 Android 平台的 loader，它通过 hw_get_module()
# 加载 vulkan.mali，那条路径由 loader 自身的 namespace 处理，
# 不受调用进程 namespace 的限制。
#
# 用法：
#   bash termux-system-vulkan-test.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
LIB=/data/data/com.termux/files/usr/lib
T="$TMPDIR/vksys"
mkdir -p "$T"

cat > "$T/vk-sys.c" <<'EOF'
/* 用系统 Vulkan loader 枚举物理设备。
   与 vk-test.c 的唯一区别是链接对象：这里链 /system/lib64/libvulkan.so，
   而 vk-test.c 链的是 Termux 的 libvulkan.so（只认 Mesa 软件 ICD）。*/
#include <stdio.h>
#include <vulkan/vulkan.h>

int main(void) {
    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "vk-sys";
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
    printf("物理设备数量 -> %u (rc=%d)\n", n, r);
    if (n == 0) { printf("没有物理设备\n"); return 2; }

    VkPhysicalDevice devs[8];
    uint32_t cap = n > 8 ? 8 : n;
    vkEnumeratePhysicalDevices(inst, &cap, devs);
    for (uint32_t i = 0; i < cap; i++) {
        VkPhysicalDeviceProperties p;
        vkGetPhysicalDeviceProperties(devs[i], &p);
        printf("设备[%u] 名称=%s\n", i, p.deviceName);
        printf("        API=%u.%u.%u  驱动版本=0x%08x  类型=%d\n",
               VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion),
               VK_VERSION_PATCH(p.apiVersion), p.driverVersion, p.deviceType);
        printf("        maxComputeWorkGroupInvocations=%u  maxComputeSharedMemorySize=%u\n",
               p.limits.maxComputeWorkGroupInvocations,
               p.limits.maxComputeSharedMemorySize);
        /* 队列族数量能反映是否具备计算能力 */
        uint32_t qn = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &qn, NULL);
        printf("        队列族数=%u\n", qn);
        for (uint32_t q = 0; q < qn && q < 4; q++) {
            VkQueueFamilyProperties qp;
            uint32_t one = 1;
            vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &one, &qp);
            printf("          族[%u] flags=0x%x 队列数=%u%s\n", q, qp.queueFlags,
                   qp.queueCount,
                   (qp.queueFlags & VK_QUEUE_COMPUTE_BIT) ? "  [支持计算]" : "");
        }
    }
    vkDestroyInstance(inst, NULL);
    return 0;
}
EOF

echo "=============================================================="
echo " 编译：链接系统的 libvulkan.so"
echo "=============================================================="
# 关键：显式给出系统库的完整路径，绕过 -lvulkan 的搜索顺序
if clang -o "$T/vk-sys" "$T/vk-sys.c" \
     /system/lib64/libvulkan.so \
     -I/data/data/com.termux/files/usr/include \
     -Wl,-rpath,/system/lib64 2>&1; then
  echo "编译成功"
else
  echo "直接链 .so 失败，改用 -L/system/lib64 -lvulkan 重试"
  if clang -o "$T/vk-sys" "$T/vk-sys.c" \
       -L/system/lib64 -lvulkan \
       -I/data/data/com.termux/files/usr/include 2>&1; then
    echo "编译成功（-L 方式）"
  else
    echo "编译失败"
    exit 1
  fi
fi

echo
echo "--- 确认它链的是哪一个 libvulkan ---"
if command -v readelf >/dev/null 2>&1; then
  readelf -d "$T/vk-sys" 2>/dev/null | grep -E 'NEEDED|RUNPATH|RPATH'
fi

echo
echo "=============================================================="
echo " 运行（关键判据：设备名是 Mali 还是 llvmpipe）"
echo "=============================================================="
"$T/vk-sys" 2>&1

echo
echo "=============================================================="
echo " 对照实验：换成 Termux 的 loader"
echo "=============================================================="
# 用 LD_LIBRARY_PATH 把 Termux 的库目录放前面，
# 让 libvulkan.so 解析到 Termux 那份，应该看到 llvmpipe
LD_LIBRARY_PATH="$LIB" "$T/vk-sys" 2>&1 | head -8

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 若「系统 loader」那组显示 Mali-* 或 Mali-G615：
     → 找到正确路径了。llama.cpp 的 Vulkan 后端必须链系统 loader。
       可行做法：用 Android NDK 交叉编译 llama.cpp（NDK 天然链系统 libvulkan），
       产物推回 Termux 就能直接用 Mali，不需要 root、不需要改系统。

 若仍显示 llvmpipe 或报错：
     → 系统 loader 也没把 Mali 认出来，说明本机 Mali 只对
       Android 图形栈（SurfaceFlinger/应用）开放，
       Termux 这类进程拿不到，GPU 加速在 Termux 内到此为止。
EOF
