#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""collect.py —— 按产出日期归档：把各工程里的文档与配套脚本收进 Tojmpdoc。

输入：
    PROJECTS 表里声明的本机源工程目录（D:\\项目\\simuhome-ljb、D:\\项目\\树莓派、D:\\项目\\手机部署）。
输出：
    Tojmpdoc/<MMDD>/doc/<工程>/<原相对路径>   复制过来的文件（保留原始修改时间）
    Tojmpdoc/<MMDD>/README.md                 当天索引（含文件清单）
    Tojmpdoc/source.md                        未入库内容的登记表

判定规则（详见 tools/collect.md）：
    1. 只收文档与配套脚本/配置/小体量数据，脚本的扩展名白名单见 TEXT_EXTS。
    2. 单个文本文件超过 SIZE_LIMIT_TEXT、单个压缩包超过 SIZE_LIMIT_ARCHIVE 的一律不收，登记进 source.md。
    3. 第三方源码、浏览器 profile、运行时日志、运行时数据库、离线安装包按路径排除，登记进 source.md。
    4. 含本机口令的文件按路径排除，登记进 source.md。
    5. 日期取文件自身的修改时间；源工程里有一批文件的时间戳是 git 检出时间（不是产出时间），
       这类路径用 date_rules 直接写死日期。

用法：
    python tools\\collect.py             # 实际归档
    python tools\\collect.py --dry-run   # 只打印将要复制和跳过的内容，不落盘
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

# 本仓库根目录（tools 的上一级）
REPO_ROOT = Path(__file__).resolve().parents[1]

# 收录的文本类扩展名：文档优先，其次是与文档同名的配套脚本/配置
TEXT_EXTS = {
    ".md", ".py", ".ps1", ".sh", ".cmd", ".bat", ".json", ".yaml", ".yml",
    ".txt", ".tsv", ".csv", ".reg", ".html", ".sql", ".jsonl",
    # 运行时日志只收实验记录类的小文件；HA / broker / 音箱桥的常驻日志已按路径排除
    ".log",
}
# 收录的压缩包扩展名（交付给用户的文档包/实测包）
ARCHIVE_EXTS = {".zip"}

# 单文件体积上限：文本 512 KB，压缩包 2 MB
SIZE_LIMIT_TEXT = 512 * 1024
SIZE_LIMIT_ARCHIVE = 2 * 1024 * 1024

# 每个日期目录的一句话主题，写进 <MMDD>/README.md 的首行
DATE_NOTES = {
    "0929": "树莓派 4B 的 SD 卡烧录脚本（raw-write / write-image）",
    "0930": "树莓派部署报告与 CPU 基准（pi-bench、bench-report-raw）",
    "1002": "树莓派上的 HomeAssistant 容器部署记录与 MCP demo",
    "1003": "安卓手机 Termux + llama.cpp 的调研、方案与脚本（第一版文档包）",
    "1004": "V2 接入小米后的设计方案：记忆模块、时间调度、交付接口（来源为 finally new paper 的 10_04 目录）",
    "1009": "手机端性能实测（CPU / GPU-NPU 探测与报告）、交接文档、四模型对比",
    "1010": "智能家居部署文档（deploy 五份）、跨会话上下文总结、本地工具脚本、layered 接入记录 01-06",
    "1012": "MQTT broker、蓝牙音箱桥、米家 / 美的 / BLE / Zigbee 探测、大模型经 MCP 的 E 路线实测",
    "1013": "端侧前缀缓存测评方案与实测数据；树莓派有线直连排障手册",
    "1014": "端侧方案 B（房间信息前置）与交接包；手机提速调研、复现手册与真机实测结果",
    "1015": "三台设备（氛围灯 / 美的温湿度计 / 涂鸦 Zigbee）接入情况；手机端五模型同场测速与答案质量排名（Redmi K70E）",
}

# 外部仓库指针：不在本仓库内，单独有 git 远端
EXTERNAL_REPOS = [
    (r"D:\项目\autodl-tmp", "https://github.com/juezhan340/autodl-tmp.git",
     "科研主线文档仓库（训练数据、接口交接、UbiComp 讨论等），文件时间戳被 git 检出覆盖，无法按日期归档，未并入"),
    (r"D:\项目\simuhome-ljb", "https://github.com/Mr-luo-q/simuhome-ljb.git",
     "智能家居工程本体：代码、部署脚本、MQTT/MCP 工程、论文资料。本仓库只镜像它的文档"),
]

