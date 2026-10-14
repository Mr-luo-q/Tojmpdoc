#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · NNAPI 设备枚举（用 APEX 里的真实路径）
#
# 路径修正记录：
#   第一版试 /system/lib64/libneuralnetworks.so      → 不存在
#   第二版试 /apex/... 顶层目录                       → Permission denied
#   实际位置：/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so
#             （来自 /system/apex/com.android.neuralnetworks.capex 这个 APEX 模块）
#
# 本脚本要判定两件事：
#   1. Termux 进程能不能 dlopen 到 APEX 里的 libneuralnetworks.so
#   2. 如果能，NNAPI 会不会把 NPU 设备暴露给 Termux（预期为 0，需实测）
#
# 用法：
#   bash termux-nnapi-enum2.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp
T="$TMPDIR/nnapi2"
mkdir -p "$T"

NNLIB="/apex/com.android.neuralnetworks/lib64/libneuralnetworks.so"

echo "=============================================================="
echo " 第 1 步 · 逐层探测 APEX 路径的可达性"
echo "=============================================================="
# 从顶层往上逐段测，定位权限断在哪一层
for p in /apex \
         /apex/com.android.neuralnetworks \
         /apex/com.android.neuralnetworks/lib64 \
         "$NNLIB"; do
  if [ -e "$p" ]; then
    if ls -ld "$p" >/dev/null 2>&1; then
      echo "可访问   $p  $(ls -ld "$p" 2>/dev/null | awk '{print $1}')"
    else
      echo "存在但被拒 $p"
    fi
  else
    echo "不可见   $p"
  fi
done

echo
echo "=============================================================="
echo " 第 2 步 · 直接 dlopen 这个 APEX 里的 NNAPI 库"
echo "=============================================================="
cat > "$T/dl.c" <<EOF
#include <stdio.h>
#include <dlfcn.h>
#include <stdint.h>
typedef int (*fn_count)(uint32_t *);
int main(void) {
    void *h = dlopen("$NNLIB", RTLD_NOW);
    if (!h) { printf("dlopen 失败: %s\n", dlerror()); return 1; }
    printf("dlopen 成功\n");
    fn_count f = (fn_count)dlsym(h, "ANeuralNetworks_getDeviceCount");
    if (!f) { printf("找不到 ANeuralNetworks_getDeviceCount\n"); return 1; }
    uint32_t n = 0;
    int rc = f(&n);
    printf("ANeuralNetworks_getDeviceCount -> rc=%d  设备数=%u\n", rc, n);
    if (n == 0)
        printf("判据: NNAPI 对 Termux 不可见，NPU 无标准入口\n");
    else
        printf("判据: NNAPI 可见 %u 个设备，NPU 这条路有戏\n", n);
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
echo " 第 3 步 · 若 dlopen 成功，再枚举并打印设备详情"
echo "=============================================================="
cat > "$T/enum.c" <<EOF
#include <stdio.h>
#include <stdint.h>
#include <dlfcn.h>
typedef struct ANeuralNetworksDevice ANeuralNetworksDevice;
int main(void) {
    void *h = dlopen("$NNLIB", RTLD_NOW);
    if (!h) { printf("库不可加载\n"); return 1; }
    int (*getCount)(uint32_t*) = dlsym(h, "ANeuralNetworks_getDeviceCount");
    int (*getDev)(uint32_t, ANeuralNetworksDevice**) = dlsym(h, "ANeuralNetworks_getDevice");
    int (*getName)(const ANeuralNetworksDevice*, const char**) = dlsym(h, "ANeuralNetworksDevice_getName");
    int (*getType)(const ANeuralNetworksDevice*, int32_t*) = dlsym(h, "ANeuralNetworksDevice_getType");
    int (*getVer)(const ANeuralNetworksDevice*, const char**) = dlsym(h, "ANeuralNetworksDevice_getVersion");
    if (!getCount || !getDev) { printf("符号缺失\n"); return 1; }
    uint32_t n = 0;
    if (getCount(&n) != 0) { printf("getDeviceCount 调用失败\n"); return 1; }
    printf("设备数 = %u\n", n);
    for (uint32_t i = 0; i < n; i++) {
        ANeuralNetworksDevice *d = NULL;
        if (getDev(i, &d) != 0 || !d) continue;
        const char *nm = NULL, *vr = NULL; int32_t tp = -1;
        if (getName) getName(d, &nm);
        if (getVer)  getVer(d, &vr);
        if (getType) getType(d, &tp);
        printf("  [%u] name=%s  version=%s  type=%d\n", i,
               nm ? nm : "?", vr ? vr : "?", tp);
    }
    return 0;
}
EOF
if clang -o "$T/enum" "$T/enum.c" -ldl 2>&1; then
  "$T/enum" 2>&1
else
  echo "编译失败"
fi

echo
echo "=============================================================="
echo " 第 4 步 · 顺带确认 vendor 库在 Termux 下的可达性（与 GPU 同源问题）"
echo "=============================================================="
for so in /vendor/lib64/libneuron_runtime.so \
          /vendor/lib64/libapu_mdw.so \
          /vendor/lib64/hw/vulkan.mali.so; do
  cat > "$T/p.c" <<EOF
#include <stdio.h>
#include <dlfcn.h>
int main(void){ void*h=dlopen("$so",RTLD_NOW);
  printf("%-46s %s\n","$so", h?"可加载":"被拒");
  return 0; }
EOF
  clang -o "$T/p" "$T/p.c" -ldl 2>/dev/null && "$T/p" 2>/dev/null
done

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 本机 NPU 的三点事实（已实测）：
   1. APU 驱动与 HAL 都在跑：/dev 下有 apusys 系列节点，
      android.hardware.neuralnetworks-shim-service-mtk 进程活着，
      binder 上注册了 mtk-dsp_shim / mtk-mdla_shim / mtk-neuron_shim
   2. 跑在 runas_app 域里的 Termux 看不到 /dev/apusys，
      /sys/devices/platform/mdla 等 sysfs 也是 Permission denied
   3. /vendor/lib64 下的 neuron/apu/mali 库全部被 linker namespace 拒绝

 因此 NPU 与 GPU 的结论同源：
   硬件与驱动齐备，被 Android 的进程级隔离挡在 Termux 之外。
   这不是「接口没暴露」，而是「暴露了但不给第三方进程」。
EOF
