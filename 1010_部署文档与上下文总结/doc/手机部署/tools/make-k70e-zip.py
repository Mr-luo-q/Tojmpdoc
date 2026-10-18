r"""把红米 K70E 的部署文档、脚本与原始日志打包成一个 zip。

为什么不复用 tools/make-docs-zip.py：
    那个脚本的文件清单与说明文本是为上一台设备（华为 Pura 70）写死的，
    对应的是另一批文档。改掉它会丢掉原包的复现能力，所以另起一个。

中文文件名的处理沿用同一套办法：逐个条目手工构造 ZipInfo 并显式设置
UTF-8 文件名标志位（general purpose bit 11），否则各平台会各自猜编码，
解压出来一堆乱码。

用法：
    python tools\make-k70e-zip.py <项目目录> <输出zip路径>
"""
import sys
import zipfile
from datetime import datetime
from pathlib import Path

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])

# (归档内路径, 源文件相对 SRC 的路径)
# 分四组：核心报告 / 脚本 / 脚本说明 / 原始日志
FILES = [
    # ---------- 一、核心报告 ----------
    ("报告/GPU-NPU探测报告.md", "GPU-NPU探测报告.md"),
    ("报告/CPU性能实测报告.md", "CPU性能实测报告.md"),
    ("报告/GPU-NPU加速实测报告.md", "GPU-NPU加速实测报告.md"),
    ("报告/Token速率详表.md", "Token速率详表.md"),
    ("报告/四模型架构与性能对比.md", "四模型架构与性能对比.md"),
    ("报告/交接文档.md", "交接文档.md"),

    # ---------- 二、启停脚本 ----------
    ("脚本/start-server.sh", "start-server-k70e.sh"),
    ("脚本/start-server.doc.md", "start-server-k70e.doc.md"),
    ("脚本/termux-gpu-setup.sh", "termux-gpu-setup.sh"),
    ("脚本/termux-gpu-setup.doc.md", "termux-gpu-setup.doc.md"),
    ("脚本/termux-npu-probe.sh", "termux-npu-probe.sh"),
    ("脚本/termux-npu-probe.doc.md", "termux-npu-probe.doc.md"),

    # ---------- 三、探测与测试脚本（含环境包装器与索引） ----------
    ("脚本/tools/README.doc.md", "tools/README.doc.md"),
    ("脚本/tools/termux-run.sh", "tools/termux-run.sh"),    ("脚本/tools/gpu-npu-probe.sh", "tools/gpu-npu-probe.sh"),
    ("脚本/tools/gpu-npu-probe.doc.md", "tools/gpu-npu-probe.doc.md"),
    ("脚本/tools/gpu-npu-reach.sh", "tools/gpu-npu-reach.sh"),
    ("脚本/tools/gpu-npu-reach.doc.md", "tools/gpu-npu-reach.doc.md"),
    ("脚本/tools/probe-gpu-npu.ps1", "tools/probe-gpu-npu.ps1"),
    ("脚本/tools/probe-gpu-npu.doc.md", "tools/probe-gpu-npu.doc.md"),
    ("脚本/tools/termux-cleanup-bench.sh", "tools/termux-cleanup-bench.sh"),
    ("脚本/tools/termux-compare-backends.sh", "tools/termux-compare-backends.sh"),
    ("脚本/tools/termux-cmp2.sh", "tools/termux-cmp2.sh"),
    ("脚本/tools/termux-perf-lean.sh", "tools/termux-perf-lean.sh"),
    ("脚本/tools/termux-perf-fill.sh", "tools/termux-perf-fill.sh"),
    ("脚本/tools/termux-perf-detail.sh", "tools/termux-perf-detail.sh"),
    ("脚本/tools/termux-http-timing.sh", "tools/termux-http-timing.sh"),
    ("脚本/tools/termux-bench-taskset.sh", "tools/termux-bench-taskset.sh"),
    ("脚本/tools/termux-freq-sample.sh", "tools/termux-freq-sample.sh"),
    ("脚本/tools/termux-freq-diagnose.sh", "tools/termux-freq-diagnose.sh"),
    ("脚本/tools/termux-verify-ui.sh", "tools/termux-verify-ui.sh"),
    ("脚本/tools/termux-install-ui.sh", "tools/termux-install-ui.sh"),
    ("脚本/tools/termux-check-server.sh", "tools/termux-check-server.sh"),
    ("脚本/tools/termux-gguf-arch.sh", "tools/termux-gguf-arch.sh"),
    ("脚本/tools/termux-get-models.sh", "tools/termux-get-models.sh"),
    ("脚本/tools/termux-compare-models.sh", "tools/termux-compare-models.sh"),
    ("脚本/tools/termux-verify-models.sh", "tools/termux-verify-models.sh"),
    ("脚本/tools/termux-probe-model-sources.sh", "tools/termux-probe-model-sources.sh"),
    ("脚本/tools/termux-test-qwen35.sh", "tools/termux-test-qwen35.sh"),
    ("脚本/tools/termux-fix-libcxx.sh", "tools/termux-fix-libcxx.sh"),    ("脚本/tools/termux-backend-diag.sh", "tools/termux-backend-diag.sh"),
    ("脚本/tools/termux-mali-attach.sh", "tools/termux-mali-attach.sh"),
    ("脚本/tools/termux-system-vulkan-test.sh", "tools/termux-system-vulkan-test.sh"),
    ("脚本/tools/termux-android-loader-test.sh", "tools/termux-android-loader-test.sh"),
    ("脚本/tools/termux-app-context-test.sh", "tools/termux-app-context-test.sh"),
    ("脚本/tools/termux-vulkan-android-loader.sh", "tools/termux-vulkan-android-loader.sh"),
    ("脚本/tools/termux-copy-mali-driver.sh", "tools/termux-copy-mali-driver.sh"),
    ("脚本/tools/termux-mali-origin-fix.sh", "tools/termux-mali-origin-fix.sh"),
    ("脚本/tools/termux-mali-dep-loop.sh", "tools/termux-mali-dep-loop.sh"),
    ("脚本/tools/termux-gpu-only-bench.sh", "tools/termux-gpu-only-bench.sh"),
    ("脚本/tools/termux-gpu-scan.sh", "tools/termux-gpu-scan.sh"),
    ("脚本/tools/termux-gpu-vs-cpu.sh", "tools/termux-gpu-vs-cpu.sh"),
    ("脚本/tools/termux-npu-tflite.sh", "tools/termux-npu-tflite.sh"),
    ("脚本/tools/termux-nnapi-enum.sh", "tools/termux-nnapi-enum.sh"),
    ("脚本/tools/termux-nnapi-enum2.sh", "tools/termux-nnapi-enum2.sh"),
    ("脚本/tools/termux-nnapi-runtime-check.sh", "tools/termux-nnapi-runtime-check.sh"),
    ("脚本/tools/termux-npu-e2e.sh", "tools/termux-npu-e2e.sh"),
    ("脚本/tools/termux-nnapi-abi-probe.sh", "tools/termux-nnapi-abi-probe.sh"),
    ("脚本/tools/make-k70e-zip.py", "tools/make-k70e-zip.py"),
    ("脚本/tools/make-k70e-zip.doc.md", "tools/make-k70e-zip.doc.md"),

    # ---------- 四、原始日志（可回溯的证据） ----------
    ("原始日志/gpu-npu-probe-first-run.log",
     "probe-reports/probe-7LPRYTBYU8NRY5SC-20261009-152022.log"),
    ("原始日志/app-context-test.log", "probe-reports/appctx.log"),
    ("原始日志/gpu-setup.log", "probe-reports/gpu-setup-out.log"),
    ("原始日志/fix-libcxx.log", "probe-reports/fix-libcxx.log"),
    ("原始日志/nnapi-runtime.log", "probe-reports/nnapi-runtime.log"),
    ("原始日志/perf-lean-1.5B-prefill.log", "probe-reports/perf-lean-1.5B-prefill.log"),
]

