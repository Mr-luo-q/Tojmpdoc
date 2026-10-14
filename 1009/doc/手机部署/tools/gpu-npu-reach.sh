#!/system/bin/sh
#
# 手机部署 · GPU / NPU 可达性深探（第二轮）
#
# 与第一轮 gpu-npu-probe.sh 的区别：
#   第一轮问「有什么」，这一轮问「我这个身份能不能用」。
#   Android 上 SELinux 域与文件权限是两道独立的门，第一轮只看得到第二道。
#
# 探测三层：
#   L1 内核接口层   —— 设备节点能否 open、sysfs/ioctl 能否读
#   L2 用户态库层   —— 厂商 .so 落在哪些分区、哪些路径能读进来 dlopen
#   L3 框架服务层   —— NNAPI / neuralnetworks HAL 是否注册、能否被普通应用调用
#
# 用法：
#   adb shell sh /data/local/tmp/gpu-npu-reach.sh
#   adb shell run-as com.termux sh ~/gpu-npu-reach.sh    （Termux 身份下跑，对比差异）
#
# 全部是只读操作。

echo "##### [0] 我是谁 #####"
id
echo "SELinux 上下文:"
if command -v ls >/dev/null 2>&1; then
  # -Z 需要 toybox 的 ls 支持，不支持时静默跳过
  ls -Zd /data/local/tmp 2>/dev/null
fi
cat /proc/self/attr/current 2>/dev/null
echo "SELinux 模式: $(getenforce 2>/dev/null)"
echo "uid/gid 补充: $(id -u):$(id -g)"

echo
echo "##### [1] L1 内核接口层：设备节点可读可写性 #####"
# 对每个算力节点做「存在 + 权限位 + 实际能否读」三重检查
for n in /dev/mali0 /dev/dri/card0 /dev/dri/renderD128 /dev/apusys /dev/apuext \
         /dev/apusys_apummu /dev/apusys_sapu /dev/mtk_mdp /dev/adsp /dev/scp; do
  if [ -e "$n" ]; then
    perm=$(ls -l "$n" 2>/dev/null | awk '{print $1, $3, $4}')
    # 读 1 字节，成功说明至少可读；失败打印 errno 便于区分 EACCES 与 ENOENT
    if head -c 1 "$n" >/dev/null 2>&1; then rd="可读"; else rd="不可读"; fi
    if [ -w "$n" ]; then wr="可写"; else wr="不可写"; fi
    echo "$n  [$perm]  $rd  $wr"
  else
    echo "$n  不存在"
  fi
done

echo
echo "--- GPU sysfs / devfreq ---"
for d in /sys/class/devfreq/13000000.mali; do
  [ -d "$d" ] || continue
  for f in available_frequencies cur_freq governor available_governors trans_stat; do
    [ -e "$d/$f" ] && echo "$d/$f => $(cat "$d/$f" 2>&1 | head -3 | tr '\n' ' ')"
  done
done
echo "--- GPU 型号相关 sysfs ---"
ls /sys/class/misc/mali0/device/ 2>/dev/null | head -20
cat /sys/class/misc/mali0/device/gpuinfo 2>/dev/null
find /sys/devices -maxdepth 3 -name '*mali*' -o -maxdepth 3 -name '*gpu*' 2>/dev/null | head -20

