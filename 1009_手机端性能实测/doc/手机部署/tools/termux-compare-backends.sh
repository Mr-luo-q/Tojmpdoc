#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · CPU / GPU / NPU 三后端同参数对比
#
# 为什么要重测：
#   之前 GPU 的数据（-p 256 / -p 512，带预热）与 CPU 详表的数据
#   （-p 128，--no-warmup）参数不同，直接并列不严谨。
#   本脚本用**完全相同的参数与条件**把三个后端各测一遍。
#
# 三个后端的实现方式：
#   CPU   装 vulkan-loader-generic（桌面版），ggml 只会枚举到 llvmpipe
#         但我们显式 -ngl 0，张量全在 CPU，backends 列会显示 CPU
#   GPU   装 vulkan-loader-android（Android 版），libvulkan.so 符号链接到
#         /system/lib64/libvulkan.so，Mali-G615 被枚举到
#   NPU   没有可用入口。llama.cpp 无法用 NNAPI（GGUF 映射不到 NNAPI 算子集，
#         上游已移除该后端），TFLite 的 NNAPI delegate 也没编进 Termux 的包。
#         本脚本会把这个事实作为结论的一部分记录下来，而不是伪造数字。
#
# 统一测量条件：
#   模型    Qwen2.5-1.5B 与 Qwen3-0.6B 各测一遍
#   -p 128 -n 64     与 CPU 详表一致
#   -r 3             取平均，标准差用于判断数据质量
#   --no-warmup      与 CPU 详表一致
#   -t 4             CPU 侧最优线程数
#   -o jsonl         拿到 avg_ns（真实耗时）而不只是 t/s
#
# 切换 loader 需要重装包，所以脚本按「CPU → 装 android loader → GPU」顺序跑。
#
# 用法：
#   bash termux-compare-backends.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=$HOME/../usr/bin:$PATH
export TMPDIR=$HOME/../usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"
LOG="$HOME/backend-compare.log"
COMMON="-p 128 -n 64 -r 3 --no-warmup -o jsonl"

exec > "$LOG" 2>&1

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

