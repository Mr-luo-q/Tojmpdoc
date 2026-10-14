#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 用 taskset 绑核重测，定位「加线程反而变慢」的根因
#
# 已有的反常数据（llama-bench，-ngl 0 纯 CPU）：
#
#   Qwen2.5-1.5B   pp256                tg64
#       -t 4       22.46 ± 0.06         16.32 ± 0.04     ← 最快
#       -t 6       21.50 ± 0.65         11.31 ± 0.05
#       -t 8       22.35 ± 0.14          7.80 ± 0.13     ← 最慢
#
#   Qwen3-0.6B     pp256                tg64
#       -t 4       57.04 ± 0.22         33.75 ± 0.25     ← 最快
#       -t 6       56.05 ± 0.13         17.34 ± 0.31
#       -t 8       60.27 ± 0.17         18.01 ± 0.04
#
# 特征：pp（计算受限）几乎不随线程数变化，tg（访存受限）随线程数增加而大幅下降。
# 这是「线程跨簇迁移破坏缓存局部性」的典型表现。
#
# 但先要查清一件基础事实：这台机器的物理簇归属。
# 首次探测时读到的 core_id 是交错的小数字（0,1,2,3,0,1,2,0），
# 那个读法（/sys/.../topology/core_id）反映的不是物理簇，
# 说明当时的「三簇结构」判断需要重新核实。
#
# 本脚本做两件事：
#   1. 用多种 sysfs 途径核实物理簇归属
#   2. 用 taskset 把线程绑到指定核上重测，找出真正的瓶颈在哪一簇
#
# 用法：
#   bash termux-bench-taskset.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if have termux-wake-lock; then termux-wake-lock; fi

echo "=============================================================="
echo " 第 1 步 · 核实物理簇归属（三种途径交叉验证）"
echo "=============================================================="

echo "--- 途径 1: scaling_max_freq（同频者同簇，最可靠） ---"
for c in $(seq 0 7); do
  f="/sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq"
  [ -r "$f" ] || f="/sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq"
  if [ -r "$f" ]; then
    echo "  cpu$c  最大频率 $(($(cat "$f") / 1000)) MHz"
  else
    echo "  cpu$c  频率节点不可读"
  fi
done

echo
echo "--- 途径 2: physical_package_id 与 core_id ---"
for c in $(seq 0 7); do
  d="/sys/devices/system/cpu/cpu$c/topology"
  [ -d "$d" ] || continue
  pkg=$(cat "$d/physical_package_id" 2>/dev/null || echo "?")
  core=$(cat "$d/core_id" 2>/dev/null || echo "?")
  clu=$(cat "$d/cluster_id" 2>/dev/null || echo "-")
  echo "  cpu$c  package=$pkg  core_id=$core  cluster_id=$clu"
done

echo
echo "--- 途径 3: /sys/devices/system/cpu/cpu*/cpufreq/related_cpus（内核给的簇内清单） ---"
for c in $(seq 0 7); do
  f="/sys/devices/system/cpu/cpu$c/cpufreq/related_cpus"
  [ -r "$f" ] && echo "  cpu$c 的同簇: $(cat "$f")"
done

echo
echo "--- 途径 4: 各簇的 devfreq / 调频策略目录 ---"
ls -d /sys/devices/system/cpu/cpufreq/policy* 2>/dev/null
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "$p" ] || continue
  echo "  $(basename "$p"): cpus=$(cat "$p/related_cpus" 2>/dev/null) max=$(($(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo 0) / 1000))MHz gov=$(cat "$p/scaling_governor" 2>/dev/null)"
done

echo
echo "--- 途径 5: nproc 与 taskset 的可用核掩码 ---"
echo "  nproc = $(nproc)"
if have taskset; then
  echo "  taskset 可用"
  echo "  当前进程可跑在: $(taskset -pc $$ 2>&1)"
else
  echo "  taskset 不可用，需要 pkg install util-linux"
fi

echo
echo "=============================================================="
echo " 第 2 步 · 若 taskset 不可用则安装"
echo "=============================================================="
if ! have taskset; then
  info "pkg install util-linux"
  pkg install -y util-linux 2>&1 | tail -3
fi

echo
echo "=============================================================="
echo " 第 3 步 · 绑核重测（1.5B，-ngl 0）"
echo "=============================================================="
# 按频率分簇的假设做绑核测试。不同簇组合各测一遍，
# 目的是找出「哪一簇贡献了性能，哪一簇在拖后腿」。
run_pinned() {
  local label="$1" cpus="$2" threads="$3"
  echo "--------------------------------------------------------------"
  echo " $label   绑到 CPU $cpus   用 $threads 线程"
  echo "--------------------------------------------------------------"
  if have taskset; then
    taskset -c "$cpus" llama-bench -m "$M15" -p 128 -n 48 -ngl 0 -t "$threads" -r 2 2>&1 \
      | grep -E '^\|' | grep -v 'model\|--'
  else
    llama-bench -m "$M15" -p 128 -n 48 -ngl 0 -t "$threads" -r 2 2>&1 \
      | grep -E '^\|' | grep -v 'model\|--'
  fi
  echo
}

# 逐个簇单独测：看单簇的能力上限
run_pinned "低频率簇（假设是 A510）"  "0-3" 4
run_pinned "中频率簇（假设是 A715）"  "4-6" 3
run_pinned "最高频率核（假设是 A720）" "7"   1

# 跨簇组合对照
run_pinned "全 8 核（首轮的劣化配置）" "0-7" 8
run_pinned "仅中+大核（跳过低频簇）"   "4-7" 4

echo
echo "=============================================================="
echo " 第 4 步 · 0.6B 上复现同样的绑核对照"
echo "=============================================================="
run06() {
  local label="$1" cpus="$2" threads="$3"
  echo "--- $label  绑到 $cpus  用 $threads 线程 ---"
  if have taskset; then
    taskset -c "$cpus" llama-bench -m "$M06" -p 128 -n 48 -ngl 0 -t "$threads" -r 2 2>&1 \
      | grep -E '^\|' | grep -v 'model\|--'
  fi
  echo
}
run06 "低频率簇" "0-3" 4
run06 "中+大核"  "4-7" 4

echo
echo "=============================================================="
echo " 判读框架"
echo "=============================================================="
cat <<'EOF'
 把结果填进这个表，就能看出瓶颈在哪：

                        1.5B tg     1.5B pp    0.6B tg
   低频簇 4 核
   中频簇 3 核
   最高频 1 核
   全 8 核
   中+大核 4 核

 三种可能的结论：

 甲、低频簇的 tg 明显低于中/高频簇
     → A510 的访存吞吐是瓶颈。解法：用 taskset 绑到高频簇，
       或多线程但避开低频簇。

 乙、单簇 tg 都低，但全 8 核也无法叠加（甚至更低）
     → 内存带宽本身到顶了，加核无用。这是硬件上限，
       只能换更小的模型（0.6B）或接受现状。

 丙、各簇单独测都不差，但 -t 8 明显劣化
     → 调度器的跨簇迁移是主因。解法：taskset 绑核，
       固定线程在簇内，避免迁移。

 对照参考（上一台华为 Pura 70，Kirin 9010，同为 4+3+1）：
     1.5B tg 18.35~22.62 t/s    pp 49.4~54.3 t/s   用 -t 8 得到
     0.6B tg 49.42~49.65 t/s    pp 132.3~133.7 t/s
   如果本机绑核后仍显著低于这些值，说明是内存子系统差异（硬件），
   而不是配置问题。
EOF

if have termux-wake-unlock; then termux-wake-unlock; fi
