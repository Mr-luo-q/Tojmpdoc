#!/usr/bin/env bash
# 在树莓派上运行，一次性采集部署报告需要的全部实测数据
#
# 用法：
#   chmod +x pi-bench.sh
#   ./pi-bench.sh [模型目录] [输出文件]
#   默认模型目录 ~/models，默认输出 ~/bench-report.txt

set -u

BIN="${BIN:-$HOME/llama}"
MODELS="${1:-$HOME/models}"
OUT="${2:-$HOME/bench-report.txt}"

exec > >(tee "$OUT") 2>&1

echo "======================== 系统信息 ========================"
date
echo -n "板子型号: "; cat /proc/device-tree/model; echo
uname -a
echo "CPU 核心数: $(nproc)"
lscpu | grep -E "^Model name|^CPU\(s\)|^CPU max|^BogoMIPS" || true
echo "CPU 当前频率: $(vcgencmd measure_clock arm)"
echo "CPU 调速策略: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
echo "内存: $(free -h | awk '/^Mem:/ {print $2" 总计 / "$7" 可用"}')"
echo "存储: $(df -h / | awk 'NR==2 {print $2" 总计 / "$4" 可用"}')"
echo "系统: $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "温度: $(vcgencmd measure_temp)"
echo "欠压/降频: $(vcgencmd get_throttled)"
echo

for m in "$MODELS"/*.gguf; do
    [ -e "$m" ] || { echo "没有找到模型文件: $MODELS/*.gguf"; break; }
    name="$(basename "$m")"

    echo "======================== $name ========================"
    echo "文件大小: $(du -h "$m" | cut -f1)"
    echo "温度(测试前): $(vcgencmd measure_temp)"
    echo

    echo "---------- llama-bench：纯推理吞吐 ----------"
    "$BIN/llama-bench" -m "$m" -t 4 -p 512 -n 128 -r 3 -o md
    echo

    echo "---------- 端到端问答耗时与内存峰值 ----------"
    /usr/bin/time -f "峰值内存: %M KB | 总耗时: %e 秒 | CPU 占用: %P" \
        "$BIN/llama-cli" -m "$m" -t 4 -c 2048 -n 128 -no-cnv \
        -p "用一句话说明什么是树莓派。/no_think" 2>&1 | tail -n 25
    echo

    echo "温度(测试后): $(vcgencmd measure_temp)"
    echo "欠压/降频: $(vcgencmd get_throttled)"
    echo
done

echo "======================== 采集完成 ========================"
echo "结果已保存到: $OUT"
