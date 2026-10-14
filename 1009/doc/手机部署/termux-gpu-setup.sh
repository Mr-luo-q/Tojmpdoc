#!/data/data/com.termux/files/usr/bin/bash
#
# 手机部署 · Termux 侧 GPU 后端安装与验证（天玑 8300 / Mali-G615 专用）
#
# 这个脚本解决一件事：把 llama.cpp 的 Vulkan 后端在 Termux 里跑起来，并验证
# 它真的落到了 Mali GPU 上，而不是悄悄退回 CPU。
#
# 为什么不需要自己编译：
#   Termux 官方仓库提供 llama-cpp-backend-vulkan 预编译包，
#   配套 vulkan-loader-android 走 Android 系统的 /vendor/lib64/hw/vulkan.mali.so。
#   这绕开了「官方不发 Android arm64 Vulkan 构建」的死结。
#
# 用法：
#   bash termux-gpu-setup.sh            # 安装 + 验证 + 跑基准
#   bash termux-gpu-setup.sh --check    # 只做能力检查，不装东西
#   bash termux-gpu-setup.sh --no-bench # 装完不跑基准
#
# 输出：
#   终端打印每一步结论；基准数据同时写入 ~/gpu-bench.log
#
# 不做的事：
#   不碰 NPU（那条路另走 gpu-npu-reach.sh，因为入口是 NNAPI HAL 而非 Termux 包）
#   不改任何系统设置

set -uo pipefail

LOG="$HOME/gpu-bench.log"
MODE="${1:-full}"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# 把输出同时写到日志和终端
tee_log() { tee -a "$LOG"; }

[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] \
  || die "看起来不在 Termux 里"

# 长任务期间拉住唤醒锁，避免灭屏后 CPU 被限频，污染基准数据
if command -v termux-wake-lock >/dev/null 2>&1; then termux-wake-lock; fi

echo "=============================================================="
echo " 第 0 步 · 记录当前身份与 SELinux 上下文"
echo "=============================================================="
echo "uid: $(id -u)  gid: $(id -g)"
echo "id: $(id)"
echo "SELinux 上下文: $(cat /proc/self/attr/current 2>/dev/null)"
echo "SELinux 模式: $(getenforce 2>/dev/null)"
echo "内核: $(uname -r)"
echo "ABI: $(getprop ro.product.cpu.abi)"

echo
echo "=============================================================="
echo " 第 1 步 · GPU 设备节点可达性（Termux 身份，与 shell 身份对比）"
echo "=============================================================="
# 关键验证点：Termux 的 app 域能不能 open /dev/mali0。
# 这一步要是失败，后面 Vulkan 一定跑不起来，先把根因定位在这里。
for n in /dev/mali0 /dev/dri/card0 /dev/apusys; do
  if [ -e "$n" ]; then
    ls -l "$n"
    # 用 dd 读 1 字节，比 head 更可靠地反映 open+read 的权限结果
    if dd if="$n" of=/dev/null bs=1 count=1 2>/dev/null; then
      echo "  → $n 可读（open + read 成功）"
    else
      echo "  → $n 不可读（open 被拒，SELinux 或权限位拦截）"
    fi
    if [ -w "$n" ]; then echo "  → $n 可写"; else echo "  → $n 不可写"; fi
  else
    echo "$n 不存在"
  fi
done

echo
echo "=============================================================="
echo " 第 2 步 · 图形驱动库可见性"
echo "=============================================================="
for so in /vendor/lib64/hw/vulkan.mali.so \
          /vendor/lib64/egl/mt6897/libGLES_mali.so \
          /vendor/lib64/libOpenCL.so \
          /system/lib64/libvulkan.so; do
  if [ -r "$so" ]; then
    echo "可读  $so  ($(stat -c%s "$so" 2>/dev/null) 字节)"
  else
    echo "不可读/不存在  $so"
  fi
done

if [ "$MODE" = "--check" ]; then
  echo
  info "只做检查，结束。"
  if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
  exit 0
fi

echo
echo "=============================================================="
echo " 第 3 步 · 安装 llama.cpp 与 Vulkan 后端"
echo "=============================================================="
info "更新包索引"
pkg update -y >/dev/null 2>&1 || warn "pkg update 有警告，继续"

info "安装 vulkan-tools（提供 vulkaninfo）"
pkg install -y vulkan-tools >/dev/null 2>&1 || warn "vulkan-tools 安装失败"

info "安装 llama-cpp + Vulkan 后端"
# llama-cpp-backend-vulkan 依赖 llama-cpp，会把本体一起带上
pkg install -y llama-cpp llama-cpp-backend-vulkan >/dev/null 2>&1 \
  || warn "llama-cpp 安装有警告，继续"

info "安装 clinfo（查 Mali 的 OpenCL）"
pkg install -y clinfo >/dev/null 2>&1 || warn "clinfo 安装失败（OpenCL 不是必需）"

