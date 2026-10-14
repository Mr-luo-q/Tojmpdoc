#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 让 llama.cpp 用上 Mali 而不是 llvmpipe
#
# 已确认的两个问题：
#   问题 A  llama-cli --list-devices 输出 (none)，连 CPU 后端都没认到
#           → 后端 .so 在，但 ggml 的动态加载没找到它们
#   问题 B  Vulkan 枚举到的是 llvmpipe（Mesa 软件光栅化器），不是 Mali
#           → Termux 的 libvulkan.so 只认自己的 Mesa ICD，
#             不去加载 Android 系统的 /vendor/lib64/hw/vulkan.mali.so
#
# 本脚本按顺序试多种把 Mali 接上来的办法，哪个成功用哪个。
#
# 用法：
#   bash termux-mali-attach.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
LIB=/data/data/com.termux/files/usr/lib
T="$TMPDIR/mali"
mkdir -p "$T"

echo "=============================================================="
echo " 问题 A · 修 ggml 后端加载"
echo "=============================================================="
echo "--- 先看 llama-cli 到底在哪里找后端 ---"
strings "$LIB"/libllama.so 2>/dev/null | grep -iE 'libggml-(cpu|vulkan|blas)\.so|GGML_BACKEND_PATH|ggml_backend_load' | sort -u | head -20

echo
echo "--- 试法 A1: GGML_BACKEND_PATH 指向具体的 .so 文件 ---"
# 之前给的是目录，dlopen 会报 Is a directory；这次给文件列表
for combo in \
  "$LIB/libggml-cpu.so" \
  "$LIB/libggml-vulkan.so:$LIB/libggml-cpu.so" \
  "$LIB/libggml-vulkan.so"; do
  echo "== GGML_BACKEND_PATH=$combo"
  GGML_BACKEND_PATH="$combo" llama-cli --list-devices 2>&1 | head -8 | sed 's/^/   /'
  echo
done

echo "--- 试法 A2: 用 LD_PRELOAD 直接塞进后端库 ---"
echo "== LD_PRELOAD=libggml-vulkan.so:libggml-cpu.so"
LD_PRELOAD="$LIB/libggml-vulkan.so:$LIB/libggml-cpu.so" llama-cli --list-devices 2>&1 | head -10 | sed 's/^/   /'
echo

echo "--- 试法 A3: 从 Termux 包里看后端应有的加载方式（读包内文件清单） ---"
dpkg -L llama-cpp-backend-vulkan 2>/dev/null
echo
echo "--- llama-cpp 包自带的文件（找 backend 目录） ---"
dpkg -L llama-cpp 2>/dev/null | grep -iE 'backend|\.so|bin/' | head -20

echo
echo "=============================================================="
echo " 问题 B · 把 Mali 接到 Termux 的 Vulkan loader 上"
echo "=============================================================="
echo "--- 系统 Mali 驱动的真实路径与类型 ---"
ls -lL /vendor/lib64/hw/vulkan.mali.so 2>&1
echo
echo "--- Mali 驱动导出的 ICD 入口点（决定能否当 ICD 用）---"
if command -v nm >/dev/null 2>&1; then
  nm -D --defined-only /vendor/lib64/hw/vulkan.mali.so 2>/dev/null | grep -iE 'vk_icd|vkGetInstanceProcAddr|vkCreateInstance' | head -10
else
  strings /vendor/lib64/hw/vulkan.mali.so 2>/dev/null | grep -E '^vk_icd|^vkGetInstanceProcAddr' | head -10
fi

echo
echo "--- Termux loader 会去哪里找 ICD ---"
strings "$LIB"/libvulkan.so.1.4.365 2>/dev/null | grep -iE 'icd\.d|vulkan/icd|share/vulkan|VK_ICD' | sort -u | head -10
echo
echo "--- 现有的 ICD json ---"
find "$HOME/../usr/share" -iname '*icd*' 2>/dev/null
ls -l "$HOME/../usr/share/vulkan/icd.d/" 2>/dev/null

echo
echo "--- 试法 B1: 把系统 Mali 驱动路径写成一个 ICD json 喂给 Termux loader ---"
ICDDIR="$HOME/../usr/share/vulkan/icd.d"
mkdir -p "$ICDDIR" 2>/dev/null
cat > "$ICDDIR/mali.json" <<'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/vendor/lib64/hw/vulkan.mali.so",
        "api_version": "1.3.0"
    }
}
EOF
echo "已写入 $ICDDIR/mali.json"
if [ -f "$T/vk-test" ]; then
  echo "== 带这个 ICD 重跑 vk-test"
  VK_ICD_FILENAMES="$ICDDIR/mali.json" "$T/vk-test" 2>&1 | sed 's/^/   /'
  echo
  echo "== 默认（不指定 ICD）对照"
  "$T/vk-test" 2>&1 | sed 's/^/   /'
fi

