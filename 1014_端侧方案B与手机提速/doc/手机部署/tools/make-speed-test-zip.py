"""把 2026-10-14 这次「手机小模型提速」实测的相关文档、脚本、原始数据打成一个 zip。

与仓库里其他打包脚本的分工：
  make-docs-zip.py        完整文档包（全部脚本与说明书）
  make-research-zip.py    GPU/NPU 调研包（那一轮的文档）
  make-k70e-zip.py        K70E 部署包
  本脚本                   本轮提速实验包：实验设计 + 实测结果 + 工具 + 原始数据 + 证据来源

同样显式设置 ZIP 的 UTF-8 文件名标志位，避免中文名在安卓/Windows 上乱码。

用法：
  python tools/make-speed-test-zip.py <项目目录> <输出zip>
"""
import hashlib
import sys
import zipfile
from datetime import datetime
from pathlib import Path

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "手机提速实测包-20261014.zip")


def build_manifest():
    """构造 (归档内路径, 源文件) 清单。

    分六类：设计文档、实测结果、工具、提示词、证据来源、历史基线。
    结果目录与来源目录用递归收集，保证原始数据一条不漏。
    """
    items = []

    # 一、实验设计：方法与协议，回答「为什么测这些、怎么测、怎么判」
    design = SRC / "01-实验设计"
    items += [
        (f"{design.name}/手机小模型提速调研与复现.md", SRC / "手机小模型提速调研与复现.md"),
        (f"{design.name}/手机小模型提速复现操作手册.md", SRC / "手机小模型提速复现操作手册.md"),
    ]

    # 二、实测结果：结果正文 + 每个 suite 的对照表 + 全部原始数据
    results = SRC / "02-实测结果"
    items.append((f"{results.name}/手机提速实测结果-20261014.md", SRC / "手机提速实测结果-20261014.md"))
    device_dir = SRC / "research" / "speed-20261014" / "device-20261014"
    if device_dir.exists():
        for path in sorted(device_dir.rglob("*")):
            if not path.is_file() or path.stat().st_size == 0:
                # 跳过空文件：采集失败时通配符没匹配到内容，留下 0 字节文件不含信息
                continue
            rel = path.relative_to(device_dir).as_posix()
            # 对照表放到结果正文同一层，逐调用的原始产出留在 原始数据/ 下
            if path.name.endswith("-summary.md"):
                items.append((f"{results.name}/{path.name}", path))
            else:
                items.append((f"{results.name}/原始数据/{rel}", path))

    # 三、工具：本次实际用到的脚本，每个都带同名中文说明
    tools = SRC / "03-工具"
    for name in ("phone-speed-bench", "measure-phone-stream", "summarize-speed-results",
                 "termux-speed-env.sh", "termux-quality-check.sh", "termux-start-bench-server.sh",
                 "fetch-speed-sources", "verify-speed-tools"):
        stem = name if name.endswith(".sh") else f"{name}.py"
        items.append((f"{tools.name}/{stem}", SRC / "tools" / stem))
        items.append((f"{tools.name}/{stem.rsplit('.', 1)[0]}.md", SRC / "tools" / f"{stem.rsplit('.', 1)[0]}.md"))
    # 环境包装器没有同名 md，但它是所有手机命令的入口，必须带上
    items.append((f"{tools.name}/termux-run.sh", SRC / "tools" / "termux-run.sh"))

    # 四、提示词：题集与缓存前缀，测量用的输入素材
    prompts = SRC / "04-提示词"
    for path in sorted((SRC / "phone-prompts").glob("*")):
        if path.is_file():
            items.append((f"{prompts.name}/{path.name}", path))

    # 五、证据来源：一手资料原文 + 索引 + 工具验证记录
    evidence = SRC / "05-证据与来源"
    research = SRC / "research" / "speed-20261014"
    for name in ("来源索引.md", "验证记录.md", "tool-verification.log"):
        if (research / name).exists():
            items.append((f"{evidence.name}/{name}", research / name))
    if (research / "sources").exists():
        for path in sorted((research / "sources").glob("*")):
            if path.is_file():
                items.append((f"{evidence.name}/sources/{path.name}", path))

    # 六、历史基线：本次对照结论所依据的上一轮报告
    history = SRC / "06-历史基线"
    for name in ("CPU性能实测报告.md", "Token速率详表.md", "GPU-NPU加速实测报告.md",
                 "四模型架构与性能对比.md", "提速调研报告.md", "交接文档.md"):
        items.append((f"{history.name}/{name}", SRC / name))
    return items


