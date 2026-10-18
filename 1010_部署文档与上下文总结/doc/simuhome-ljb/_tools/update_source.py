r"""生成 source.md：登记本仓库跟踪的目录，以及未跟踪的大目录与它们的外部来源。

用法：python _tools\update_source.py
每次目录结构或外部依赖发生变化后跑一次，输出覆盖仓库根目录的 source.md。
"""

from __future__ import annotations

import datetime as dt
import fnmatch
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

# 本仓库跟踪的目录：写清用途，source.md 会按它生成第一张表
TRACKED: dict[str, str] = {
    "finally new paper": "论文讨论与设计文档、benchmark 与方法论文整理、架构图",
    "ha_mcp_server": "v1 MCP server（冻结，论文主实验口径）",
    "ha_mcp_universal": "v2 MCP server：通用化接入，8 个统一语义工具",
    "simuhome_mqtt_publisher": "MQTT 接入工程：broker 配置、发布器、实体改名脚本",
    "old_simuhome_bridge_project": "已退役的 SimuHome×HA 桥接工程（compose.yaml 历史版本）",
    "deploy": "部署文档组（MCP / 沙盒 / 米家三层）与通用版 HA compose",
    "_tools": "本地工具与探针：一键拉起脚本、MQTT broker 包（安装包与 wheels 不入库）",
    "context": "跨会话上下文与笔记",
}

# 不入库、但要在 source.md 里登记的大目录
REGISTERED: dict[str, str] = {
    "oldmcp": "已废弃的早期 MCP 实验（代码与文档，仅存档，不参与研究）",
    "ha_core_official": "Home Assistant Core 官方源码克隆（含 core 子仓库）",
    "simuprocject": "SimuHome 仿真内核源码（被控端本体）",
    "tdp-nlu-private-main": "外部项目副本：TDP-NLU 私有仓库",
    "sandbox": "外部项目副本：sandbox 实验目录",
    "related paper": "相关论文 PDF 与资料",
    "milocoproject": "外部项目副本：MILoco",
    "homebenchproject": "HomeBench 相关项目副本",
    "sageproject": "SAGE 相关项目副本",
    "qixuancai_papers": "论文 PDF 收集（当前为空）",
}

# 不入库的文件类型：登记名称与体积即可
IGNORED_GLOBS = ["*.pdf", "_tools/mqtt/*.exe", "_tools/mqtt/wheels/*"]

# 第 3 张表最多列多少个文件，其余只报数量，避免 source.md 过长
IGNORED_LIST_LIMIT = 40


def dir_stats(path: Path) -> tuple[float, int]:
    """返回目录的（大小 MB，文件数），忽略权限错误。"""

    total = 0
    count = 0
    for base, _dirs, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(base, name))
                count += 1
            except OSError:
                continue
    return total / 1024 / 1024, count


def find_nested_repo(path: Path, max_depth: int = 2) -> Path | None:
    """在目录内（限定深度）找一个带 .git 的子目录，用于登记外部来源。"""

    base_depth = len(path.parts)
    for base, dirs, _files in os.walk(path):
        if len(Path(base).parts) - base_depth >= max_depth:
            dirs[:] = []
            continue
        if ".git" in dirs:
            return Path(base)
    return None


def git_info(repo: Path) -> dict[str, str]:
    """读取子仓库的远端、分支与最近提交。"""

    def run(args: list[str]) -> str:
        try:
            out = subprocess.run(
                ["git", "-C", str(repo), *args],
                capture_output=True, text=True, timeout=20,
            )
            return out.stdout.strip()
        except Exception:  # noqa: BLE001
            return ""

    return {
        "remote": run(["remote", "get-url", "origin"]) or "(无远端)",
        "branch": run(["rev-parse", "--abbrev-ref", "HEAD"]) or "?",
        "commit": (run(["log", "-1", "--pretty=%h %ad", "--date=short"]) or "?"),
    }


