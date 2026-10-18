#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · Qwen3-0.6B 与 Qwen3.5-0.8B 同口径速度测评
#
# 目的：
#   用完全相同的参数、交错顺序（ABBA）与固定冷却，比较两个小模型的速度，
#   并回答「小模型还有没有提速空间、空间在哪一维」。
#
# 为什么必须 ABBA 交错：
#   K70E 的主频随温度持续漂移，先跑完 A 再跑完 B 会把「温度差」记成「模型差」。
#   交错后两个模型共享同一段热状态，再用频率采样交叉验证读数是否可信。
#
# 五个实验组（每组结果单独落一个 JSON 文件，便于精确取数）：
#   S0 历史口径基线   -p 128 -n 64 -d 0            与四模型对比表同参数，用于接续旧数据
#   S1 标准口径基线   -p 128 -n 64 -d 0            显式 -fa off、f16 KV、b512 ub128
#   S2 线程扫描       -p 128 -n 64 -d 0            t=2/4/6/8，确认 t4 结论对新模型是否成立
#   S3 深度扫描       -d 0,512,2048,4096           SSM 混合架构的主场
#   S4 深度 2048 + FA -d 2048                      flash attention 开关在长上下文下的影响
#
# 用法：
#   bash termux-bench-qwen35-08.sh
#
# 产出：
#   $HOME/speed-results/0608-<时间戳>/   每组一个 JSON + 一个 stderr + metadata
#   $HOME/bench-qwen35-08.log            全过程日志（含频率采样）

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
M08="$HOME/models/Qwen3.5-0.8B-Q4_K_M.gguf"

OUT="$HOME/speed-results/0608-$(date '+%Y%m%d-%H%M%S')"
LOG="$HOME/bench-qwen35-08.log"
mkdir -p "$OUT"
exec > "$LOG" 2>&1

# 标准口径：显式关掉 GPU、KV 卸载、host 算子卸载，固定 FA 与 KV 精度，
# 与仓库既有的 phone-speed-bench.py 默认设置保持一致，便于横向对照。
STD="-ngl 0 -dev none -nkvo 1 -nopo 1 -t 4 -fa off -ctk f16 -ctv f16 -b 512 -ub 128 --repack 1"
# 历史口径：与《四模型架构与性能对比》用的参数一致，用于把新数据接回旧表。
LEGACY="-ngl 0 -t 4"

# 频率采样：读 0/4/7 号核的当前频率，用来判断同批数据是否在同一热状态下取得。
freq() {
  local o=""
  local c v
  for c in 0 4 7; do
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    o="$o cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$o"
}

# 单次测量：标签、模型、公共参数、附加参数；JSON 与 stderr 分别落盘。
run() {
  local tag="$1"
  local model="$2"
  local common="$3"
  shift 3
  echo "### $tag | $(basename "$model") | $common $*"
  echo "    频率前:$(freq)"
  llama-bench -m "$model" $common "$@" -o json > "$OUT/$tag.json" 2> "$OUT/$tag.stderr.log"
  local rc=$?
  echo "    rc=$rc 频率后:$(freq)"
  echo
  sleep 10
}

echo "开始: $(date '+%Y-%m-%d %H:%M:%S')"
echo "输出目录: $OUT"
echo "频率:$(freq)"
echo

# 环境取证：把版本、哈希、CPU 信息固化到结果目录，保证以后能复现这一批数据的身份。
{
  echo "utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "android_release=$(getprop ro.build.version.release)"
  echo "android_sdk=$(getprop ro.build.version.sdk)"
  echo "soc=$(getprop ro.soc.model)"
  llama-bench --version 2>&1
  dpkg-query -W llama-cpp 2>&1
  sha256sum "$M06" "$M08" 2>&1
} > "$OUT/metadata.txt"
cat "$OUT/metadata.txt"
echo

echo "=============== S0 历史口径基线 ==============="
run s0-06-a "$M06" "$LEGACY" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s0-08-a "$M08" "$LEGACY" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s0-08-b "$M08" "$LEGACY" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s0-06-b "$M06" "$LEGACY" -p 128 -n 64 -d 0 -r 3 --no-warmup

echo "=============== S1 标准口径基线 ==============="
run s1-06-a "$M06" "$STD" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s1-08-a "$M08" "$STD" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s1-08-b "$M08" "$STD" -p 128 -n 64 -d 0 -r 3 --no-warmup
run s1-06-b "$M06" "$STD" -p 128 -n 64 -d 0 -r 3 --no-warmup

echo "=============== S2 线程扫描 ==============="
for t in 2 4 6 8; do
  run "s2-08-t$t" "$M08" "${STD/ -t 4 / -t $t }" -p 128 -n 64 -d 0 -r 2 --no-warmup
done
run s2-06-t4 "$M06" "$STD" -p 128 -n 64 -d 0 -r 2 --no-warmup
run s2-06-t8 "$M06" "${STD/ -t 4 / -t 8 }" -p 128 -n 64 -d 0 -r 2 --no-warmup

echo "=============== S3 上下文深度扫描 ==============="
run s3-06-a "$M06" "$STD" -p 128 -n 64 -d 0,512,2048,4096 -r 2 --no-warmup
run s3-08-a "$M08" "$STD" -p 128 -n 64 -d 0,512,2048,4096 -r 2 --no-warmup
run s3-08-b "$M08" "$STD" -p 128 -n 64 -d 0,512,2048,4096 -r 2 --no-warmup
run s3-06-b "$M06" "$STD" -p 128 -n 64 -d 0,512,2048,4096 -r 2 --no-warmup

echo "=============== S4 深度 2048 下的 FA 对照 ==============="
run s4-06-faoff "$M06" "$STD" -p 128 -n 64 -d 2048 -r 2 --no-warmup
run s4-08-faoff "$M08" "$STD" -p 128 -n 64 -d 2048 -r 2 --no-warmup
run s4-08-faon "$M08" "${STD/ -fa off / -fa on }" -p 128 -n 64 -d 2048 -r 2 --no-warmup
run s4-06-faon "$M06" "${STD/ -fa off / -fa on }" -p 128 -n 64 -d 2048 -r 2 --no-warmup

echo "完成: $(date '+%Y-%m-%d %H:%M:%S')"
echo "频率:$(freq)"
echo "输出目录: $OUT"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
