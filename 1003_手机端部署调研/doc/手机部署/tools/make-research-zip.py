"""把「GPU/NPU 调研 + 测速 + Home Assistant 构建」三类文档打包成一个 zip。

与 tools/make-docs-zip.py 的分工：
  make-docs-zip.py          打完整文档包（含全部脚本与说明书）
  本脚本                     打聚焦调研包（只收这三类文档 + 原始数据）

同样显式设置 ZIP 的 UTF-8 文件名标志位，避免中文名在安卓/Windows 上乱码。

用法：
  python tools/make-research-zip.py <项目目录> <输出zip> [--with-rpi <树莓派目录>]
"""
import sys
import zipfile
from datetime import datetime
from pathlib import Path

# 命令行参数：argv[1] 项目目录、argv[2] 输出 zip、可选 --with-rpi 目录
SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
RPI = None
if "--with-rpi" in sys.argv:
    RPI = Path(sys.argv[sys.argv.index("--with-rpi") + 1])


def build_manifest():
    """构造要打包的 (归档内路径, 源文件) 清单。树莓派数据存在时才加入。"""
    items = [
        # ---- 一、GPU / NPU 调研 ----
        ("01-GPU与NPU调研/提速调研报告.md", SRC / "提速调研报告.md"),
        ("01-GPU与NPU调研/端侧优化与容器化调研.md", SRC / "端侧优化与容器化调研.md"),
        # ---- 二、测速数据 ----
        ("02-测速/部署总结.md", SRC / "部署总结.md"),
        ("02-测速/bench-server.ps1", SRC / "bench-server.ps1"),
        ("02-测速/bench-server.doc.md", SRC / "bench-server.doc.md"),
        # ---- 三、Home Assistant 构建 ----
        ("03-HomeAssistant构建/HomeAssistant构建文档.md", SRC / "HomeAssistant构建文档.md"),
        ("03-HomeAssistant构建/start-homeassistant.sh", SRC / "start-homeassistant.sh"),
        ("03-HomeAssistant构建/start-homeassistant.doc.md", SRC / "start-homeassistant.doc.md"),
        # ---- 附：环境与使用说明 ----
        ("04-参考/交接文档.md", SRC / "交接文档.md"),
        ("04-参考/README.md", SRC / "README.md"),
    ]
    # 树莓派那套测速方法与原始数据，作为跨平台对照
    if RPI and RPI.exists():
        for name in ("pi-bench.sh", "bench-report-raw.txt", "部署报告.md"):
            p = RPI / name
            if p.exists():
                items.append((f"05-树莓派对照/{name}", p))
    return items


def write_entry(z, arcname, data, mode=0o644):
    """写一个条目，并设置 UTF-8 文件名标志位（中文名不乱码的关键）。"""
    zi = zipfile.ZipInfo(arcname, date_time=datetime.now().timetuple()[:6])
    zi.flag_bits |= 0x800          # bit 11：文件名是 UTF-8
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = mode << 16  # .sh 传 0o755，其余 0o644
    z.writestr(zi, data)