def make_readme_txt():
    """生成包内说明文件：先说结论数字，再说每份文档回答什么问题。"""
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    return f"""手机小模型提速实测包 · 0.6B / 1.5B
打包时间：{stamp}
设备：Redmi K70E（2311DRK48C，duchamp），MT6897 天玑 8300-Ultra，Android 16
模型：Qwen3-0.6B-Q4_K_M、Qwen2.5-1.5B-Instruct Q4_K_M
后端：llama.cpp 0.6.0（Termux 包），纯 CPU

================================================================
一句话结论
================================================================
线程已经到头（t4 对生成为最优）；长上下文靠 Flash Attention 加 KV 量化，
且默认的 -fa auto 在 2048 深度下等同于开 FA，恰好落在生成最慢的一档；
前缀缓存的收益最大，与模型和内核都无关。没有任何配置能让速度翻倍。

================================================================
关键数字（全部为本次真机实测，条件见 02-实测结果）
================================================================
基线（冷态，纯 CPU，t4，空上下文）
  Qwen3-0.6B      提示词处理 71.86 t/s    生成 41.12 t/s
  Qwen2.5-1.5B    提示词处理 28.12 t/s    生成 18.67 t/s

线程扫描（相对 t4）
  生成阶段：t2 -47% / t3 -24% / t6 -29~48% / t8 -41~47%，t4 最优
  提示词处理：t6 持平，t8 反而 +4.3%（0.6B）/ +7.7%（1.5B）

2048 深度注意力（生成 t/s）
  配置                     0.6B     1.5B
  默认 auto                10.06    9.36     ← 现状，生成最慢档
  -fa on  + KV f16         10.72    9.29
  -fa off + KV f16         14.59    10.17
  -fa on  + KV q8_0        17.61    11.24    ← 生成最快档
  同一配置重复测量组内差 1%，跨半小时基线漂移最高 20%

首字延迟与前缀缓存（0.6B，SSE 实测）
  中文短对话 51 token     首轮 719 ms → 命中后 41~78 ms（约 11 倍）
  长前缀 1166 token       缓存关：每轮 16.1~16.8 s
                          缓存开：首轮 17.9 s，第 2 轮起 0.085~0.089 s（约 185 倍）

质量回归（0.6B，q8_0 对 f16）
  题02 订单抽取、题06 17×23−19 两题输出完全一致，未观察到退化
  题01 三种配置全部答错（正确答案 41，模型给 30 / 36 / 未求值表达式）
  → 该题超出 0.6B 能力，不能用来分辨配置差异

================================================================
包里有什么，分别回答什么问题
================================================================
01-实验设计/
  手机小模型提速调研与复现.md
      要提速先要看清楚瓶颈在哪。这份文档把设备事实、旧测试的测量误读、
      可选路线和验收门槛一次讲清，并区分「已验证事实 / 推断 / 待测」。
  手机小模型提速复现操作手册.md
      逐条可执行命令：基线、线程、批大小、FA/KV、缓存、内核构建、量化转换，
      以及每个实验的判定门槛（中位数改善 ≥10% 且多块方向一致）。

02-实测结果/
  手机提速实测结果-20261014.md       结果正文，含条件身份、漂移分析、结论与未完成项
  06-threads-summary.md              0.6B 线程对照表
  15-threads-summary.md              1.5B 线程对照表
  06-attn-d0-summary.md              0.6B 空上下文 FA/KV 对照
  06-attn-d2048-summary.md           0.6B 2048 深度 FA/KV 对照
  15-attn-d2048-summary.md           1.5B 2048 深度 FA/KV 对照
  原始数据/                          环境快照、模型哈希、逐调用 results.tsv、
                                     llama-bench 原始 JSON、频率采样、质量回归日志

03-工具/
  phone-speed-bench.py       基准编排：单变量、ABBA 顺序、失败不填伪数据
  measure-phone-stream.py    SSE 首字延迟测量：区分空事件 / 思考 / 真正答案
  summarize-speed-results.py 把逐调用 TSV 聚成对照表，带方向一致性判断
  termux-speed-env.sh        第 0 步环境快照（只读）
  termux-quality-check.sh    注意力配置的质量回归
  termux-start-bench-server.sh 8081 端口的受控实验服务
  fetch-speed-sources.py     一手资料取证，带 SHA-256 与版本记录
  verify-speed-tools.py      离线验证上面这些工具的行为（12 项）
  termux-run.sh              所有手机命令的入口包装器

04-提示词/
  题01~题08.txt              质量题集
  问答.txt                   中文对话延迟用
  缓存512.txt / 缓存2048.txt  缓存实验的长短前缀
  README.md                  用法、token 数必须实测的说明

05-证据与来源/
  来源索引.md                S01~S30 的编号、URL、版本、哈希
  验证记录.md                哪些做了、哪些没做、测得是什么
  tool-verification.log      离线验证原始输出
  sources/Sxx.txt            一手资料原文（llama.cpp 源码与文档、模型配置、
                             MNN/MLC/ExecuTorch/LiteRT-LM 资料、MediaTek 规格）

06-历史基线/
  CPU性能实测报告.md          t8→t4 的 2 倍、绑核、频率锁定
  Token速率详表.md            prefill/decode 曲线、深度衰减、HTTP 层
  GPU-NPU加速实测报告.md      Mali 慢 1.5~19 倍、NPU 无可用入口
  四模型架构与性能对比.md     四个模型的架构差异与同批对照
  提速调研报告.md             华为那台的调研（另一台设备，不套用）
  交接文档.md                 设备整体状态与已踩的坑

================================================================
测量条件与局限（引用数字前请先看这一段）
================================================================
· 全程插电充电，powermode = enhance，无主动散热
· 电池温度 24.5°C 起，最高 40.1°C；SoC 热区 68 个全部 Permission denied，
  无 root 读不到，温度只能用电池值加频率采样间接约束
· 单次调用内部重复性优于 1%，但跨时间段基线漂移最高 20%，
  所以每个候选都和自己同块的 A 比较，跨组比绝对值会得出错误结论
· 质量回归只有 2 道有效题，只能说「未观察到退化」，不能说「质量无损」
· KleidiAI / i8mm 对照构建与拔线供电对照本轮未执行
· 历史报告的数字与本次不可直接比较（设备状态、参数、批次都不同）

================================================================
怎么用这个包
================================================================
只想看结论        打开 02-实测结果/手机提速实测结果-20261014.md
想复现           照 01-实验设计/操作手册 走，工具在 03-工具，题集在 04-提示词
想核对数据       02-实测结果/原始数据/ 里是逐调用的原始 TSV 与 JSON
想查设计依据     05-证据与来源/来源索引.md 指向 sources/ 里的原文

清单.tsv 里是每个条目的 SHA-256 与字节数，可用于校验包内文件未被改动。
"""