read_freq() {
  local out=""
  for c in 0 4 7; do
    local v
    v=$(cat "/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    out="$out cpu$c=$(( ${v:-0} / 1000 ))"
  done
  echo "$out"
}

# 从 jsonl 里提取关键字段，压成一行便于阅读
# 注意：必须把**完整的 jsonl** 喂给 python，不能先 grep。
# 上一版先做了 grep -o '"backends"...'，管道里只剩半行 JSON，
# python 解析不出任何东西，结果每格只打出 backends 字段。
summarize() {
  python - <<'PY'
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line.startswith('{'):
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    npp = d.get('n_prompt', 0)
    ngen = d.get('n_gen', 0)
    if npp and not ngen:
        test = f"pp{npp}"
    elif ngen and not npp:
        test = f"tg{ngen}"
    else:
        test = f"pp{npp}+tg{ngen}"
    if d.get('n_depth'):
        test += f" @d{d['n_depth']}"
    ts = d.get('avg_ts', 0)
    ns = d.get('avg_ns', 0)
    sd = d.get('stddev_ts', 0)
    be = d.get('backends', '?')
    ngl = d.get('n_gpu_layers', '?')
    nthr = d.get('n_threads', '?')
    print(f"  {test:16s} backend={be:8s} ngl={ngl:<4} thr={nthr:<3} "
          f"{ts:7.2f} t/s  ±{sd:5.2f}  耗时 {ns/1e6:9.1f} ms")
PY
}

echo "############################################################"
echo "# 后端对比 · 统一参数"
echo "############################################################"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "参数: $COMMON  -t 4 -ngl 0/99"
echo "拓扑: cpu0-3 A510 2.2GHz / cpu4-6 A715 3.2GHz / cpu7 A720 3.35GHz"
echo "频率:$(read_freq)"

# ============================================================
echo
echo "############################################################"
echo "# 一 · CPU 后端"
echo "############################################################"
echo "当前 loader: $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备清单: $(llama-cli --list-devices 2>&1 | tail -2 | tr '\n' ' ')"
echo

echo "--- 1.5B CPU (-ngl 0) ---"
llama-bench -m "$M15" -t 4 -ngl 0 $COMMON 2>/dev/null | summarize
echo
echo "--- 0.6B CPU (-ngl 0) ---"
llama-bench -m "$M06" -t 4 -ngl 0 $COMMON 2>/dev/null | summarize
echo
echo "频率:$(read_freq)"

# ============================================================
echo
echo "############################################################"
echo "# 二 · 切换到 GPU 后端"
echo "############################################################"
echo "装 vulkan-loader-android 替换 generic"
pkg uninstall -y vulkan-loader-generic 2>&1 | tail -2
pkg install -y vulkan-loader-android 2>&1 | tail -2
echo
echo "切换后 libvulkan.so -> $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备清单:"
llama-cli --list-devices 2>&1 | tail -3
echo

echo "--- 1.5B GPU 全量卸载 (-ngl 99) ---"
# 全量卸载在 1.5B 上已知会挂死，套 timeout 保护
timeout -s KILL 300 llama-bench -m "$M15" -t 4 -ngl 99 $COMMON 2>/dev/null | summarize
rc=$?
[ "$rc" = "137" ] && echo "  （超时挂死，无数据）"
echo
echo "--- 1.5B GPU 部分卸载 (-ngl 8) ---"
llama-bench -m "$M15" -t 4 -ngl 8 $COMMON 2>/dev/null | summarize
echo
echo "--- 0.6B GPU 全量卸载 (-ngl 99) ---"
llama-bench -m "$M06" -t 4 -ngl 99 $COMMON 2>/dev/null | summarize
echo
echo "--- 0.6B GPU 部分卸载 (-ngl 8) ---"
llama-bench -m "$M06" -t 4 -ngl 8 $COMMON 2>/dev/null | summarize
echo
echo "频率:$(read_freq)"

# ============================================================
echo
echo "############################################################"
echo "# 三 · GPU 能力清单（解释为什么慢）"
echo "############################################################"
llama-bench -m "$M06" -t 4 -ngl 99 -p 16 -n 1 -r 1 2>&1 | grep -i 'ggml_vulkan' | head -3

# ============================================================
echo
echo "############################################################"
echo "# 四 · NPU"
echo "############################################################"
cat <<'EOF'
 NPU 无法给出速度数字，原因是入口全部封死。三层验证的结论：

 L1  /dev/apusys 存在但 App 域不可读写（SELinux 域策略拦截，
     不是文件权限问题——权限位写着 crw-rw-rw-）
 L2  /vendor/lib64 下的 libneuron_runtime.so 等被 linker namespace 拒绝
     （permitted_paths 里没有 /vendor/lib64）
 L3  NNAPI 能枚举到 4 个加速器（mtk-dsp_shim / mtk-mdla_shim /
     mtk-neuron_shim / nnapi-reference），但：
       · 手工建图卡在 ANeuralNetworksOperandType 的 ABI 校验
         （四种结构体布局均返回 ANEURALNETWORKS_BAD_DATA）
       · TFLite runtime 的构建里没有 NNAPI delegate
         （tflite.NnApiDelegate 属性不存在）

 更根本的阻断在格式层：
     NNAPI 吃的是 TFLite / ONNX 转换来的算子图，
     GGUF 的 GGML 图无法映射到 NNAPI 算子集。
     且 llama.cpp 上游已移除 NNAPI 后端。
     → llama.cpp 与 NPU 之间没有通路，与能否打通 ABI 无关。
EOF

# ============================================================
echo
echo "############################################################"
echo "# 五 · 恢复纯 CPU 环境"
echo "############################################################"
pkg uninstall -y vulkan-loader-android 2>&1 | tail -2
pkg install -y vulkan-loader-generic 2>&1 | tail -2
echo "恢复后 libvulkan.so -> $(readlink -f "$HOME/../usr/lib/libvulkan.so" 2>/dev/null)"
echo "设备清单: $(llama-cli --list-devices 2>&1 | tail -2 | tr '\n' ' ')"

echo
echo "结束: $(date '+%H:%M:%S')"
echo "频率:$(read_freq)"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
echo "日志: $LOG"
