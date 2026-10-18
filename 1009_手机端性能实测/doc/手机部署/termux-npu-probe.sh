#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · NPU 可达性验证（Termux 身份）
#
# 这个脚本回答一个问题：在 Termux（普通应用身份、无 root）里，
# 到底能不能摸到天玑 8300 的 APU 780。
#
# 背景（由电脑侧探测已确认的事实）：
#   - /dev/apusys 权限位是 crw-rw-rw-，但 shell 身份实测不可读写
#     → 说明拦它的是 SELinux 域策略，不是文件权限
#   - NNAPI HAL 服务在跑：android.hardware.neuralnetworks-shim-service-mtk
#   - binder 上注册了三个 IDevice：
#       mtk-dsp_shim / mtk-mdla_shim / mtk-neuron_shim
#   - /vendor/lib64 下有 libneuron_runtime.so、libapu_mdw.so 等厂商库
#
# 因此本脚本按「三层递进」验证，任何一层通了都算有路：
#   L1 直连内核接口：open /dev/apusys 及 APU sysfs
#   L2 直连厂商库：dlopen libneuron_runtime.so 并调用其导出符号
#   L3 走标准 API：NNAPI（Android 的 NPU 标准入口）
#
# 用法：
#   bash termux-npu-probe.sh
#
# 全部只读，不加载任何模型、不提交任何推理任务。

set -uo pipefail

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || {
  echo "看起来不在 Termux 里"; exit 1; }

echo "=============================================================="
echo " 身份信息（对比 shell 身份的 u:r:shell:s0）"
echo "=============================================================="
echo "uid=$(id -u)  $(id)"
echo "SELinux 上下文: $(cat /proc/self/attr/current 2>/dev/null)"
echo

echo "=============================================================="
echo " L1 · 直连内核接口：APU 设备节点能否打开"
echo "=============================================================="
# 逐个节点做「存在 + 权限位 + 真实 open/read」三重判定。
# 只有真实 open 成功才算通；权限位好看不代表能用。
for n in /dev/apusys /dev/apuext /dev/apusys_apummu /dev/apusys_sapu \
         /dev/mtk_mdp /dev/dri/card0 /dev/mali0; do
  if [ ! -e "$n" ]; then echo "缺失      $n"; continue; fi
  perm=$(ls -l "$n" 2>/dev/null | awk '{print $1}')
  r="不可读"; w="不可写"
  dd if="$n" of=/dev/null bs=1 count=1 2>/dev/null && r="可读"
  [ -w "$n" ] && w="可写"
  printf '%-24s %s  %s  %s\n' "$n" "$perm" "$r" "$w"
done

echo
echo "--- APU 相关 sysfs 可读性（能读就说明驱动暴露了状态） ---"
for p in /sys/devices/platform/mdla \
         /sys/class/apusys_drv_apummu \
         /sys/devices/platform/mtk-apu-mem-code \
         /sys/devices/platform/soc/190e1000.apusys-rv; do
  if [ -e "$p" ]; then
    echo "存在: $p"
    ls "$p" 2>&1 | head -8 | sed 's/^/    /'
  else
    echo "缺失: $p"
  fi
done

echo
echo "=============================================================="
echo " L2 · 直连厂商库：libneuron_runtime.so 能否 dlopen"
echo "=============================================================="
echo "--- 库文件可读性 ---"
for so in /vendor/lib64/libneuron_runtime.so \
          /vendor/lib64/libneuron_adapter_mgvi.so \
          /vendor/lib64/libneuron_wrapper.so \
          /vendor/lib64/libneuron_platform.so \
          /vendor/lib64/libapu_mdw.so \
          /vendor/lib64/libapu_mdw_batch.so \
          /vendor/lib64/libtflite_mtk.so; do
  if [ -r "$so" ]; then
    echo "可读  $(basename $so)  $(stat -c%s "$so" 2>/dev/null) 字节"
  else
    echo "不可读  $so"
  fi
done

echo
echo "--- libneuron_runtime.so 的 DT_NEEDED（它还要拉哪些库） ---"
if [ -r /vendor/lib64/libneuron_runtime.so ] && command -v readelf >/dev/null 2>&1; then
  readelf -d /vendor/lib64/libneuron_runtime.so 2>/dev/null | grep NEEDED
