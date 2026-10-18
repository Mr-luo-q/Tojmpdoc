#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · NNAPI 设备枚举（决定性实验，修掉上一版的链接 bug）
#
# 上一版失败原因：
#   用了 -lneuralnetworks，而 libneuralnetworks.so 不在 Termux 的库搜索路径里，
#   报 "unable to find library -lneuralnetworks"。
#   修法：绝对路径链 /system/lib64/libneuralnetworks.so。
#
# 这个实验回答的问题：
#   Termux（普通第三方应用）能否通过 Android 标准 API 看到 NPU 设备。
#
# 已知预期（AOSP 实现）：
#   Android 10 起 NeuralNetworks 的 DeviceManager 只把设备暴露给
#     1. 系统应用
#     2. 持有 android.permission.NNAPI_ACCESS 签名权限的应用
#     3. 在设备所有人白名单里的应用，且设备被标记为非受限
#   Termux 三条都不满足，所以预期设备数为 0。
#   但必须实测证实，不能靠读文档下结论。
#
# 用法：
#   bash termux-nnapi-enum.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
T="$TMPDIR/nnapi"
mkdir -p "$T"

echo "=============================================================="
echo " 第 1 步 · 确认 libneuralnetworks.so 的位置与形态"
echo "=============================================================="
ls -l /system/lib64/libneuralnetworks.so 2>&1
echo "--- SONAME 与依赖 ---"
readelf -d /system/lib64/libneuralnetworks.so 2>/dev/null | grep -E 'SONAME|NEEDED' | head -12
echo "--- 是否在 Termux 的库路径里（决定能不能用 -l） ---"
ls -l /data/data/com.termux/files/usr/lib/libneuralnetworks* 2>&1 || echo "不在 Termux 库目录，必须用绝对路径链"

echo
echo "=============================================================="
echo " 第 2 步 · 编译枚举程序（绝对路径链接）"
echo "=============================================================="
cat > "$T/nnapi.c" <<'EOF'
/* 枚举 NNAPI 加速器设备。
   手工声明函数原型，避免依赖 Android NDK 头文件。 */
#include <stdio.h>
#include <stdint.h>

typedef struct ANeuralNetworksDevice ANeuralNetworksDevice;

extern int ANeuralNetworks_getDeviceCount(uint32_t *numDevices);
extern int ANeuralNetworks_getDevice(uint32_t devIndex, ANeuralNetworksDevice **device);
extern int ANeuralNetworksDevice_getName(const ANeuralNetworksDevice *device, const char **name);
extern int ANeuralNetworksDevice_getType(const ANeuralNetworksDevice *device, int32_t *type);
extern int ANeuralNetworksDevice_getVersion(const ANeuralNetworksDevice *device, const char **version);

int main(void) {
    uint32_t n = 0;
    int rc = ANeuralNetworks_getDeviceCount(&n);
    printf("ANeuralNetworks_getDeviceCount 返回码=%d  设备数=%u\n", rc, n);
    if (rc != 0) {
        printf("调用失败 —— 连 API 层都没进去\n");
        return 0;
    }
    if (n == 0) {
        printf("设备数为 0 —— NNAPI 对普通应用不可见\n");
        printf("这正是 AOSP 的应用可见性限制在起作用\n");
        return 0;
    }
    for (uint32_t i = 0; i < n; i++) {
        ANeuralNetworksDevice *d = NULL;
        if (ANeuralNetworks_getDevice(i, &d) != 0 || !d) continue;
        const char *name = NULL, *ver = NULL;
        int32_t type = -1;
        ANeuralNetworksDevice_getName(d, &name);
        ANeuralNetworksDevice_getVersion(d, &ver);
        ANeuralNetworksDevice_getType(d, &type);
        printf("设备[%u] name=%s  version=%s  type=%d\n", i,
               name ? name : "(null)", ver ? ver : "(null)", type);
    }
    return 0;
}
EOF

if clang -o "$T/nnapi" "$T/nnapi.c" /system/lib64/libneuralnetworks.so 2>&1; then
  echo "编译成功"
  echo "--- NEEDED ---"
  readelf -d "$T/nnapi" 2>/dev/null | grep -E 'NEEDED|RUNPATH'
else
  echo "编译失败"
  echo
  echo "--- 退一步：直接 dlopen 试试（绕过链接期） ---"
  cat > "$T/nnapi-dl.c" <<'EOF'
#include <stdio.h>
#include <dlfcn.h>
#include <stdint.h>
typedef int (*fn_count)(uint32_t *);
int main(void) {
    void *h = dlopen("/system/lib64/libneuralnetworks.so", RTLD_NOW);
    if (!h) { printf("dlopen 失败: %s\n", dlerror()); return 1; }
    printf("dlopen 成功\n");
    fn_count f = (fn_count)dlsym(h, "ANeuralNetworks_getDeviceCount");
    if (!f) { printf("找不到 ANeuralNetworks_getDeviceCount\n"); return 1; }
    uint32_t n = 0;
    int rc = f(&n);
    printf("getDeviceCount -> rc=%d 设备数=%u\n", rc, n);
    return 0;
}
EOF
  if clang -o "$T/nnapi-dl" "$T/nnapi-dl.c" -ldl 2>&1; then
    "$T/nnapi-dl" 2>&1
  fi
  exit 0
fi

echo
echo "=============================================================="
echo " 第 3 步 · 运行（关键判据）"
echo "=============================================================="
"$T/nnapi" 2>&1

echo
echo "=============================================================="
echo " 第 4 步 · 对照：Termux 能否加载系统图形栈的库"
echo "=============================================================="
echo "目的：确认 namespace 里哪些路径真的能进。"
echo "已知 permitted_paths 含 /system/lib64 与 /vendor/*/app、/vendor/*/priv-app，"
echo "但明确不含 /vendor/lib64。"
for so in /system/lib64/libvulkan.so \
          /system/lib64/libneuralnetworks.so \
          /system/lib64/libandroid.so \
          /vendor/lib64/libneuron_runtime.so \
          /vendor/lib64/libOpenCL.so; do
  cat > "$T/probe.c" <<EOF
#include <stdio.h>
#include <dlfcn.h>
int main(void){ void*h=dlopen("$so",RTLD_NOW);
  printf("%-52s %s\n","$so", h?"可加载":"被拒"); if(!h) printf("    %s\n", dlerror());
  return 0; }
EOF
  clang -o "$T/probe" "$T/probe.c" -ldl 2>/dev/null && "$T/probe" 2>/dev/null
done

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 判读：
 设备数 = 0
      → NNAPI 对 Termux 关闭，NPU 在 Termux 内不可用。
        这与 GPU 的结论同源：都是 Android 的进程级隔离策略，
        一个体现在 linker namespace（库加载），一个体现在 API 可见性（服务访问）。

 设备数 > 0
      → 意外结果，说明 MediaTek 的 shim 对普通应用开放，
        此时可以继续尝试 LiteRT/TFLite 的 NPU delegate 路线。
EOF
