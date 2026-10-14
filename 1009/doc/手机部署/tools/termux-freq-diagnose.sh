#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 追查「推理时 CPU 被锁在 60% 频率」的原因
#
# 已实测的关键现象：
#   推理进行中，各核频率恒定不动，且都只有约 60% 上限：
#       cpu0 小核  1400 / 2200 MHz
#       cpu4 中核  2000 / 3200 MHz
#       cpu7 大核  2000 / 3350 MHz
#   电池温度仅 37.4°C，不是热降频。
#   可用 governor 含 performance，但当前 governor 读不到（需 root）。
#
# 要排查的方向（本脚本只做只读探测，不改任何系统设置）：
#   方向 1  厂商限频策略 / 省电模式是否开启
#   方向 2  MTK 的 sugov_ext 与 per-mode 频率表
#   方向 3  供电状态：USB 供电时厂商常主动压频
#   方向 4  系统属性里与性能模式/限频相关的开关
#   方向 5  devfreq / 功耗管理节点暴露的状态
#
# 用法：
#   bash termux-freq-diagnose.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

exec > "$HOME/freq-diagnose.log" 2>&1

echo "=============================================================="
echo " 方向 1 · 电量与供电状态（USB 供电常触发压频）"
echo "=============================================================="
dumpsys battery 2>/dev/null | grep -E 'level|status|powered|temperature|health|Charge|charg' || echo "dumpsys battery 不可读"

echo
echo "--- 从 sysfs 读充电状态 ---"
for p in /sys/class/power_supply/battery/status \
         /sys/class/power_supply/battery/current_now \
         /sys/class/power_supply/battery/voltage_now \
         /sys/class/power_supply/usb/online \
         /sys/class/power_supply/ac/online \
         /sys/class/power_supply/battery/temp; do
  if [ -r "$p" ]; then
    echo "  $(basename "$p") = $(cat "$p" 2>/dev/null)"
  fi
done

echo
echo "=============================================================="
echo " 方向 2 · 系统属性里的性能/省电相关开关"
echo "=============================================================="
getprop 2>/dev/null | grep -iE 'power|perf|boost|thermal|throttl|limit|saving|powersave|sched|freq' \
  | grep -viE 'log.tag|persist.log' | head -40

echo
echo "=============================================================="
echo " 方向 3 · MTK sugov_ext 与频率表"
echo "=============================================================="
for c in 0 4 7; do
  base="/sys/devices/system/cpu/cpu$c/cpufreq"
  echo "--- cpu$c ---"
  for f in scaling_available_frequencies scaling_available_governors \
           scaling_driver scaling_cur_freq cpuinfo_cur_freq \
           scaling_boost_frequencies stats/time_in_state; do
    if [ -r "$base/$f" ]; then
      v=$(cat "$base/$f" 2>/dev/null | head -3 | tr '\n' ' ')
      echo "  $f = $v"
    fi
  done
  # 有些机型的 governor 在当前策略目录下
  for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor; do
    [ -r "$g" ] && echo "  $(dirname "$g" | xargs basename)/scaling_governor = $(cat "$g" 2>/dev/null)"
  done 2>/dev/null | sort -u | head -6
done

echo
echo "--- 是否有 per-mode 频率表（MTK 常见） ---"
find /sys/devices/system/cpu/cpufreq -maxdepth 2 -name '*freq*' 2>/dev/null | head -20
ls /sys/kernel/ 2>/dev/null | grep -iE 'power|perf|mtk|sched' | head -10

echo
echo "=============================================================="
echo " 方向 4 · 功耗管理节点（devfreq / 温度 / cooling）"
echo "=============================================================="
echo "--- devfreq 设备 ---"
ls /sys/class/devfreq/ 2>/dev/null | head -15
for d in /sys/class/devfreq/*/; do
  n=$(basename "$d")
  cur=$(cat "$d/cur_freq" 2>/dev/null)
  mx=$(cat "$d/max_freq" 2>/dev/null)
  gv=$(cat "$d/governor" 2>/dev/null)
  [ -n "$cur$mx$gv" ] && echo "  $n: cur=$cur max=$mx gov=$gv"
done

echo
echo "--- thermal cooling devices（看有没有被触发） ---"
for c in /sys/class/thermal/cooling_device*/; do
  n=$(basename "$c")
  t=$(cat "$c/type" 2>/dev/null)
  s=$(cat "$c/cur_state" 2>/dev/null)
  m=$(cat "$c/max_state" 2>/dev/null)
  [ -n "$t" ] && echo "  $n: type=$t state=$s/$m"
done

echo
echo "--- thermal zones（能读多少读多少） ---"
for z in /sys/class/thermal/thermal_zone*/; do
  n=$(basename "$z")
  t=$(cat "$z/type" 2>/dev/null)
  v=$(cat "$z/temp" 2>/dev/null)
  if [ -n "$t" ]; then
    echo "  $n: $t = $v"
  fi
done | head -25

echo
echo "=============================================================="
echo " 方向 5 · cpuidle 与调度器状态"
echo "=============================================================="
echo "--- cpuidle 各核状态名 ---"
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name 2>/dev/null | tr '\n' ' '
echo
echo "--- sched 相关可读节点 ---"
ls /proc/sys/kernel/ 2>/dev/null | grep -iE 'sched|perf' | head -10

echo
echo "=============================================================="
echo " 方向 6 · 尝试判断能否影响调频（只读探测可行性，不实际修改）"
echo "=============================================================="
for f in /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor \
         /sys/devices/system/cpu/cpufreq/policy7/scaling_governor; do
  if [ -e "$f" ]; then
    echo "  $f 权限: $(ls -l "$f" 2>/dev/null | awk '{print $1, $3, $4}')"
    if [ -w "$f" ]; then
      echo "    → 可写！可以尝试切 performance governor"
    else
      echo "    → 不可写（需要 root）"
    fi
  fi
done

echo
echo "=============================================================="
echo " 小结"
echo "=============================================================="
cat <<'EOF'
 可能的原因与对应处置：

 原因甲  USB 供电触发的厂商压频
         手机接在电脑 USB 上时，厂商常主动限制 SoC 功耗。
         验证：拔掉数据线，用手机自己的电池跑一次基准对比。
         处置：拔线后重测（但拔线会失去 adb，需要用终端注入执行）。

 原因乙  省电模式/均衡模式
         验证：设置 → 电池 → 看是否处于「省电模式」或「均衡」。
         处置：切到性能模式，或关闭省电。

 原因丙  MTK sugov_ext 的负载判断
         llama.cpp 的负载特征是「短时爆发 + 频繁访存等待」，
         scheduler 可能据此判定为轻负载而不升频。
         验证：换更大的 -p（如 2048）看频率是否上升。
         处置：基本无解（需 root 改 governor）。

 原因丁  系统级限频（温度或厂商策略）
         验证：看 thermal cooling_device 的 cur_state 是否 > 0。
         处置：散热或等待降温。

 最值得先试的是原因甲——拔线重测，成本最低，且这个假设
 与「电池仅 37.4°C 却被压到 60% 频率」的现象最吻合。
EOF
