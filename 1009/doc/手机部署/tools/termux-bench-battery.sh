#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 验证「供电状态是否影响调频」并给出定稿配置
#
# 已实测的根因链条：
#   1. scaling_driver = mtk-cpufreq-hw，频率由 MTK 硬件调频器代理，
#      请求来自厂商的功耗/性能策略层
#   2. init.svc.mi_thermald = running，小米温控守护进程在跑
#   3. persist.sys.power.default.powermode = enhance（不是 performance）
#   4. 推理期间各核频率恒定在 1400 / 1800 MHz
#           cpu0 小核  1400 / 2200 = 64%
#           cpu4 中核  1800 / 3200 = 56%
#           cpu7 大核  1800 / 3350 = 54%
#   5. 电池温度仅 37°C，不是热降频
#
# 结论指向：系统层的调频策略把频率压在约 55~65%，
# 而「AC 供电 + 99% 电量」是厂商策略里触发压频的常见条件。
#
# 本脚本的设计要点：
#   拔线后 adb 会断开，无法再远程执行。所以脚本必须
#   自己等待拔线、自己跑完、自己把结果写盘，
#   重新插线后再用 adb 读日志。
#
# 用法：
#   1. 先在电脑上启动本脚本（此时还插着线）
#   2. 脚本提示后拔掉数据线
#   3. 等脚本跑完
#   4. 重新插线，读 ~/bench-battery.log

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
LOG="$HOME/bench-battery.log"
exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# 读供电状态。Termux 读不到 /sys/class/power_supply，改用 termux-api 或 android 层
read_power() {
  # 优先用 dumpsys（Termux 里通常可用）
  local out
  out=$(dumpsys battery 2>/dev/null)
  if [ -n "$out" ]; then
    echo "$out" | grep -E 'AC powered|USB powered|level|temperature' | tr '\n' ';'
  else
    echo "读不到供电状态"
  fi
}

sample_freq() {
  local out=""
  for c in 0 4 7; do
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    out="$out cpu$c=$(( ${v:-0} / 1000 ))MHz"
  done
  echo "$out"
}

echo "=============================================================="
echo " 阶段一 · 插线状态下的基准（对照）"
echo "=============================================================="
echo "供电: $(read_power)"
echo "频率: $(sample_freq)"
echo
echo "--- llama-bench 1.5B -t 4 ---"
llama-bench -m "$MODEL" -p 256 -n 64 -ngl 0 -t 4 -r 2 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
echo
echo "跑后频率: $(sample_freq)"

echo
echo "=============================================================="
echo " 阶段二 · 等待拔线"
echo "=============================================================="
echo "现在请拔掉数据线。脚本会每 3 秒检测一次，最多等 180 秒。"
echo "（拔线后 adb 会断，但本脚本已在手机上独立运行，不受影响）"

waited=0
UNPLUGGED=0
while [ $waited -lt 180 ]; do
  p=$(read_power)
  # 不含 "AC powered: true" 也不含 "USB powered: true" 即视为已拔线
  case "$p" in
    *"AC powered: true"*|*"USB powered: true"*) ;;
    *) UNPLUGGED=1; break ;;
  esac
  sleep 3
  waited=$((waited + 3))
done

if [ "$UNPLUGGED" = "1" ]; then
  echo "检测到已拔线（等了 ${waited} 秒）"
else
  echo "180 秒内未检测到拔线，仍按当前供电状态继续"
fi

echo "当前供电: $(read_power)"
echo "当前频率: $(sample_freq)"
echo
echo "等 20 秒让系统适应供电变化"
sleep 20
echo "适应后频率: $(sample_freq)"

echo
echo "=============================================================="
echo " 阶段三 · 拔线状态下的基准"
echo "=============================================================="
echo "--- llama-bench 1.5B -t 4 ---"
llama-bench -m "$MODEL" -p 256 -n 64 -ngl 0 -t 4 -r 2 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
echo
echo "跑后频率: $(sample_freq)"

echo
echo "--- 再测一组更长的提示词，看大负载下频率是否升上去 ---"
llama-bench -m "$MODEL" -p 2048 -n 64 -ngl 0 -t 4 -r 1 2>&1 | grep -E '^\|' | grep -vE 'model|^-+'
echo "跑后频率: $(sample_freq)"

echo
echo "=============================================================="
echo " 结论"
echo "=============================================================="
cat <<'EOF'
 对比方式：
   阶段一（插线）的 pp/tg  vs  阶段三（拔线）的 pp/tg

 若拔线后明显变快
     → 确认是供电策略触发压频。日常使用建议：不插电跑推理，
       或插电时手动开启性能模式（设置 → 电池 → 性能模式）。

 若两者一样
     → 与供电无关，是 mi_thermald 的常态策略或 MTK 调频器行为。
       此时只能从系统设置侧想办法（关闭省电模式、开启性能模式），
       或接受现状——这是厂商策略，Termux 无 root 改不了。

 若长提示词（-p 2048）时频率升到 3200 附近
     → 说明调频器按负载升频，短任务被判定为轻负载。
       日常对话属短任务，所以会一直吃到低频。
EOF

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo
echo "日志已写: $LOG"