else
  warn="（readelf 不可用，用 strings 兜底）"
  echo "$warn"
  strings /vendor/lib64/libneuron_runtime.so 2>/dev/null | grep -E '^lib.*\.so' | sort -u | head -20
fi

echo
echo "--- 写一个最小 dlopen 测试程序并编译运行 ---"
# 这是关键实验：如果 dlopen 成功且 dlsym 找到符号，
# 说明 SELinux 没有拦 vendor 库的加载，NPU 的软件栈在 Termux 里是可达的。
TESTDIR="$HOME/npu-test"
mkdir -p "$TESTDIR"
cat > "$TESTDIR/dlopen-neuron.c" <<'EOF'
/* 最小实验：验证 Termux 身份能否加载 MediaTek 的 NPU 运行时库。
   成功 = 软件栈可达；失败 = SELinux 或 linker namespace 拦截。 */
#include <stdio.h>
#include <dlfcn.h>

int main(void) {
    const char *libs[] = {
        "/vendor/lib64/libneuron_runtime.so",
        "/vendor/lib64/libneuron_adapter_mgvi.so",
        "/vendor/lib64/libapu_mdw.so",
        "/vendor/lib64/libtflite_mtk.so",
        NULL
    };
    for (int i = 0; libs[i]; i++) {
        void *h = dlopen(libs[i], RTLD_NOW | RTLD_GLOBAL);
        if (h) {
            printf("dlopen 成功  %s\n", libs[i]);
            /* 顺手找一个 NNAPI/neuron 风格符号，确认不是空壳 */
            const char *syms[] = {"NnAdapter_create", "neuron_runtime_init",
                                  "NeuronAdapter_create", "nn_api_create", NULL};
            for (int j = 0; syms[j]; j++) {
                void *s = dlsym(h, syms[j]);
                if (s) printf("    找到符号 %s\n", syms[j]);
            }
            dlclose(h);
        } else {
            printf("dlopen 失败  %s\n    原因: %s\n", libs[i], dlerror());
        }
    }
    return 0;
}
EOF

if command -v clang >/dev/null 2>&1; then
  info "编译 dlopen 测试程序"
  if clang -o "$TESTDIR/dlopen-neuron" "$TESTDIR/dlopen-neuron.c" -ldl 2>&1; then
    echo "--- 运行结果（这是 NPU 可达性的关键证据） ---"
    "$TESTDIR/dlopen-neuron" 2>&1
  else
    echo "编译失败，跳过"
  fi
else
  echo "clang 不可用，跳过编译实验（可 pkg install clang）"
fi

echo
echo "=============================================================="
echo " L3 · 标准 API：NNAPI（Android 的 NPU 标准入口）"
echo "=============================================================="
echo "--- HAL 服务状态 ---"
getprop init.svc.neuralnetworks_hal_service_shim_mtk
echo "--- HAL 进程 ---"
ps -A 2>/dev/null | grep -iE 'neural|neuron|apu' || echo "（ps 看不到，app 域限制）"
echo
echo "--- 关键判断点：NNAPI 对普通应用的可见性 ---"
# Android 10 起，NNAPI 收紧了应用可见性：只有系统应用或持有
# android.permission.NNAPI_ACCESS 的应用才能枚举设备。
# Termux 是普通应用，因此这里大概率拿不到设备列表。
# 这个结论必须靠「写一个 NNAPI 枚举程序」来证实，不能靠读文档下结论。
cat <<'EOF'

 背景（决定这条路能否走通的关键约束）：

   Android 10 起，NNAPI 引入了应用可见性限制。AOSP 的实现里，
   NeuralNetworks 的 DeviceManager 只在以下情况把设备暴露给调用方：
       - 调用方是系统应用
       - 调用方持有 android.permission.NNAPI_ACCESS 签名权限
       - 设备被标记为「非受限」，且调用方在设备所有人的白名单里

   Termux 是普通第三方应用，上述条件一条都不满足。
   → 预期结论：通过 NNAPI 枚举设备会得到空列表。

   这正是「接口开着但普通应用够不着」的典型形态：
   手机上确实有 NPU、HAL 在跑、binder 服务已注册，
   但 Android 框架把这道门对第三方应用关上了。

   与华为那台的区别在于：华为是 vendor 根本没暴露节点与库，
   而这台是节点与库都在、只有框架层的准入策略挡着。
