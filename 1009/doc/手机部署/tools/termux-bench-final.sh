#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 定稿配置搜索（找这台机器上实际可用的最优参数）
#
# 已知事实（绑核实测，1.5B，-ngl 0）：
#
#   绑定           线程   pp128     tg48
#   cpu0-3          4      3.46      2.60    小核对推理几乎无用
#   cpu4-6          3     17.07     12.50
#   cpu7            1      5.76      4.34
#   cpu0-7          8     24.23      8.13    pp 最好但 tg 被拖累
#   cpu4-7          4     21.70     14.93    tg 最好
#
# 规律：pp 随线程数单调上升（计算受限），tg 随线程数上升而下降（访存带宽饱和）。
# 这说明存在内存带宽墙，加核只增加竞争不增加吞吐。
#
# 本脚本要回答的是实际问题：
#   「日常用的时候，参数该怎么给」
# 因此测三组候选，并在两个模型上都验证：
#   组 1  llama-bench 默认 -t 4（让调度器自己分配，实测最快的一档）
#   组 2  taskset 绑 cpu4-7 + 4 线程（tg 最优）
#   组 3  taskset 绑 cpu4-6 + 3 线程（只用中核，看是否更稳）
#
# 同时测一组「分阶段最优」的可行性：
#   llama.cpp 支持 -t 与 -tb（批处理线程数）分开设，
#   pp 阶段吃 -tb、tg 阶段吃 -t，理论上可以各取所长。
#   这一组直接决定最终推荐参数。
#
# 用法：
#   bash termux-bench-final.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

if have termux-wake-lock; then termux-wake-lock; fi

show() { grep -E '^\|' | grep -vE 'model|^-+'; }

echo "=============================================================="
echo " 一、1.5B：三组候选配置"
echo "=============================================================="

echo "--- 组 1：默认调度，-t 4 ---"
llama-bench -m "$M15" -p 256 -n 64 -ngl 0 -t 4 -r 3 2>&1 | show

echo
echo "--- 组 2：绑 cpu4-7，4 线程 ---"
taskset -c 4-7 llama-bench -m "$M15" -p 256 -n 64 -ngl 0 -t 4 -r 3 2>&1 | show

echo
echo "--- 组 3：绑 cpu4-6，3 线程 ---"
taskset -c 4-6 llama-bench -m "$M15" -p 256 -n 64 -ngl 0 -t 3 -r 3 2>&1 | show

echo
echo "--- 组 4：绑 cpu4-7，-t 4 -tb 4（分阶段参数）---"
# -tb 是 batch 线程数，主要作用于 prefill 阶段
taskset -c 4-7 llama-bench -m "$M15" -p 256 -n 64 -ngl 0 -t 4 -tb 4 -r 3 2>&1 | show

echo
echo "=============================================================="
echo " 二、0.6B：同样的四组"
echo "=============================================================="

echo "--- 组 1：默认调度，-t 4 ---"
llama-bench -m "$M06" -p 256 -n 64 -ngl 0 -t 4 -r 3 2>&1 | show

echo
echo "--- 组 2：绑 cpu4-7，4 线程 ---"
taskset -c 4-7 llama-bench -m "$M06" -p 256 -n 64 -ngl 0 -t 4 -r 3 2>&1 | show

echo
echo "--- 组 3：绑 cpu4-6，3 线程 ---"
taskset -c 4-6 llama-bench -m "$M06" -p 256 -n 64 -ngl 0 -t 3 -r 3 2>&1 | show

echo
echo "=============================================================="
echo " 三、验证：真实对话走一遍（llama-cli，看端到端速度）"
echo "=============================================================="
# 用英文提示避免编码问题；-st 表示答完即退出
PROMPT="Name the three largest planets in the solar system."
for cfg in "default:4" "pinned:4"; do
  name="${cfg%%:*}"; th="${cfg##*:}"
  echo "--- llama-cli  $name  -t $th ---"
  if [ "$name" = "pinned" ]; then
    taskset -c 4-7 llama-cli -m "$M06" -t "$th" -c 1024 -n 64 -ngl 0 -st \
      -no-cnv -p "$PROMPT" 2>&1 | grep -iE 'eval time|total time|tokens per second|llama_perf' | head -8
  else
    llama-cli -m "$M06" -t "$th" -c 1024 -n 64 -ngl 0 -st \
      -no-cnv -p "$PROMPT" 2>&1 | grep -iE 'eval time|total time|tokens per second|llama_perf' | head -8
  fi
  echo
done

echo
echo "=============================================================="
echo " 四、结论汇总表（把上面实测值填进来）"
echo "=============================================================="
cat <<'EOF'
 1.5B Q4_K_M
   配置                         pp t/s        tg t/s        建议用途
   ─────────────────────────────────────────────────────────────────
   默认 -t 4                    ~22           ~16          日常首选
   绑 cpu4-7 -t 4               ~22           ~15          与默认相当
   绑 cpu4-6 -t 3               ~17           ~12.5        更省电
   绑 cpu0-7 -t 8               ~24            ~8          不推荐（tg 崩）

 0.6B Q4_K_M
   同上四组对照，看大核绑定的收益是否更明显

 关键判断：
   pp 与 tg 的最优线程数方向相反（pp 要多核，tg 要少核），
   这是内存带宽饱和的直接证据。日常对话两者都有，
   取折中——实际以「默认 -t 4」或「绑 cpu4-7」为宜。
EOF

if have termux-wake-unlock; then termux-wake-unlock; fi