def collect_ignored_files() -> list[tuple[str, float]]:
    """列出被忽略的大文件（PDF、安装包、wheel），用于登记。"""

    found: list[tuple[str, float]] = []
    for base, dirs, files in os.walk(ROOT):
        rel_base = os.path.relpath(base, ROOT).replace("\\", "/")
        if rel_base.startswith((".git", ".git_old")):
            dirs[:] = []
            continue
        for name in files:
            rel = f"{rel_base}/{name}" if rel_base != "." else name
            if not any(fnmatch.fnmatch(rel, pat) for pat in IGNORED_GLOBS):
                continue
            try:
                size = os.path.getsize(os.path.join(base, name)) / 1024 / 1024
            except OSError:
                continue
            found.append((rel, size))
    return sorted(found, key=lambda item: item[1], reverse=True)


def main() -> None:
    """扫描工作区并写出 source.md。"""

    lines: list[str] = []
    stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines.append("# source.md")
    lines.append("")
    lines.append(f"本文件由 `_tools/update_source.py` 自动生成，最后更新：{stamp}。")
    lines.append("")
    lines.append("仓库只跟踪下面第一张表里的目录；第二、三张表里的内容不入库，只登记来源与体积。")
    lines.append("")

    lines.append("## 1. 本仓库跟踪的目录")
    lines.append("")
    lines.append("| 目录 | 用途 | 大小 | 文件数 | 最后修改 |")
    lines.append("| --- | --- | --- | --- | --- |")
    for name, purpose in TRACKED.items():
        path = ROOT / name
        if not path.exists():
            lines.append(f"| `{name}` | {purpose} | — | — | 缺失 |")
            continue
        size, count = dir_stats(path)
        mtime = dt.datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
        lines.append(f"| `{name}` | {purpose} | {size:.1f} MB | {count} | {mtime} |")
    lines.append("")
    lines.append("表 1 的体积是磁盘占用；实际入库的内容不含 `.venv`、`.env`、PDF、安装包与 wheel，")
    lines.append("这些被忽略的文件在第 3 张表里登记。")
    lines.append("")

    lines.append("## 2. 不入库的外部目录（登记）")
    lines.append("")
    lines.append("| 目录 | 用途 | 大小 | 文件数 | 自带仓库 | 远端 / 版本 |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for name, purpose in REGISTERED.items():
        path = ROOT / name
        if not path.exists():
            lines.append(f"| `{name}` | {purpose} | — | — | — | 缺失 |")
            continue
        size, count = dir_stats(path)
        repo = find_nested_repo(path)
        if repo:
            info = git_info(repo)
            note = f"{info['remote']}（{info['branch']} @ {info['commit']}）"
            has_git = f"是（{repo.relative_to(ROOT)}）"
        else:
            has_git, note = "否", "(无版本信息)"
        lines.append(f"| `{name}` | {purpose} | {size:.1f} MB | {count} | {has_git} | {note} |")
    lines.append("")

    lines.append("## 3. 被忽略的大文件（登记）")
    lines.append("")
    ignored = collect_ignored_files()
    lines.append("| 文件 | 大小 |")
    lines.append("| --- | --- |")
    for rel, size in ignored[:IGNORED_LIST_LIMIT]:
        lines.append(f"| `{rel}` | {size:.1f} MB |")
    if len(ignored) > IGNORED_LIST_LIMIT:
        rest = sum(size for _rel, size in ignored[IGNORED_LIST_LIMIT:])
        lines.append(f"| （其余 {len(ignored) - IGNORED_LIST_LIMIT} 个小文件） | {rest:.1f} MB |")
    if not ignored:
        lines.append("| （无） | — |")
    lines.append("")

    lines.append("## 4. 重新生成")
    lines.append("")
    lines.append("```powershell")
    lines.append(r"C:\ProgramData\anaconda3\python.exe _tools\update_source.py")
    lines.append("```")
    lines.append("")

    (ROOT / "source.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"source.md 已更新：跟踪 {len(TRACKED)} 个目录，登记 {len(REGISTERED)} 个外部目录，"
          f"被忽略的大文件 {len(ignored)} 个")


if __name__ == "__main__":
    main()