echo
echo "--- 试法 B2: 让 libggml-vulkan.so 链接到系统的 libvulkan.so ---"
# 系统的 libvulkan.so 在 /system/lib64，看 Termux 进程能否加载它
echo "== 系统 libvulkan.so 能否被 Termux 进程 dlopen"
cat > "$T/dlopen-vk.c" <<'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    const char *cands[] = {
        "/system/lib64/libvulkan.so",
        "libvulkan.so",
        NULL
    };
    for (int i = 0; cands[i]; i++) {
        void *h = dlopen(cands[i], RTLD_NOW | RTLD_GLOBAL);
        printf("dlopen(%s) -> %s\n", cands[i], h ? "成功" : dlerror());
        if (h) {
            void *s = dlsym(h, "vkGetInstanceProcAddr");
            printf("    vkGetInstanceProcAddr -> %s\n", s ? "找到" : "未找到");
            dlclose(h);
        }
    }
    return 0;
}
EOF
if clang -o "$T/dlopen-vk" "$T/dlopen-vk.c" -ldl 2>&1; then
  "$T/dlopen-vk" 2>&1 | sed 's/^/   /'
fi

echo
echo "--- 试法 B3: 直接把 Android 的 libvulkan.so 拷来用（实测可行性）---"
# 如果 Termux 进程能 dlopen /system/lib64/libvulkan.so，
# 那就可以让 libggml-vulkan.so 的 DT_NEEDED 解析到它，
# 办法是在 LD_LIBRARY_PATH 里把 /system/lib64 放前面
echo "== LD_LIBRARY_PATH=/system/lib64 下重跑 vk-test"
LD_LIBRARY_PATH="/system/lib64:$LIB" "$T/vk-test" 2>&1 | sed 's/^/   /'

echo
echo "=============================================================="
echo " 试法 C · 直接用 Android NDK 风格的加载方式验证厂商驱动"
echo "=============================================================="
echo "--- 写一个直接 dlopen Mali HAL 并调 vk_icdGetInstanceProcAddr 的程序 ---"
cat > "$T/mali-direct.c" <<'EOF'
/* 绕过所有 loader，直接加载厂商 Vulkan HAL 并调用其 ICD 入口点。
   这是判断「Mali 驱动本身能不能被这个进程用」的最直接实验：
   如果这一步成功，说明缺的只是一个正确的 loader，而不是驱动不可达。 */
#include <stdio.h>
#include <dlfcn.h>

typedef void (*PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(void *instance, const char *pName);
typedef PFN_vkVoidFunction (*PFN_vk_icdGetInstanceProcAddr)(void *instance, const char *pName);

int main(void) {
    const char *paths[] = {
        "/vendor/lib64/hw/vulkan.mali.so",
        "/vendor/lib64/egl/mt6897/libGLES_mali.so",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        printf("=== %s\n", paths[i]);
        void *h = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (!h) {
            printf("    dlopen 失败: %s\n", dlerror());
            continue;
        }
        printf("    dlopen 成功\n");
        const char *entries[] = {
            "vk_icdGetInstanceProcAddr",
            "vkGetInstanceProcAddr",
            "vk_icdNegotiateLoaderICDInterfaceVersion",
            NULL
        };
        for (int j = 0; entries[j]; j++) {
            void *s = dlsym(h, entries[j]);
            printf("    %-45s %s\n", entries[j], s ? "找到" : "未找到");
            /* 对 ICD 入口点再进一步：问它要 vkCreateInstance 和 vkEnumeratePhysicalDevices */
            if (s && j == 0) {
                PFN_vk_icdGetInstanceProcAddr gipa = (PFN_vk_icdGetInstanceProcAddr)s;
                PFN_vkVoidFunction f1 = gipa(NULL, "vkCreateInstance");
                PFN_vkVoidFunction f2 = gipa(NULL, "vkEnumerateInstanceVersion");
                PFN_vkVoidFunction f3 = gipa(NULL, "vkEnumeratePhysicalDevices");
                printf("        -> vkCreateInstance            %s\n", f1 ? "可用" : "不可用");
                printf("        -> vkEnumerateInstanceVersion  %s\n", f2 ? "可用" : "不可用");
                printf("        -> vkEnumeratePhysicalDevices  %s\n", f3 ? "可用" : "不可用");
            }
        }
        dlclose(h);
    }
    return 0;
}
EOF
if clang -o "$T/mali-direct" "$T/mali-direct.c" -ldl 2>&1; then
  "$T/mali-direct" 2>&1 | sed 's/^/   /'
fi

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 判读方式：

 试法 B1（ICD json 指向 Mali）成功 → 最省事，Termux 的 loader 直接能用 Mali
 试法 C（直接 dlopen Mali HAL）成功但 B1 失败
     → 驱动本身可用，缺的是 loader 的正确对接方式，
       这时正确的做法是「用 Android NDK 编译 llama.cpp 的 Vulkan 后端」，
       让它在编译期就链接 /system/lib64/libvulkan.so（系统的那个），
       而不是 Termux 那个只看 Mesa ICD 的桌面版 loader
 全部失败
     → Mali 对 Termux 进程确实不可达，GPU 这条路在 Termux 内走不通，
       只能退回到「自己编一个 Android 原生 app」的方案
EOF