STAMP = datetime.now().strftime("%Y-%m-%d %H:%M")

README_TXT = f"""红米 K70E 手机端大模型部署 · 文档包
打包时间：{STAMP}
设备：Redmi K70E（2311DRK48C，代号 duchamp）
      MediaTek MT6897 = 天玑 8300-Ultra / Mali-G615 / APU 780
      Android 14（SDK 36），HyperOS，SELinux Enforcing
环境：Termux v0.118.3，llama.cpp 0.6.0，无 root


================================================================
一、这个包是什么
================================================================

红米 K70E 上部署本地大模型的全套文档、脚本与原始日志。
重点做了两件上一台设备（华为 Pura 70）没做成的事：

  1. 把 GPU 探测做到能跑出速度数字（最终结论是慢 10~20 倍，不可用）
  2. 把 NPU 的封堵原因定位到具体层级（最终结论是无通路）

四个模型的架构差异与性能数据也已实测完成。


================================================================
二、包里有什么
================================================================

报告/
  GPU-NPU探测报告.md          硬件能力与可达性探测（第一轮：有什么）
  CPU性能实测报告.md          CPU 数据、三簇拓扑、调频限制分析
  GPU-NPU加速实测报告.md      GPU 打通全过程 + NPU 封堵原因 + 我犯的 5 个错误
  Token速率详表.md            prefill/decode 细粒度曲线 + 三后端对比
  四模型架构与性能对比.md      四模型架构差异 + 长上下文衰减对照
  交接文档.md                 先看这个：设备状态、日常命令、9 个环境坑

脚本/
  start-server.sh             HTTP 服务启停（支持四个模型切换）
  termux-gpu-setup.sh         GPU 后端安装与验证
  termux-npu-probe.sh         NPU 三层可达性验证
  tools/                      32 个探测与测试脚本 + 说明文档
  tools/README.doc.md         脚本索引：它们之间的关系与调用顺序

原始日志/
  9 份关键测量的原始输出，用于回溯报告里的数字


================================================================
三、核心结论（一句话版）
================================================================

后端        能否用      实测速度 vs CPU
────────────────────────────────────────────────────────────
CPU         能         基准（唯一可用）
GPU(Vulkan) 能认到设备 tg 慢 10~20 倍
NPU(NNAPI)  无入口     —

GPU 慢的硬件原因（ggml 报告的 Mali-G615 能力）：
    int dot: 0           不支持整数点积，量化推理无硬件加速
    matrix cores: none   不支持 cooperative matrix
    bf16: 0              不支持 bfloat16

NPU 封堵的三层原因：
    L1  /dev/apusys 权限位看着是 crw-rw-rw-，App 域实际不可读写
    L2  /vendor/lib64 下的 neuron/apu 库被 linker namespace 拒绝
    L3  NNAPI 能枚举到 4 个加速器，但手工建图卡在 ABI，
        TFLite 构建里也没有 NNAPI delegate
    更根本的：GGUF 无法映射到 NNAPI 算子集，且 llama.cpp 已移除该后端


================================================================
四、四个模型（全部 Q4_K_M，同档位可比）
================================================================

模型               参数量   体积     pp128    tg64    特点
──────────────────────────────────────────────────────────────
Qwen3-0.6B         596 M   379 MB   80.41    43.19   最快
Qwen2.5-1.5B       1.78 B  1.07 GB  28.54    18.86   通用
Qwen3-1.7B         1.72 B  1.06 GB  25.10    15.44   深上下文衰减重
Qwen3.5-2B         1.88 B  1.22 GB  22.45    13.52   混合 SSM，长对话首选

两个值得注意的点：

  1. Qwen3-1.7B 比 Qwen2.5-1.5B 慢 18%，尽管参数量更少。
     原因是 head_count_kv：Qwen3-1.7B 是 8 个 KV 头，
     Qwen2.5-1.5B 只有 2 个。GQA 压缩更狠的模型 decode 更快。

  2. Qwen3.5-2B 是「注意力 + 状态空间」混合架构，长上下文衰减只有
     Qwen3-1.7B 的四分之一：

         深度      Qwen3-1.7B        Qwen3.5-2B
         d=0       15.58             10.75
         d=2048     7.48 (−52%)      9.67 (−10%)
         d=4096     5.10 (−67%)      8.93 (−16%)

     d=4096 时 2B 的模型反而比 1.7B 快 75%。


================================================================
五、怎么用
================================================================

手机浏览器（最省事）
    bash ~/start-server.sh
    然后打开 http://127.0.0.1:8080

切换模型
    MODEL=06 bash ~/start-server.sh     Qwen3-0.6B     最快
    MODEL=15 bash ~/start-server.sh     Qwen2.5-1.5B   通用（默认）
    MODEL=17 bash ~/start-server.sh     Qwen3-1.7B
    MODEL=35 bash ~/start-server.sh     Qwen3.5-2B     长对话

全面自检（一条命令看清服务状态）
    bash ~/scripts/termux-check-server.sh

命令行对话
    llama-cli -m ~/models/Qwen3-0.6B-Q4_K_M.gguf -t 4 -c 2048

三个必须遵守的参数：
    -t 4      实测最优。加到 8 会让 decode 掉一半以上
    -ngl 0    必须显式指定。Mali 实测慢 10~20 倍
    -c 2048   足够日常，更大只增加内存与访存压力


================================================================
六、九个必须知道的环境坑
================================================================

HyperOS 相关
  1. adb install 报 INSTALL_FAILED_USER_RESTRICTED
     需要在开发者选项打开「USB 安装」。该开关在无 SIM 卡时点不开，
     插卡才能启用（国行防盗装策略）。
  2. adb install -g 会被拒
     INSTALL_GRANT_RUNTIME_PERMISSIONS 在小米上是受限权限，去掉 -g。
  3. 小米的 USB PID 是关键判据
     VID_2717&PID_FF40 是 MTP（没开 USB 调试），FF48 才是 ADB。
     只看到 FF40 就去开发者选项把「USB 调试」重新开关一次再插拔线。

Termux 相关
  4. run-as 不设置 PATH
     直接 run-as com.termux bash 会报 exec failed。
     用绝对路径，或本包的 tools/termux-run.sh 包装器。
  5. /tmp 在 Termux 里不可写，要用 $TMPDIR
  6. 往手机推脚本不要推 /sdcard/Download
     Termux 没存储权限读不了。走 /data/local/tmp 再拷进私有目录。
     且 adb push 目标必须写完整文件名，写成目录会让文件名被截断。
  7. pkill 在 run-as 环境下匹配不到目标
     必须用 PID 杀。否则清理失败会导致多个基准进程并存、
     测出标准差大于均值的垃圾数据。

测量与自动化相关
  8. llama-cli 的 -no-cnv 已被移除
     用 -st（single-turn）。加了 -no-cnv 会直接报 invalid argument
     且完全不做推理。
  9. 拔线才能跑的测试，必须先把脚本推到手机再拔线
     拔线后 adb 断开，脚本推不上去。


================================================================
七、这套数据的局限（如实说明）
================================================================

1. 主频在漂移，跨节的绝对值不可直接比较
   同一参数（-p 128 -n 64 --no-warmup）两次测出 1.5B pp128
   分别是 18.44 与 27.60，差 50%。
   原因是 mtk-cpufreq-hw 硬件调频，请求来自厂商策略层，
   不同时刻给出的档位不同（采样到 cpu4 从 1300 到 2800 MHz 不等）。
   → 三后端对比是同一次会话内连续完成的，相对关系可靠；
     跨节引用绝对值则不可靠。

2. 主频被锁在硬件上限的 55~65%
   推理期间实测 cpu0 1400/2200、cpu4 1800/3200、cpu7 1800/3350，
   20 次采样完全一致。温度仅 28~37°C，不是热降频，
   是系统调频策略。Termux 无 root 改不了。
   → 解开后所有绝对值都还有上升空间。

3. 中文能力与回答质量未评估
   通过 shell 传中文会被编码破坏（实测模型收到乱码）。
   只能测速度，质量需要在浏览器界面上人工试用。

4. 热降频曲线未测
   上一台华为在持续压测中从 22.62 掉到 5.56 t/s，这台未做同样测试。
"""


