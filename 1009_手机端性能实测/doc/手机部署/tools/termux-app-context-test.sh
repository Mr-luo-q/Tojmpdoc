#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 在「真正的 App 进程内」复测 GPU / NPU 可达性
#
# 为什么要重测：
#   之前的全部实验都是用 `adb shell run-as com.termux` 跑的。
#   run-as 只切换 UID，namespace 仍然是 shell 的 "(default)"，
#   其 permitted_paths 不含 /vendor/lib64，所以 vendor 库一律被拒。
#
#   但用图标启动的 Termux 跑在 classloader-namespace 里，
#   该 namespace 由 Android 的 libnativeloader 按 APK 的 nativeLibraryDir
#   与 ABI 配置，**包含 /vendor/lib64 与 /system/vendor/lib64**——
#   不然任何 APK 都无法加载自己的 vendor 依赖。
#
#   因此「run-as 下被拒」不能推出「Termux App 内也被拒」。
#   本脚本必须在 App 进程内执行才有意义。
#
# 触发方式（二选一）：
#   A. Termux 的 RunCommandService
#        adb shell am startservice --user 0 \
#          -n com.termux/com.termux.app.RunCommandService \
#          -a com.termux.RUN_COMMAND \
#          --es com.termux.RUN_COMMAND_PATH <脚本路径> \
#          --ez com.termux.RUN_COMMAND_BACKGROUND true
#      需要 ~/.termux/termux.properties 里有 allow-external-apps=true
#   B. 直接在 Termux 终端里粘贴执行
#
# 用法：
#   bash termux-app-context-test.sh        （在 App 进程内跑）

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

echo "=============================================================="
echo " 第 0 步 · 确认这次跑在哪个 namespace 里"
echo "=============================================================="
echo "进程 PID: $$"
echo "自身可执行文件: $(readlink -f /proc/$$/exe 2>/dev/null)"
# 从 maps 里读 namespace 线索：App 进程会加载 libnativeloader
echo "--- 加载了哪些 native loader ---"
grep -E 'nativeloader|libandroid\.so|linker64' /proc/self/maps 2>/dev/null | head -5
echo
echo "--- 关键判据：permitted_paths 是否含 /vendor/lib64 ---"
# 故意 dlopen 一个 vendor 库，看报错里带的 namespace 描述
T="$TMPDIR/appctx"
mkdir -p "$T"
cat > "$T/ns.c" <<'EOF'
#include <stdio.h>
#include <dlfcn.h>
int main(void) {
    /* 只打印失败的 namespace 描述，不关心成功与否 */
    const char *p = "/vendor/lib64/hw/vulkan.mali.so";
    void *h = dlopen(p, RTLD_NOW);
    if (h) { printf("%s 可加载\n", p); return 0; }
    printf("%s 被拒\n%s\n", p, dlerror());
    return 0;
}
EOF
if command -v clang >/dev/null 2>&1; then
  clang -o "$T/ns" "$T/ns.c" -ldl 2>/dev/null && "$T/ns" 2>&1 | head -4
fi

echo
echo "=============================================================="
echo " 第 1 步 · GPU：vendor 库与 Mali 驱动可达性"
echo "=============================================================="
for so in /vendor/lib64/hw/vulkan.mali.so \
          /vendor/lib64/egl/mt6897/libGLES_mali.so \
          /vendor/lib64/libOpenCL.so; do
  cat > "$T/t.c" <<EOF
#include <stdio.h>
#include <dlfcn.h>
int main(void){void*h=dlopen("$so",RTLD_NOW);
  printf("%-48s %s\n","$so",h?"可加载":"被拒");return 0;}
EOF
  clang -o "$T/t" "$T/t.c" -ldl 2>/dev/null && "$T/t" 2>&1
done

echo
echo "=============================================================="
echo " 第 2 步 · GPU：Vulkan 枚举（用的是哪个 loader，枚举到什么设备）"
echo "=============================================================="
if [ -x "$TMPDIR/vksys/vk-sys" ]; then
  echo "--- 系统 loader ---"
  "$TMPDIR/vksys/vk-sys" 2>&1 | head -12
else
  echo "（之前的 vk-sys 测试程序不在，重新编译）"
  cat > "$T/vk.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>
int main(void) {
    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app;
    VkInstance inst = NULL;
    if (vkCreateInstance(&ci, NULL, &inst) != VK_SUCCESS) { printf("建实例失败\n"); return 1; }
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, NULL);
    printf("物理设备数=%u\n", n);
    VkPhysicalDevice d[8]; uint32_t c = n>8?8:n;
    vkEnumeratePhysicalDevices(inst, &c, d);
    for (uint32_t i=0;i<c;i++){ VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(d[i],&p);
      printf("  [%u] %s  API=%u.%u  类型=%d\n", i, p.deviceName,
        VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion), p.deviceType); }
    return 0;
}
EOF
  clang -o "$T/vk" "$T/vk.c" -lvulkan 2>/dev/null && "$T/vk" 2>&1
  echo "--- 实际加载的 libvulkan ---"
  clang -o "$T/vk2" "$T/vk.c" -lvulkan 2>/dev/null && "$T/vk2" >/dev/null 2>&1
  grep -i vulkan /proc/self/maps 2>/dev/null | head -3
fi

echo
echo "=============================================================="
echo " 第 3 步 · NPU：vendor 库 + NNAPI 设备"
echo "=============================================================="
for so in /vendor/lib64/libneuron_runtime.so \
          /vendor/lib64/libapu_mdw.so \
          /vendor/lib64/libneuron_adapter_mgvi.so; do
  cat > "$T/t.c" <<EOF
#include <stdio.h>
#include <dlfcn.h>
int main(void){void*h=dlopen("$so",RTLD_NOW);
  printf("%-48s %s\n","$so",h?"可加载":"被拒");
  if(!h) printf("      %s\n", dlerror());
  return 0;}
EOF
  clang -o "$T/t" "$T/t.c" -ldl 2>/dev/null && "$T/t" 2>&1 | head -2
done

echo
echo "--- NNAPI 设备枚举（App 进程内） ---"
if [ -x "$TMPDIR/nnapi2/enum" ]; then
  "$TMPDIR/nnapi2/enum" 2>&1
fi

echo
echo "--- APU 设备节点（App 进程内） ---"
for n in /dev/apusys /dev/apuext /dev/apusys_sapu /dev/apusys_apummu /dev/mali0; do
  if [ -e "$n" ]; then
    r="不可读"; w="不可写"
    dd if="$n" of=/dev/null bs=1 count=1 2>/dev/null && r="可读"
    [ -w "$n" ] && w="可写"
    printf '%-24s %s %s\n' "$n" "$r" "$w"
  else
    printf '%-24s 不可见\n' "$n"
  fi
done

echo
echo "=============================================================="
echo " 结论判读"
echo "=============================================================="
cat <<'EOF'
 本次结果与 run-as 下的结果对比：

 若 vendor 库在 App 进程里「可加载」
     → 之前所有「被拒」的结论都是 run-as 环境造成的假象，
       GPU 与 NPU 的直连路径在 Termux App 内其实可用。
       下一步：装 llama-cpp-backend-vulkan，看 llama-cli --list-devices 是否列出 Mali。

 若仍「被拒」且 namespace 描述里没有 /vendor/lib64
     → 结论成立：Termux 拿不到 vendor 库（无论哪种启动方式）。
       这时只剩「用 Android NDK 编原生 APK」一条路。

 若 /dev/apusys 变为可读写
     → APU 直连在 App 进程里可行，NPU 多一条路。
EOF
