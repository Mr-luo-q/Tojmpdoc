#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 彻底清理残留的基准进程，并确认环境干净
#
# 背景：
#   上一轮脚本卡住后我用 `run-as com.termux pkill -f llama-bench` 清理，
#   但它没生效——pkill 在 run-as 环境下匹配不到目标，
#   结果新基准启动后有两个 llama-bench 同时跑，互相抢内存，
#   测出的 pp512 只有 3.68 ± 2.22（早先正常值是 20.69），
#   标准差远大于均值，是典型的被干扰数据。
#
# 本脚本用 PID 逐个杀，不用 pkill，避免匹配问题。
#
# 用法：
#   bash termux-cleanup-bench.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH

echo "=============================================================="
echo " 清理前"
echo "=============================================================="
echo "--- llama 相关进程 ---"
ps -A 2>/dev/null | grep -i llama || echo "（无）"
echo
echo "--- 内存 ---"
grep -E '^(MemTotal|MemFree|MemAvailable|SwapFree)' /proc/meminfo 2>/dev/null

echo
echo "=============================================================="
echo " 逐个杀"
echo "=============================================================="
# ps -A 的列：USER PID PPID VSZ RSS WCHAN ADDR S NAME
# 取第 2 列作 PID，第 9 列作进程名
KILLED=0
for pid in $(ps -A -o PID,NAME 2>/dev/null | grep -iE 'llama|termux-bench|termux-gpu|termux-vulkan' | awk '{print $1}'); do
  case "$pid" in
    ''|*[!0-9]*) continue ;;
  esac
  # 不要杀自己（本脚本的进程名里也可能含 termux）
  if [ "$pid" = "$$" ]; then continue; fi
  if kill -9 "$pid" 2>/dev/null; then
    echo "  已杀 PID $pid"
    KILLED=$((KILLED + 1))
  else
    echo "  杀不掉 PID $pid（权限或已退出）"
  fi
done
echo "共处理 $KILLED 个进程"

# 兜底再试一次 pkill（有时它反而有效）
pkill -9 -f llama-bench 2>/dev/null
sleep 3

echo
echo "=============================================================="
echo " 清理后"
echo "=============================================================="
echo "--- llama 相关进程 ---"
ps -A 2>/dev/null | grep -i llama || echo "（无，已清干净）"
echo
echo "--- 内存 ---"
grep -E '^(MemTotal|MemFree|MemAvailable|SwapFree)' /proc/meminfo 2>/dev/null

echo
echo "--- 等 10 秒让内存回收后复查 ---"
sleep 10
grep -E '^(MemFree|MemAvailable)' /proc/meminfo 2>/dev/null

echo
echo "=============================================================="
echo " 清理结论"
echo "=============================================================="
REMAIN=$(ps -A 2>/dev/null | grep -ci llama)
if [ "$REMAIN" = "0" ]; then
  echo "环境已干净，可以重新跑基准"
else
  echo "仍有 $REMAIN 个 llama 进程残留，需要再处理"
fi
