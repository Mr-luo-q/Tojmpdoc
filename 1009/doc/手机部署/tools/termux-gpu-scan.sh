#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · GPU 卸载量的安全扫描（每个测试都套 timeout）
#
# 已知：
#   1. Mali-G615 MC6 已被 llama.cpp 认出
#        Vulkan0: Mali-G615 MC6 (11271 MiB, 11271 MiB free)
#   2. ggml 报告的能力：
#        fp16: 1  bf16: 0  fp4: 0  warp size: 16
#        shared memory: 32768  int dot: 0  matrix cores: none
#   3. -ngl 99（全量卸载）会卡死在初始化，不产生任何 t/s
#        进程累计 CPU 仅 18 秒但存活很久，属于阻塞而非计算
#
# 本脚本要回答：是不是只有全量卸载才挂？部分卸载能不能用？
#
# 每个测试都套 timeout，挂死就跳过，不会让整个脚本卡住。
# timeout 的用法：timeout -s KILL 秒数 命令
#
# 用法：
#   bash termux-gpu-scan.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

MODEL="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
RESULT="$HOME/gpu-scan-result.log"

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

# 结果只写一个文件，便于最后统一读取
: > "$RESULT"

say() { echo "$@" | tee -a "$RESULT"; }

say "=============================================================="
say " 环境确认"
say "=============================================================="
say "设备: $(llama-cli --list-devices 2>&1 | grep Vulkan)"
say "内存: $(grep MemAvailable /proc/meminfo 2>/dev/null)"
say ""

# 单次测试：带 timeout，结果按行解析
# 参数: 标签 模型 ngL timeout秒 prompt生成数
one_test() {
  local tag="$1" model="$2" ngl="$3" tmo="$4"
  local out="$HOME/gpu-scan-$tag.log"
  say "--------------------------------------------------------------"
  say " $tag   ngl=$ngl   超时=${tmo}s"
  say "--------------------------------------------------------------"

  # timeout -s KILL：超时后强杀，避免阻塞
  timeout -s KILL "$tmo" llama-bench -m "$model" -p 256 -n 64 -ngl "$ngl" -r 1 \
      > "$out" 2>&1
  local rc=$?

  if [ "$rc" = "137" ] || [ "$rc" = "124" ]; then
    say "结果: 超时挂死（rc=$rc），这一档不可用"
    # 把卡住前的日志尾部打出来，便于判断卡在哪一步
    say "卡住前的最后几行:"
    tail -4 "$out" 2>/dev/null | sed 's/^/    /' | tee -a "$RESULT"
  elif [ "$rc" != "0" ]; then
    say "结果: 失败（rc=$rc）"
    tail -4 "$out" 2>/dev/null | sed 's/^/    /' | tee -a "$RESULT"
  else
    local data
    data=$(grep -E '^\|' "$out" 2>/dev/null | grep -vE 'model|^-+')
    if [ -n "$data" ]; then
      say "结果:"
      echo "$data" | sed 's/^/    /' | tee -a "$RESULT"
    else
      say "结果: 退出码 0 但没有数据行"
    fi
  fi
  say ""
}

say "=============================================================="
say " 一、1.5B：卸载量从 0 到 99 扫描"
say "=============================================================="
# 从最小卸载量开始，逐步加大，找出「到多少层开始挂」
one_test "15-ngl0"  "$MODEL" 0  180
one_test "15-ngl1"  "$MODEL" 1  180
one_test "15-ngl4"  "$MODEL" 4  240
one_test "15-ngl8"  "$MODEL" 8  300

say "=============================================================="
say " 二、0.6B：小模型是否更容易卸载成功"
say "=============================================================="
one_test "06-ngl0"  "$M06" 0  120
one_test "06-ngl4"  "$M06" 4  180
one_test "06-ngl99" "$M06" 99 240

say "=============================================================="
say " 三、汇总"
say "=============================================================="
for f in "$HOME"/gpu-scan-*.log; do
  [ -f "$f" ] || continue
  local_name=$(basename "$f" .log)
  line=$(grep -E '^\|' "$f" 2>/dev/null | grep -vE 'model|^-+' | head -4)
  if [ -n "$line" ]; then
    say "--- $local_name ---"
    echo "$line" | tee -a "$RESULT"
  else
    say "--- $local_name --- （无数据，卡死或失败）"
  fi
done

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
say ""
say "全部完成"
