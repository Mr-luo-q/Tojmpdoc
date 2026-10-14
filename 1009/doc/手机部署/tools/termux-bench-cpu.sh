#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · CPU 推理基准（红米 K70E / 天玑 8300-Ultra）
#
# 目的：
#   拿到这台机器在 CPU 后端上的真实推理速度，作为后续任何 GPU/NPU 尝试的对照基线。
#
# 设计成与上一台华为 Pura 70 可比的形式：
#   同样的 llama-bench、同样的 -p 512 -n 128、同样的 -t 8
#   这样两次的数据能直接放在一张表里比对。
#
# 测两个模型：
#   qwen2.5-1.5b-instruct-q4_k_m   质量优先，1.07 GB
#   Qwen3-0.6B-Q4_K_M             速度优先，0.38 GB
#
# 每组测两个指标：
#   pp512   prompt processing，提示词处理，计算受限
#   tg128   text generation，逐 token 生成，访存受限
#
# 说明手机热的现实：
#   上一台华为热降频严重（SoC 30°C 时 22.62 t/s，热保护触发后掉到 5.56 t/s）。
#   本脚本在每组之前记录一次温度（能读到的话），便于事后判断数据是否被降频污染。
#
# 用法：
#   bash termux-bench-cpu.sh            跑全部
#   bash termux-bench-cpu.sh 06         只跑 0.6B
#   bash termux-bench-cpu.sh 15         只跑 1.5B

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
WHICH="${1:-all}"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# 长任务期间拉住唤醒锁，避免灭屏后 CPU 被限频，污染基准
if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# 读一次 SoC 温度。不同机型节点名不一样，逐个试。
read_temp() {
  for p in /sys/class/thermal/thermal_zone0/temp \
           /sys/class/thermal/thermal_zone1/temp \
           /sys/devices/virtual/thermal/thermal_zone0/temp; do
    if [ -r "$p" ]; then
      v=$(cat "$p" 2>/dev/null)
      case "$v" in
        ''|*[!0-9]*) continue ;;
      esac
      # 多数机型是毫摄氏度
      echo "$((v / 1000))"
      return 0
    fi
  done
  echo "n/a"
}

# 读一遍各核当前频率上限，用来判断是否已被热限流
read_cpu_max() {
  out=""
  for c in 0 4 7; do
    f="/sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq"
    if [ -r "$f" ]; then
      v=$(cat "$f" 2>/dev/null)
      out="$out cpu$c=$((${v:-0} / 1000))MHz"
    fi
  done
  echo "$out"
}

echo "=============================================================="
echo " 设备信息"
echo "=============================================================="
echo "SoC:        $(getprop ro.soc.model 2>/dev/null)"
echo "内核:       $(uname -r)"
echo "逻辑核数:   $(nproc)"
echo "llama-cli:  $(command -v llama-cli || echo '不在 PATH')"
if command -v llama-cli >/dev/null 2>&1; then
  llama-cli --version 2>&1 | head -2
fi
echo
echo "起始温度:   $(read_temp) °C"
echo "起始频率上限: $(read_cpu_max)"
echo

bench_one() {
  local tag="$1" model="$2"
  if [ ! -f "$model" ]; then
    warn "$tag 模型不存在: $model"
    return
  fi
  echo "=============================================================="
  echo " $tag"
  echo " 模型: $(basename "$model")  ($(stat -c%s "$model") 字节)"
  echo "=============================================================="
  echo "跑前温度: $(read_temp) °C   频率上限: $(read_cpu_max)"
  echo
  # -r 3 表示每项重复 3 次，llama-bench 会给出平均值与标准差
  llama-bench -m "$model" -p 512 -n 128 -t 8 -r 3 2>&1
  echo
  echo "跑后温度: $(read_temp) °C   频率上限: $(read_cpu_max)"
  echo
}

case "$WHICH" in
  06)  bench_one "Qwen3-0.6B（速度优先）" "$M06" ;;
  15)  bench_one "Qwen2.5-1.5B（质量优先）" "$M15" ;;
  all)
    bench_one "Qwen2.5-1.5B（质量优先）" "$M15"
    echo
    echo "（两组之间不做冷却，便于观察热降频的真实影响）"
    echo
    bench_one "Qwen3-0.6B（速度优先）" "$M06"
    ;;
  *) echo "用法: bash termux-bench-cpu.sh [all|15|06]"; exit 1 ;;
esac

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi

echo "=============================================================="
echo " 读表说明"
echo "=============================================================="
cat <<'EOF'
 llama-bench 输出两行，各行字段含义：

   model      模型文件名（含量化类型）
   size       模型体积
   params     参数量
   backend    CPU
   ngl        卸载到 GPU 的层数（CPU 测试恒为 0）
   test       测试类型
                pp512  = 处理 512 token 的提示词，计算受限
                tg128  = 生成 128 token，访存受限
   t/s        每秒 token 数，这是核心指标
   ±          标准差。数值大说明测量被干扰（后台应用、降频）

 判读要点：
   1. 上一台华为 Pura 70（Kirin 9010）的对照值：
          Qwen2.5-1.5B  tg 18.35~22.62 t/s   pp 49.4~54.3 t/s
          Qwen3-0.6B    tg 49.42~49.65 t/s   pp 132.3~133.7 t/s
   2. 若本机 tg 低于上述值，先怀疑热降频——
      看「跑后温度」与「频率上限」是否有明显变化。
   3. 标准差明显大于均值的 10%，说明这轮数据不可靠，应静置降温后重测。
EOF