# 源工程表
PROJECTS = [
    {
        "key": "simuhome-ljb",
        "root": Path(r"D:\项目\simuhome-ljb"),
        "scan": ["_work", "deploy", "context", "_tools", "finally new paper"],
        "exclude": [
            r"^_work/(chrome-ha-profile|edge-ha-profile)/",   # 浏览器用户数据
            r"^_work/logs/",                                   # 运行时日志
            r"^_work/llm/(extract|extract202|removed_extended_openai_conversation)/",  # 第三方组件源码
            r"^_work/llm/.*\.(zip|log)$",                      # 第三方组件包与探针日志
            r"^_work/midea/(extract/|midea_auto_cloud-master\.zip$)",  # 第三方组件源码
            r"^_work/pi/wheels/",                              # 树莓派离线 wheel 包
            r"^_work/.*/logs/",                                # broker / bt_speaker 运行时日志
            r"^_work/mcp/data/.*\.db",                         # MCP 运行时数据库
            r"^_work/bt_speaker/media/",                       # 提示音素材
            r"__pycache__/",
            r"\.pyc$",
        ],
        # 这批文件的时间戳是 git 检出时间（2026-10-10 21:34），不是产出时间
        "date_rules": [
            (r"^finally new paper/10_04V2接入小米后设计方案/", "1004"),
            (r"^(finally new paper|deploy|context|_tools)/", "1010"),
        ],
    },
    {
        "key": "树莓派",
        "root": Path(r"D:\项目\树莓派"),
        "scan": ["."],
        "exclude": [
            r"^\.git/",
            r"^\.memorax-code/",
            r"^cloud-init/",                # 系统镜像自带的 cloud-init 模板
            r"^bootfs-user-data-patch/",    # 含热点 psk
            r"^树莓派配置记录\.md$",          # 含树莓派与热点口令
            r"__pycache__/",
        ],
        "date_rules": [],
    },
    {
        "key": "手机部署",
        "root": Path(r"D:\项目\手机部署"),
        "scan": ["."],
        "exclude": [
            r"^\.git/",
            r"^\.memorax-code/",
            r"^\.docs-html/",               # 由 md 生成的手机端 HTML，内容重复
            r"^tools/platform-tools/",      # Android 官方工具二进制
            r"__pycache__/",
        ],
        "date_rules": [],
    },
]

# 入库前脱敏表：本机设备口令会被顺手写进文档里，归档副本按下面的规则统一替换，本机原件不动。
# 规则对每个复制过来的文本文件都跑一遍，命中才写回，所以新增文档不用逐份登记。
# 每一项是 (正则, 替换, 说明)。
GLOBAL_REDACT = [
    (r"ha12345678", "<HA登录口令已脱敏>", "Home Assistant 登录口令"),
    (r'password\s*[:=]\s*"password"', 'password="<口令已脱敏>"', "树莓派 SSH 登录口令（默认弱口令）"),
    (r"(WPA2\s*/\s*)\d{5,}", r"\1<热点口令已脱敏>", "手机热点口令"),
    (r"(热点\s*`smp`\s*/\s*`)\d{5,}(`)", r"\1<热点口令已脱敏>\2", "手机热点口令"),
    (r"(\|\s*登录\s*\|\s*`pi`\s*/\s*`)[^`]+(`)", r"\1<口令已脱敏>\2", "树莓派 SSH 登录口令（速查表）"),
]