def make_readme_txt():
    """生成包内说明文件的内容，讲清每份文档解决什么问题。"""
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    return f"""手机端推理与 Home Assistant · 调研与构建文档包
打包时间：{stamp}
设备：华为 Pura 70 Pro+（HBN-AL80），Kirin 9010，Android 12，16 GB

================================================================
这个包里有什么，分别回答什么问题
================================================================

01-GPU与NPU调研/
  提速调研报告.md
      为什么 GPU 和 NPU 在这台机器上用不了，以及真正有效的提速手段是什么。
      核心结论：decode 阶段是内存带宽受限，NPU 在 decode 上反而不如 CPU
      （清华与北交大的跨层测量研究提出「相位拆分」）；Maleoon GPU 官方
      无可用构建且上游仍在修崩溃。
      含实测：换 0.6B 模型后 decode 快 2.4~3.0 倍、温升降 44%、每瓦高 4 倍；
      以及热降频把速度从 22.6 t/s 打到 5.6 t/s 的完整证据链。

  端侧优化与容器化调研.md
      剪枝等模型压缩方法的原理，以及为什么剪枝对这个场景不是正确工具。
      核心原理：剪枝减少的是乘加次数（FLOPs），不减少字节流量；
      而 decode 是内存带宽受限，且 llama.cpp 在 Android 上没有稀疏 kernel。
      第二部分讲手机部署 Docker 的可行性，并附本次 proot 方案的实证结果。

02-测速/
  部署总结.md
      项目全过程记录：构建路线、验收结果、分段计时实测、热降频数据。
   bench-server.ps1 + bench-server.doc.md
      分段计时工具。把 llama-server 埋在 JSON 里的 timings 拎出来，
      显示 prefill（提示处理）与 decode（生成）各自的速度，并计算 TTFT。
      文档含真机实测输出与两个环境坑（adb 转发不持久、中文提示词编码）。

03-HomeAssistant构建/
  HomeAssistant构建文档.md
      在手机上不用 Docker、不需要 root 跑起 Home Assistant 的完整过程。
      含最终架构图、8 个构建步骤、6 个实际踩到的坑、验证记录与已知限制。
      结论：HA Core 2026.2.3 已成功运行。
  start-homeassistant.sh + start-homeassistant.doc.md
      启停脚本。文档重点讲清「为什么必须用 Termux 侧的 setsid」——
      proot 的 --kill-on-exit 会让容器内 fork 出的进程全部阵亡，
      脱离动作必须发生在被 kill 的那一层之外。

04-参考/
  交接文档.md    手机端大模型部署的总入口：启停命令、两个模型怎么选、注意事项
  README.md      使用说明：三种使用方式、参数、常见问题

05-树莓派对照/（若打包时提供了树莓派目录）
  pi-bench.sh          树莓派上的基准采集脚本，可复用到其他平台
  bench-report-raw.txt 树莓派实测原始输出（Cortex-A72 4 核 1.8GHz）
  部署报告.md           树莓派部署与性能报告

================================================================
关键数字速查
================================================================

内存带宽对比（决定生成速度的物理上限）
  Kirin 9010    LPDDR5X 4266MHz   理论 68.2 GB/s   实测有效约 25.3 GB/s（37%）
  Raspberry Pi4 LPDDR4-3200       实测有效约 4.24 GB/s

生成速度（同一台手机，受温度影响极大）
  1.5B Q4_K_M   冷态 18~22 t/s    持续压测 9.9~12.8 t/s   热保护触发 5.6 t/s
  0.6B Q4_K_M   冷态 49~52 t/s    温升仅 +18°C

热降频证据
  SoC 15 秒内从 46°C 冲到 73°C
  cpu7 频率上限被从 2.30GHz 依次压到 2.05 → 1.96 → 0.335 GHz

Home Assistant
  HA Core 2026.2.3 / Python 3.13.5 / Debian 13 trixie / proot 容器
  hass-venv 1.1 GB，可用内存 6.39 GB，日志零错误

================================================================
需要注意的前提
================================================================
所有数据都是这一台机器上的实测值，换机型结论可能不成立。
文档中区分了「已验证的事实」与「基于现象的推断」，引用时请留意标注。
"""


def main():
    """命令行入口：读清单、写说明文件、逐个写入条目、报告缺失项。"""
    items = build_manifest()
    missing = []

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # 说明文件放最前，打开压缩包第一眼就能看到
        write_entry(z, "说明.txt", make_readme_txt().encode("utf-8"))

        for arcname, path in items:
            if not path.exists():
                missing.append(str(path))
                continue
            # .sh 标记为可执行，解压后无需再 chmod
            mode = 0o755 if path.suffix == ".sh" else 0o644
            write_entry(z, arcname, path.read_bytes(), mode)

    print(f"生成 {OUT}  ({OUT.stat().st_size} 字节)")
    if missing:
        print("缺失（已跳过）:")
        for m in missing:
            print("  " + m)


if __name__ == "__main__":
    main()