def main():
    """命令行入口：argv[1] 项目目录，argv[2] 输出 zip 路径。

    每个条目都手工构造 ZipInfo 并设置 UTF-8 文件名标志位，
    使中文文件名在 Windows 资源管理器与安卓解压器上都不乱码；
    .sh 文件写入可执行权限位，解压后无需再 chmod。
    """
    missing = []
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # 说明文件放最前，打开压缩包第一眼就能看到
        info = zipfile.ZipInfo("说明.txt", date_time=datetime.now().timetuple()[:6])
        info.flag_bits |= 0x800
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        z.writestr(info, README_TXT.encode("utf-8"))

        for arcname, rel in FILES:
            path = SRC / rel
            if not path.exists():
                missing.append(rel)
                continue
            zi = zipfile.ZipInfo(arcname, date_time=datetime.now().timetuple()[:6])
            zi.flag_bits |= 0x800      # 关键：中文文件名按 UTF-8 解码
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if path.suffix == ".sh" else 0o644) << 16
            z.writestr(zi, path.read_bytes())

    print(f"生成 {OUT}  ({OUT.stat().st_size} 字节)")
    with zipfile.ZipFile(OUT) as z:
        names = z.namelist()
        print(f"条目数 {len(names)}")
        bad = z.testzip()
        print("CRC 校验:", "OK" if bad is None else f"损坏条目 {bad}")
    if missing:
        print(f"缺失（已跳过 {len(missing)} 项）:")
        for m in missing:
            print("  " + m)


if __name__ == "__main__":
    main()