# 未入库内容登记表：(来源工程, 相对路径, 原因)。路径可以是目录，也可以是单个文件。
UNTRACKED = [
    ("simuhome-ljb", r"_work\chrome-ha-profile", "浏览器用户数据（登录态），可再生成"),
    ("simuhome-ljb", r"_work\edge-ha-profile", "浏览器用户数据（登录态），可再生成"),
    ("simuhome-ljb", r"_work\logs", "HA / MQTT 等运行时日志"),
    ("simuhome-ljb", r"_work\llm\extract", "HACS 组件解压出来的第三方源码"),
    ("simuhome-ljb", r"_work\llm\extract202", "HACS 组件解压出来的第三方源码"),
    ("simuhome-ljb", r"_work\llm\removed_extended_openai_conversation", "撤除前的第三方组件副本"),
    ("simuhome-ljb", r"_work\llm\ext-2.0.2.zip", "第三方组件安装包"),
    ("simuhome-ljb", r"_work\llm\ext-2.0.3.zip", "第三方组件安装包"),
    ("simuhome-ljb", r"_work\midea\extract", "第三方 midea_auto_cloud 源码"),
    ("simuhome-ljb", r"_work\midea\midea_auto_cloud-master.zip", "第三方组件安装包"),
    ("simuhome-ljb", r"_work\pi\wheels", "树莓派离线 wheel 安装包"),
    ("simuhome-ljb", r"_work\broker\logs", "MQTT broker 运行时日志"),
    ("simuhome-ljb", r"_work\bt_speaker\logs", "蓝牙音箱桥运行时日志"),
    ("simuhome-ljb", r"_work\bt_speaker\media\announce.wav", "提示音素材"),
    ("simuhome-ljb", r"_work\mcp\data\schedules.db*", "MCP 运行时 SQLite 数据库"),
    ("simuhome-ljb", r"finally new paper\**\*.png", "论文资料里的截图，正文 md 里用相对路径引用"),
    ("树莓派", r"cloud-init", "系统镜像自带模板"),
    ("树莓派", r"bootfs-user-data-patch", "含手机热点 psk 的修补脚本"),
    ("树莓派", r"树莓派配置记录.md", "含树莓派与热点口令，文档自身要求不入 git"),
    ("手机部署", r".docs-html", "由 markdown 生成的手机端 HTML，内容与 md 重复"),
    ("手机部署", r"tools\platform-tools", "Android 官方 platform-tools 二进制"),
]


def human(size: int) -> str:
    """把字节数转成便于阅读的字符串。"""
    if size >= 1024 * 1024:
        return f"{size / 1024 / 1024:.1f} MB"
    if size >= 1024:
        return f"{size / 1024:.1f} KB"
    return f"{size} B"


def dir_stats(path: Path) -> tuple[int, int]:
    """统计一个目录的体积（字节）与文件数；文件则返回它自己。"""
    if path.is_file():
        return path.stat().st_size, 1
    total, count = 0, 0
    for item in path.rglob("*"):
        if item.is_file():
            total += item.stat().st_size
            count += 1
    return total, count


def is_excluded(rel: str, patterns: list[str]) -> bool:
    """相对路径是否命中任一排除正则。"""
    return any(re.search(pattern, rel) for pattern in patterns)


def size_limit(ext: str) -> int:
    """按扩展名给出的单文件体积上限。"""
    return SIZE_LIMIT_ARCHIVE if ext in ARCHIVE_EXTS else SIZE_LIMIT_TEXT


def pick_date(project: dict, rel: str, mtime: datetime) -> str:
    """决定一个文件归到哪个日期：先看 date_rules，再看文件自身的修改时间。"""
    for pattern, date in project["date_rules"]:
        if re.search(pattern, rel):
            return date
    return mtime.strftime("%m%d")


def scan_project(project: dict) -> tuple[list[dict], list[dict]]:
    """扫描一个源工程，返回（要复制的文件列表，因体积超限被跳过的文件列表）。"""
    root: Path = project["root"]
    picked: list[dict] = []
    oversized: list[dict] = []
    for rel_dir in project["scan"]:
        base = root if rel_dir == "." else root / rel_dir
        if not base.exists():
            continue
        for src in sorted(base.rglob("*")):
            if not src.is_file():
                continue
            rel = src.relative_to(root).as_posix()
            if is_excluded(rel, project["exclude"]):
                continue
            ext = src.suffix.lower()
            if ext not in TEXT_EXTS and ext not in ARCHIVE_EXTS:
                continue
            stat = src.stat()
            record = {
                "project": project["key"],
                "rel": rel,
                "src": src,
                "size": stat.st_size,
                "mtime": datetime.fromtimestamp(stat.st_mtime),
            }
            if stat.st_size > size_limit(ext):
                oversized.append(record)
                continue
            picked.append(record)
    return picked, oversized