echo
echo "=============================================================="
echo " 第 4 步 · vulkaninfo 验证：Mali 真的被枚举到了吗"
echo "=============================================================="
if command -v vulkaninfo >/dev/null 2>&1; then
  # --summary 输出短，便于抓关键字段；失败时回退到全量输出的头部
  echo "--- vulkaninfo --summary ---"
  vulkaninfo --summary 2>&1 | head -60
  echo
  echo "--- 关键字段提取 ---"
  vulkaninfo --summary 2>&1 | grep -iE 'deviceName|driverName|driverInfo|apiVersion|deviceType|GPU id' | head -20
else
  warn "vulkaninfo 不可用，跳过。Vulkan 是否可用将在 llama.cpp 日志里体现。"
fi

echo
echo "=============================================================="
echo " 第 5 步 · clinfo 验证（Mali 的 OpenCL，作为 GPU 的第二条证据）"
echo "=============================================================="
if command -v clinfo >/dev/null 2>&1; then
  clinfo 2>&1 | grep -iE 'Platform Name|Device Name|Device Type|Device Version|Max compute units|Global memory size' | head -20
else
  warn "clinfo 不可用"
fi

echo
echo "=============================================================="
echo " 第 6 步 · llama.cpp 后端清单"
echo "=============================================================="
# llama-cli --list-devices 会列出所有可用后端；这是「GPU 是否真被 ggml 认出来」的直接证据
if command -v llama-cli >/dev/null 2>&1; then
  echo "--- llama-cli --list-devices ---"
  llama-cli --list-devices 2>&1 | head -30
  echo
  echo "--- 版本 ---"
  llama-cli --version 2>&1 | head -5
else
  warn "llama-cli 不在 PATH，检查 ~/.local/bin 或 pkg 安装结果"
fi
echo "--- ggml 后端动态库落点 ---"
find /data/data/com.termux/files/usr/lib -maxdepth 2 -iname '*ggml*' 2>/dev/null | head -20

echo
echo "=============================================================="
echo " 第 7 步 · 找模型"
echo "=============================================================="
MODEL=""
for cand in "$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
            "$HOME/models/Qwen3-0.6B-Q4_K_M.gguf" \
            "$HOME/models"/*.gguf; do
  [ -f "$cand" ] && MODEL="$cand" && break
done
if [ -z "$MODEL" ]; then
  warn "~/models 下没有 gguf 模型，跳过基准测试"
  warn "模型要先从电脑推过来，或在 Termux 里下载"
else
  echo "使用模型: $MODEL  ($(stat -c%s "$MODEL") 字节)"
fi

echo
echo "=============================================================="
echo " 第 8 步 · 基准测试：CPU vs Vulkan"
echo "=============================================================="
if [ -n "$MODEL" ] && [ "$MODE" != "--no-bench" ] && command -v llama-bench >/dev/null 2>&1; then
  echo "--- 说明 ---"
  echo "每组都测 prompt processing（pp，计算受限）与 text generation（tg，访存受限）"
  echo "手机热得快，所以每组之间保持命令一致，靠 p 和 n 参数控制负载"
  echo
  echo "########## 组 1: 纯 CPU（-ngl 0） ##########"
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 0 -t 8 2>&1 | tee_log
  echo
  echo "########## 组 2: Vulkan 全量卸载（-ngl 99） ##########"
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 99 2>&1 | tee_log
  echo
  echo "########## 组 3: Vulkan 半量卸载（-ngl 16） ##########"
  llama-bench -m "$MODEL" -p 512 -n 128 -ngl 16 2>&1 | tee_log
elif [ -z "$MODEL" ]; then
  warn "没有模型，跳过基准"
else
  warn "llama-bench 不可用，跳过基准"
fi

echo
echo "=============================================================="
echo " 结论速查"
echo "=============================================================="
cat <<'EOF'
 看三件事：

 1. vulkaninfo 里 deviceName 是否出现 "Mali-G615"（或类似）
      出现 → Vulkan 驱动层通了
      没出现但没报错 → loader 没找到 ICD，检查 vulkan-loader-android 是否装上

 2. llama-cli --list-devices 是否列出 Vulkan 设备
      列出 → ggml 认到了 GPU
      没列出 → 后端库没被加载，检查 llama-cpp-backend-vulkan 是否装成功

 3. llama-bench 组 1 与组 2 的 pp/tg 数字对比
       常见结果：pp 明显变快（GPU 擅长大批量矩阵乘）
                 tg 可能变慢或持平（decode 是访存受限，GPU 未必占优）
       若 tg 大幅慢于 CPU，说明这个模型规模下 Vulkan 不划算，
       但 prefill 快可以用混合策略：-ngl 部分层数
EOF

echo
echo "日志已保存: $LOG"
if command -v termux-wake-unlock >/dev/null 2>&1; then termux-wake-unlock; fi
info "完成"