EOF

echo
echo "--- 尝试用 NNAPI 的 C API 枚举设备（编译并运行） ---"
# NNAPI 的 C API 头文件在 NDK 里，Termux 不含。
# 这里手工声明最小函数原型，直接从 /system/lib64/libneuralnetworks.so 调。
cat > "$TESTDIR/nnapi-enum.c" <<'EOF'
/* 最小实验：用 NNAPI 的 C API 枚举可用加速器设备。
   手工声明原型，避免依赖 NDK 头文件。
   返回的设备数为 0 就证实了「框架层对第三方应用关闭」。 */
#include <stdio.h>
#include <stdint.h>

/* NNAPI 的最小 ABI：ANeuralNetworksDevice 是不透明指针 */
typedef struct ANeuralNetworksDevice ANeuralNetworksDevice;

extern int ANeuralNetworks_getDeviceCount(uint32_t *numDevices);
extern int ANeuralNetworks_getDevice(uint32_t devIndex, ANeuralNetworksDevice **device);
extern int ANeuralNetworksDevice_getName(const ANeuralNetworksDevice *device, const char **name);
extern int ANeuralNetworksDevice_getType(const ANeuralNetworksDevice *device, int32_t *type);
extern int ANeuralNetworksDevice_getVersion(const ANeuralNetworksDevice *device, const char **version);

int main(void) {
    uint32_t n = 0;
    int rc = ANeuralNetworks_getDeviceCount(&n);
    printf("ANeuralNetworks_getDeviceCount 返回码=%d，设备数=%u\n", rc, n);
    if (rc != 0) { printf("调用失败，说明链接或可见性层面就被拒\n"); return 0; }
    if (n == 0) {
        printf("设备数 0 —— NNAPI 对普通应用不可见，NPU 走不通这条路\n");
        return 0;
    }
    for (uint32_t i = 0; i < n; i++) {
        ANeuralNetworksDevice *d = NULL;
        if (ANeuralNetworks_getDevice(i, &d) != 0 || !d) continue;
        const char *name = NULL; const char *ver = NULL; int32_t type = -1;
        ANeuralNetworksDevice_getName(d, &name);
        ANeuralNetworksDevice_getVersion(d, &ver);
        ANeuralNetworksDevice_getType(d, &type);
        printf("设备[%u] name=%s version=%s type=%d\n", i,
               name ? name : "(null)", ver ? ver : "(null)", type);
    }
    return 0;
}
EOF

if command -v clang >/dev/null 2>&1; then
  info "编译 NNAPI 枚举程序"
  # 显式链接 /system/lib64/libneuralnetworks.so（Android 自带，不需要 NDK）
  if clang -o "$TESTDIR/nnapi-enum" "$TESTDIR/nnapi-enum.c" \
       -L/system/lib64 -lneuralnetworks -Wl,-rpath,/system/lib64 2>&1; then
    echo "--- 运行结果（NPU 可达性的最终判据） ---"
    "$TESTDIR/nnapi-enum" 2>&1
  else
    echo "编译或链接失败（多半是找不到 libneuralnetworks.so），这本身也是结论"
  fi
else
  echo "clang 不可用，跳过"
fi

echo
echo "=============================================================="
echo " 结论速查"
echo "=============================================================="
cat <<'EOF'
 三层里哪一层通了，决定 NPU 怎么用：

 L1 /dev/apusys 可 open
      → 理论上能自己写 apusys 驱动调用（需要 MediaTek 私有 ioctl 定义，实际不可行）
 L2 libneuron_runtime.so dlopen 成功
      → NPU 软件栈本身可达，但缺「模型转换 + 会话组装」的一整套 API 知识，
        属于「能摸到但没法用」的状态
 L3 NNAPI 枚举到设备
      → 唯一有实际意义的路径，可以用 LiteRT / TFLite 跑 NPU 加速的模型
      枚举为 0
      → 与预期一致：Android 框架层对第三方应用关闭了 NNAPI
        这不是本机特有问题，是所有非系统应用的共同处境
EOF