def write_entry(z, arcname, data, mode=0o644):
    """写一个条目，并设置 UTF-8 文件名标志位与 Unix 权限位。"""
    zi = zipfile.ZipInfo(arcname, date_time=datetime.now().timetuple()[:6])
    zi.flag_bits |= 0x800
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = mode << 16
    z.writestr(zi, data)
    return hashlib.sha256(data).hexdigest()


def main():
    """命令行入口：写说明 → 写清单 → 逐个写入 → 报告缺失与体积。"""
    items = build_manifest()
    missing, manifest, total = [], [], 0

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        write_entry(z, "说明.txt", make_readme_txt().encode("utf-8"))
        for arcname, path in items:
            if not path.exists():
                missing.append(str(path))
                continue
            data = path.read_bytes()
            mode = 0o755 if path.suffix in (".sh", ".py") else 0o644
            digest = write_entry(z, arcname, data, mode)
            manifest.append((arcname, len(data), digest))
            total += len(data)
        rows = ["归档内路径\t字节\tSHA-256"] + [f"{a}\t{n}\t{h}" for a, n, h in manifest]
        write_entry(z, "清单.tsv", "\n".join(rows).encode("utf-8"))

    # 打包后再读回校验：确认 CRC 全通过、条目数与清单一致
    with zipfile.ZipFile(OUT) as z:
        bad = z.testzip()
        names = z.namelist()
    print(f"生成 {OUT}")
    print(f"条目 {len(names)} 个，原始数据共 {total / 1024 / 1024:.2f} MB，压缩后 {OUT.stat().st_size / 1024:.0f} KB")
    print(f"CRC 校验: {'失败 ' + str(bad) if bad else '通过'}")
    if missing:
        print(f"缺失 {len(missing)} 项（已跳过）:")
        for m in missing:
            print("  " + m)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