def dest_of(record: dict) -> Path:
    """一个文件在本仓库中的落点：<MMDD>/doc/<工程>/<原相对路径>。"""
    return REPO_ROOT / record["date"] / "doc" / record["project"] / record["rel"]


def copy_all(records: list[dict], dry_run: bool) -> list[tuple[str, str]]:
    """按记录把文件复制到本仓库，保留原始修改时间；复制后统一跑一遍脱敏。"""
    hits: list[tuple[str, str]] = []
    for record in records:
        dest = dest_of(record)
        if dry_run:
            print(f"[copy] {record['src']}  ->  {dest.relative_to(REPO_ROOT)}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(record["src"], dest)
        hits.extend(redact_file(dest, f"{record['date']}/doc/{record['project']}/{record['rel']}"))
    return hits


def redact_file(dest: Path, label: str) -> list[tuple[str, str]]:
    """对一个归档副本跑 GLOBAL_REDACT，返回 (文件, 说明) 命中列表；按字节读写，不动其它内容。"""
    if dest.suffix.lower() not in TEXT_EXTS:
        return []
    text = dest.read_bytes().decode("utf-8", errors="replace")
    hits: list[tuple[str, str]] = []
    for pattern, repl, note in GLOBAL_REDACT:
        text, count = re.subn(pattern, repl, text)
        if count:
            hits.append((label, note))
    if hits:
        dest.write_bytes(text.encode("utf-8"))
    return hits


def redact_repo(dry_run: bool) -> list[tuple[str, str]]:
    """对整个仓库里已有的文本文件再跑一遍脱敏，清掉早先快照留下的口令残留。

    tools/ 和 .git/ 跳过：脚本自己就写着这些口令的正则，改它会把规则弄坏。
    """
    if dry_run:
        return []
    hits: list[tuple[str, str]] = []
    for path in sorted(REPO_ROOT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(REPO_ROOT).as_posix()
        if rel.startswith(("tools/", ".git/")):
            continue
        hits.extend(redact_file(path, rel))
    return hits


def write_date_readme(date: str, records: list[dict], dry_run: bool) -> None:
    """生成某个日期目录下的 README.md，作为当天的索引。"""
    lines = [f"# {date}", ""]
    note = DATE_NOTES.get(date)
    if note:
        lines += [f"主题：{note}", ""]
    lines += [
        f"当天归档 {len(records)} 个文件，来自 "
        + "、".join(sorted({r["project"] for r in records}))
        + "。“原路径”是它在来源工程里的位置。",
        "",
    ]
    for project in sorted({r["project"] for r in records}):
        rows = sorted([r for r in records if r["project"] == project], key=lambda r: r["rel"])
        lines += [f"## {project}（{len(rows)}）", "", "| 文件 | 原路径 | 大小 |", "| --- | --- | --- |"]
        for row in rows:
            name = Path(row["rel"]).name.replace("|", "\\|")
            target = (f"doc/{row['project']}/{row['rel']}").replace(" ", "%20")
            lines.append(f"| [{name}](<{target}>) | `{row['rel']}` | {human(row['size'])} |")
        lines.append("")
    if dry_run:
        return
    target = REPO_ROOT / date / "README.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines), encoding="utf-8")


def write_source_md(oversized: list[dict], redact_hits: list[tuple[str, str]], dry_run: bool) -> None:
    """生成 source.md：登记所有没进仓库的内容。"""
    lines = [
        "# source.md",
        "",
        "本文件由 `tools/collect.py` 生成，登记**没有进这个仓库**的东西：体积大的、第三方的、"
        "或者含本机口令的。需要时按路径回本机取，不用从仓库里找。",
        "",
        # 生成时间单独插，方便「内容没变就不重写」的比对
        "@@生成时间@@",
        "",
        "## 1. 按路径排除，未入库",
        "",
        "| 来源工程 | 路径 | 体积 | 文件数 | 原因 |",
        "| --- | --- | --- | --- | --- |",
    ]
    project_roots = {p["key"]: p["root"] for p in PROJECTS}
    for project, rel, reason in UNTRACKED:
        base = project_roots[project]
        # 相对路径里可以带通配符（例如 finally new paper\**\*.png）
        pattern = rel.replace("\\", "/")
        if any(ch in pattern for ch in "*?["):
            hits = sorted(base.glob(pattern))
        else:
            candidate = base / Path(*pattern.split("/"))
            hits = [candidate] if candidate.exists() else []
        if hits:
            stats = [dir_stats(hit) for hit in hits]
            size_text = human(sum(s for s, _ in stats))
            count_text = str(sum(c for _, c in stats))
        else:
            size_text, count_text = "-", "-"
        lines.append(f"| {project} | `{rel}` | {size_text} | {count_text} | {reason} |")

    lines += ["", "## 2. 单文件体积超过上限，未入库", ""]
    if oversized:
        lines += ["| 来源工程 | 路径 | 体积 |", "| --- | --- | --- |"]
        for record in sorted(oversized, key=lambda r: r["size"], reverse=True):
            lines.append(f"| {record['project']} | `{record['rel']}` | {human(record['size'])} |")
    else:
        lines.append("（本次没有超限文件）")

    lines += ["", "## 3. 另有 git 远端的仓库，未并入", "", "| 本地路径 | 远端 | 说明 |", "| --- | --- | --- |"]
    for path, remote, note in EXTERNAL_REPOS:
        lines.append(f"| `{path}` | {remote} | {note} |")

    lines += [
        "",
        "## 4. 入库时脱敏",
        "",
        "写文档时顺手记进去的本机口令，在仓库里的**副本**已经按 `tools/collect.py` 的 `GLOBAL_REDACT` "
        "替换成 `<...已脱敏>`，本机原件一个字没动。",
        "",
    ]
    if redact_hits:
        lines += ["| 本仓库里的文件 | 替换掉的内容 |", "| --- | --- |"]
        for where, note in redact_hits:
            lines.append(f"| `{where}` | {note} |")
    else:
        lines.append("（本次没有命中）")

    lines += [
        "",
        "## 5. 重新生成",
        "",
        "```powershell",
        "cd D:\\项目\\Tojmpdoc",
        "python tools\\collect.py",
        "```",
        "",
    ]
    body = "\n".join(lines)
    stamp = f"生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M')}（本机 `D:\\项目`）"
    # 内容（除生成时间外）没变就不重写，重复运行不会把 source.md 弄脏
    target = REPO_ROOT / "source.md"
    if target.exists():
        old = target.read_text(encoding="utf-8")
        if re.sub(r"生成时间：[^\n]*", "", old) == body.replace("@@生成时间@@", ""):
            return
    if dry_run:
        return
    target.write_text(body.replace("@@生成时间@@", stamp), encoding="utf-8")


def main() -> int:
    """入口：扫描 → 复制 → 写索引与登记表。"""
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="按日期归档文档到 Tojmpdoc")
    parser.add_argument("--dry-run", action="store_true", help="只打印动作，不写文件")
    args = parser.parse_args()

    records: list[dict] = []
    oversized: list[dict] = []
    for project in PROJECTS:
        if not project["root"].exists():
            print(f"[warn] 源目录不存在，跳过：{project['root']}")
            continue
        picked, over = scan_project(project)
        for record in picked:
            record["date"] = pick_date(project, record["rel"], record["mtime"])
        records.extend(picked)
        oversized.extend(over)
        print(f"[scan] {project['key']}: 收录 {len(picked)}，跳过超限 {len(over)}")

    # 两遍脱敏：新复制的副本，以及仓库里早先留下的快照
    redact_hits = copy_all(records, args.dry_run) + redact_repo(args.dry_run)
    seen: set[tuple[str, str]] = set()
    redact_hits = [hit for hit in redact_hits if not (hit in seen or seen.add(hit))]

    by_date: dict[str, list[dict]] = {}
    for record in records:
        by_date.setdefault(record["date"], []).append(record)
    for date in sorted(by_date):
        write_date_readme(date, by_date[date], args.dry_run)
    write_source_md(oversized, redact_hits, args.dry_run)

    for date in sorted(by_date):
        print(f"[date] {date}: {len(by_date[date])} 个文件")
    print(f"[done] 共 {len(records)} 个文件，{len(by_date)} 个日期目录"
          + ("（dry-run，未落盘）" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
