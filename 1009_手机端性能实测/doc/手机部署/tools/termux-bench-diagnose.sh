#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · 追查「为什么这台比上一台慢 3 倍」
#
# 首轮基准结果（-t 8，llama-bench 默认 -ngl -1）：
#     Qwen2.5-1.5B   pp512  26.65 ± 0.86     tg128   6.93 ± 0.05
#     Qwen3-0.6B     pp512  63.30 ± 0.76     tg128  17.07 ± 0.65
#
# 对照上一台华为 Pura 70（Kirin 9010）：
#     Qwen2.5-1.5B   pp512  49.4~54.3        tg128  18.35~22.62
#     Qwen3-0.6B     pp512  132.3~133.7      tg128  49.42~49.65
#
# 差距 2~3 倍，而本机 CPU 指令集更全（多了 sve2），不该更慢。三个假设要排除：
#
#   假设 A  线程数不对
#           本机是三簇结构（4×A510 + 3×A715 + 1×A720），
#           与华为那台 8 核构成不同，-t 8 未必最优。
#           实测 -t 4 / 6 / 8 三档。
#
#   假设 B  内存压力
#           实测 dumpsys 显示 11323M total / 9750M used / 1572M free，
#           swap 已用 1639M。llama.cpp 用 mmap 映射模型，
#           内存紧张时页面被换出，访存受限的 tg 首当其冲。
#           验证法：看模型的 RSS 是否接近其体积（说明常驻），
#           以及对比 0.6B（0.38 GB，受压力小）与 1.5B 的差距比例。
#
#   假设 C  llama-bench 的 -ngl -1 让它走了非预期路径
#           首轮日志显示 backend 标注 Vulkan 但 "No devices found"，
#           实际回落到 CPU。这次显式给 -ngl 0 固定 CPU 路径。
#
# 用法：
#   bash termux-bench-diagnose.sh

set -uo pipefail

export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export TMPDIR=/data/data/com.termux/files/usr/tmp

M15="$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
M06="$HOME/models/Qwen3-0.6B-Q4_K_M.gguf"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

echo "=============================================================="
echo " 内存压力现状（假设 B 的直接证据）"
echo "=============================================================="
# /proc/meminfo 在部分机型上对 app 域不可读，读不到就退回 free
if [ -r /proc/meminfo ]; then
  grep -E '^(MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree|SwapCached)' /proc/meminfo
else
  echo "/proc/meminfo 不可读，改用 free"
  free -m 2>/dev/null || echo "free 也不可用"
fi
echo
echo "--- 模型文件的页缓存占用（若远小于模型体积，说明没被缓存） ---"
# mincore 需要程序，这里用简单近似：看 cached 总量与模型体积的关系
for m in "$M15" "$M06"; do
  [ -f "$m" ] || continue
  sz=$(stat -c%s "$m")
  echo "  $(basename "$m")  体积 $((sz / 1024 / 1024)) MB"
done

echo
echo "=============================================================="
echo " 假设 A：线程数扫描（1.5B，固定 -ngl 0 走纯 CPU）"
echo "=============================================================="
echo "llama-bench 支持逗号分隔的多值，一次命令跑多档并输出对照表"
echo
# -ngl 0 固定 CPU；-t 4,6,8 三档一次跑完，-r 3 重复三次
llama-bench -m "$M15" -p 256 -n 64 -ngl 0 -t 4,6,8 -r 3 2>&1

echo
echo "=============================================================="
echo " 假设 A 补充：0.6B 也扫一遍线程数"
echo "=============================================================="
llama-bench -m "$M06" -p 256 -n 64 -ngl 0 -t 4,6,8 -r 3 2>&1

echo
echo "=============================================================="
echo " 假设 B 验证：两个模型的 tg 比值是否与体积比值一致"
echo "=============================================================="
cat <<'EOF'
 判读逻辑：
   1.5B 体积 1065 MB，0.6B 体积 378 MB，比值 2.82
   若是纯访存受限且内存充足，tg 比值应接近 2.82（体积小则快）
   若内存压力是主因，1.5B 受压力更大，实际比值会明显大于 2.82

 首轮实测 tg 比值：17.07 / 6.93 = 2.46
   2.46 < 2.82，说明 1.5B 并没有因为体积大而额外吃亏，
   反而比理论值稍好。这倾向于「不是内存压力主因」，
   而更像「整体带宽不足」或「线程数不对」。
EOF

echo
echo "=============================================================="
echo " 假设 C 验证：看 llama-bench 是否真的加载了 Vulkan 后端"
echo "=============================================================="
echo "--- 显式 -ngl 0 时的后端加载日志 ---"
llama-bench -m "$M06" -p 64 -n 16 -ngl 0 -t 4 -r 1 2>&1 | grep -iE 'load_backend|ggml_vulkan|backend|no devices' | head -10

echo
echo "--- 对比：不指定 -ngl 时 ---"
llama-bench -m "$M06" -p 64 -n 16 -t 4 -r 1 2>&1 | grep -iE 'load_backend|ggml_vulkan|no devices' | head -10

echo
echo "=============================================================="
echo " 补充：内存回收能否改善"
echo "=============================================================="
# 尝试通过 Termux 侧可用的手段催促回收（不一定有效，仅作观察）
echo "当前可用内存: $(grep -E '^MemAvailable' /proc/meminfo 2>/dev/null || echo 'n/a')"
echo
echo "说明：Termux 无 root，无法主动 drop_caches，"
echo "     能做的只有「关掉后台应用后重测」。"
echo "     如果线程数扫描结果显示 -t 4 或 -t 6 明显优于 -t 8，"
echo "     那结论就是线程配置问题，与内存无关。"

if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