echo
echo "--- APU sysfs 细节 ---"
ls -l /sys/class/apusys_drv_apummu/ 2>/dev/null
for f in /sys/class/apusys_drv_apummu/*; do
  [ -f "$f" ] || continue
  echo "$(basename $f) => $(cat "$f" 2>&1 | head -1)"
done
echo "--- APU 相关 sysfs 全览 ---"
find /sys/devices -maxdepth 4 \( -iname '*apu*' -o -iname '*mdla*' -o -iname '*neuron*' \) 2>/dev/null | head -30

echo
echo "##### [2] L2 用户态库层：厂商 .so 在哪个分区、能否读 #####"
# /vendor 与 /system/vendor 是同一份（符号链接），分开列出是为了看清挂载关系
for so in /vendor/lib64/libneuron_runtime.so \
          /vendor/lib64/libneuron_adapter_mgvi.so \
          /vendor/lib64/libneuron_platform.so \
          /vendor/lib64/libneuron_wrapper.so \
          /vendor/lib64/libapu_mdw.so \
          /vendor/lib64/libapu_mdw_batch.so \
          /vendor/lib64/libapudcutils.so \
          /vendor/lib64/libtflite_mtk.so \
          /vendor/lib64/libmdla_ut.so \
          /vendor/lib64/libOpenCL.so \
          /vendor/lib64/libGLES_mali.so \
          /vendor/lib64/egl/mt6897/libGLES_mali.so \
          /vendor/lib64/hw/vulkan.mali.so \
          /system/lib64/libvulkan.so; do
  if [ -e "$so" ]; then
    sz=$(stat -c%s "$so" 2>/dev/null)
    if head -c 4 "$so" >/dev/null 2>&1; then rd="可读"; else rd="不可读"; fi
    echo "$so  ${sz} 字节  $rd"
  else
    echo "$so  不存在"
  fi
done

echo
echo "--- 这些 .so 导出了什么符号（判断能否直接 dlopen 调用） ---"
for so in /vendor/lib64/libneuron_adapter_mgvi.so /vendor/lib64/libneuron_runtime.so; do
  [ -e "$so" ] || continue
  echo "== $so =="
  # 没有 readelf 时退化成 grep 二进制字符串
  if command -v readelf >/dev/null 2>&1; then
    readelf -d "$so" 2>/dev/null | grep -E 'NEEDED|SONAME' | head -20
  else
    strings "$so" 2>/dev/null | grep -E '^(neuron_|Neuron|nn_|NNAPI)' | sort -u | head -30
  fi
done

echo
echo "--- libneuron_runtime 依赖链（看它要谁来喂数据） ---"
for so in /vendor/lib64/libneuron_runtime.so /vendor/lib64/libneuron_adapter_mgvi.so /vendor/lib64/libapu_mdw.so; do
  [ -e "$so" ] || continue
  echo "== $so 的 DT_NEEDED =="
  strings "$so" 2>/dev/null | grep -E '^lib[a-zA-Z0-9_]+\.so' | sort -u | head -20
done

echo
echo "--- 找 neuron / mdla 的固件与配置 ---"
find /vendor/firmware /vendor/etc -maxdepth 3 \( -iname '*neuron*' -o -iname '*mdla*' -o -iname '*apu*' -o -iname '*dla*' \) 2>/dev/null
ls /vendor/etc/vintf/manifest/ 2>/dev/null | grep -i neural
echo "--- VINTF 里 neuralnetworks 的声明 ---"
find /vendor/etc/vintf /vendor/etc -maxdepth 2 -name '*.xml' 2>/dev/null | head -5
grep -rl 'neuralnetworks' /vendor/etc/vintf/ 2>/dev/null

echo
echo "##### [3] L3 框架服务层：NNAPI / HAL #####"
echo "--- HAL 服务是否注册 ---"
# Android 8+ 用 lshal 列 HAL；不可用时退回 init 属性
if command -v lshal >/dev/null 2>&1; then
  lshal 2>/dev/null | grep -i neural
else
  echo "（无 lshal，改用属性与进程）"
  getprop | grep -i neural
  ps -A 2>/dev/null | grep -i neural
fi
echo "--- HAL 进程 ---"
ps -A 2>/dev/null | grep -iE 'neural|neuron|apu|mdla'
echo "--- HAL 的 .so 在哪（能不能读到就决定普通应用能否间接调用） ---"
find /vendor/lib64/hw /vendor/lib64 -maxdepth 1 -iname '*neural*' -o -maxdepth 1 -iname '*neuron*' 2>/dev/null
ls -l /vendor/lib64/hw/ 2>/dev/null | grep -iE 'neural|neuron|nn'
echo "--- nnapi_powerhal.json 内容 ---"
cat /vendor/etc/nnapi_powerhal.json 2>/dev/null
echo "--- 调试属性：TFLite 走哪个 NNAPI 设备 ---"
getprop debug.mtk_tflite.target_nnapi
echo "--- app 域能否看到 NNAPI 的 binder 服务 ---"
if command -v service >/dev/null 2>&1; then
  service list 2>/dev/null | grep -i neural
fi

echo
echo "##### [4] 直接加载测试 #####"
echo "--- 尝试用 linker 直接 dlopen 厂商 AI 库（看 SELinux 拦不拦） ---"
# 没有编译器的环境下，用系统自带的 toybox 或 linker 做最小验证
if [ -x /system/bin/linker64 ]; then
  for so in /vendor/lib64/libneuron_adapter_mgvi.so /vendor/lib64/hw/vulkan.mali.so; do
    echo "== $so =="
    # 用一个不存在的可执行名调用 linker 会打印它解析到的库，能暴露 dlopen 层面的拒绝
    /system/bin/linker64 "$so" 2>&1 | head -5
  done
fi
echo "--- 检查 /apex 里的 NEURAL 相关（mainline 模块可能有独立实现） ---"
ls /apex/ 2>/dev/null
find /apex -maxdepth 3 -iname '*neural*' 2>/dev/null | head -10

echo
echo "##### 深探结束 #####"
