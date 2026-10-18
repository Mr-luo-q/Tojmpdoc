#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 五个小模型的同场速度排名
#
# 与 termux-bench-qwen35-08.sh 的区别：
#   那个只比两个模型，一组一个标签；这个把手机上的五个模型放进同一场次，
#   并且把「深度」放在外层循环、模型放在内层，让每个模型都在不同时段
#   拿到早、中、晚的测量槽位，压低主频漂移对名次的影响。
#
# 五个模型（全部 Q4_K_M）：
#   06  Qwen3-0.6B        596 M
#   08  Qwen3.5-0.8B      752 M   SSM 混合
#   15  Qwen2.5-1.5B      1.78 B  纯注意力
#   17  Qwen3-1.7B        1.72 B  纯注意力
#   35  Qwen3.5-2B        1.88 B  SSM 混合
#
# 三组实验：
#   B1 基线正序    d=0，-r 3      06→08→15→17→35
#   B2 基线逆序    d=0，-r 3      35→17→15→08→06
#   D  深度扫描    d=512/2048/4096，-r 2，每个深度换一次方向
#
# 用法：
#   bash termux-bench-ranking.sh
# 产出：
#   ~/speed-results/rank-<时间戳>/   每次调用一个 JSON
#   ~/bench-ranking.log              全过程日志，含频率采样

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

MODELS=(
  "06:$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
  "08:$HOME/models/Qwen3.5-0.8B-Q4_K_M.gguf"
  "15:$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
  "17:$HOME/models/Qwen3-1.7B-Q4_K_M.gguf"
  "35:$HOME/models/Qwen3.5-2B-Q4_K_M.gguf"
)

OUT="$HOME/speed-results/rank-$(date '+%Y%m%d-%H%M%S')"
LOG="$HOME/bench-ranking.log"
mkdir -p "$OUT"
exec > "$LOG" 2>&1

# 标准口径：与仓库 phone-speed-bench.py 一致，显式关掉一切可能的后端卸载。
STD="-ngl 0 -dev none -nkvo 1 -nopo 1 -t 4 -fa off -ctk f16 -ctv f16 -b 512 -ub 128 --repack 1"

# 频率采样：三个簇各取一个代表核，用于事后判断名次是否被降频污染。
freq() {
  local o="" c v
  for c in 0 4 7; do
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    o="$o cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$o"
}

# 单次测量：标签、模型路径、附加的 llama-bench 参数。
run() {
  local tag="$1" model="$2"
  shift 2
  echo "### $tag | $(basename "$model") | $*"
  echo "    频率前:$(freq)"
  llama-bench -m "$model" $STD "$@" -o json > "$OUT/$tag.json" 2> "$OUT/$tag.stderr.log"
  echo "    rc=$? 频率后:$(freq)"
  echo
  sleep 12
}

echo "开始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "输出目录: $OUT"
echo "频率:$(freq)"
echo

{
  echo "utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "android_release=$(getprop ro.build.version.release)"
  echo "android_sdk=$(getprop ro.build.version.sdk)"
  echo "soc=$(getprop ro.soc.model)"
  echo "incremental=$(getprop ro.build.version.incremental)"
  llama-bench --version 2>&1
  for pair in "${MODELS[@]}"; do
    sha256sum "${pair#*:}" 2>&1
  done
} > "$OUT/metadata.txt"
cat "$OUT/metadata.txt"
echo

echo "=============== B1 基线正序 d=0 r=3 ==============="
for pair in "${MODELS[@]}"; do
  run "b1-${pair%%:*}" "${pair#*:}" -p 128 -n 64 -d 0 -r 3 --no-warmup
done

echo "=============== B2 基线逆序 d=0 r=3 ==============="
for ((i=${#MODELS[@]}-1; i>=0; i--)); do
  pair="${MODELS[$i]}"
  run "b2-${pair%%:*}" "${pair#*:}" -p 128 -n 64 -d 0 -r 3 --no-warmup
done

# 深度扫描：深度在外层，方向逐层翻转，避免某个模型固定落在热尾段。
depth_round=0
for depth in 512 2048 4096; do
  depth_round=$((depth_round + 1))
  echo "=============== D$depth_round 深度 $depth r=2 ==============="
  if [ $((depth_round % 2)) -eq 1 ]; then
    order=()
    for pair in "${MODELS[@]}"; do order+=("$pair"); done
  else
    order=()
    for ((i=${#MODELS[@]}-1; i>=0; i--)); do order+=("${MODELS[$i]}"); done
  fi
  for pair in "${order[@]}"; do
    run "d$depth-${pair%%:*}" "${pair#*:}" -p 128 -n 64 -d "$depth" -r 2 --no-warmup
  done
done

echo "完成: $(date '+%Y-%m-%d %H:%M:%S')"
echo "频率:$(freq)"
echo "输出目录: $OUT"
if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
