"""把项目 Markdown 文档转成手机友好的 HTML 页面。"""
import html
import re
import sys
from pathlib import Path

# ---------- 行内标记 ----------

def inline(text: str) -> str:
    """处理行内标记。先抽出行内代码，避免其中内容被二次处理。"""
    codes = []

    def stash(m):
        """把行内代码暂存到列表，返回占位符，避免其中内容被后续正则二次处理。"""
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)

    text = html.escape(text, quote=False)

    # 图片 ![alt](src)
    text = re.sub(
        r"!\[([^\]]*)\]\(([^)\s]+)\)",
        r'<img alt="\1" src="\2">',
        text,
    )
    # 链接 [text](url)
    text = re.sub(
        r"\[([^\]]+)\]\(([^)\s]+)\)",
        r'<a href="\2">\1</a>',
        text,
    )
    # 加粗 / 斜体
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*]+)\*(?![\w*])", r"<em>\1</em>", text)

    # 还原行内代码
    def unstash(m):
        """把占位符还原成 <code> 标签，内容在此处才做 HTML 转义。"""
        return f"<code>{html.escape(codes[int(m.group(1))])}</code>"

    text = re.sub(r"\x00(\d+)\x00", unstash, text)
    return text


# ---------- 表格 ----------

def is_table_sep(line: str) -> bool:
    """判断一行是否为 Markdown 表格的分隔行（形如 |---|---|），用于识别表格开始。"""
    return bool(re.match(r"^\s*\|?[\s:|-]+\|[\s:|-]*$", line)) and "-" in line


def split_row(line: str):
    """把表格的一行按 | 拆成单元格列表，并去掉首尾多余的空竖线。"""
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


# ---------- 主转换 ----------

def convert(md: str) -> tuple[str, list[tuple[int, str]]]:
    """把整篇 Markdown 逐行转成 HTML 片段，同时收集标题层级用于生成页面目录。

    返回 (HTML 正文, [(标题层级, 标题文本), ...])。
    """
    lines = md.split("\n")
    out: list[str] = []
    toc: list[tuple[int, str]] = []

    i = 0
    n = len(lines)
    in_ul = False
    in_ol = False

    def close_lists():
        """遇到非列表行时收尾，关闭尚未闭合的 <ul>/<ol>，保证标签配对。"""
        nonlocal in_ul, in_ol
        if in_ul:
            out.append("</ul>")
            in_ul = False
        if in_ol:
            out.append("</ol>")
            in_ol = False

    while i < n:
        line = lines[i]
        stripped = line.strip()

        # 代码块
        if stripped.startswith("```"):
            close_lists()
            lang = stripped[3:].strip()
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1  # 跳过结束的 ```
            code = html.escape("\n".join(buf))
            cls = f' class="lang-{html.escape(lang)}"' if lang else ""
            label = f'<span class="code-lang">{html.escape(lang)}</span>' if lang else ""
            out.append(f'<div class="codeblock">{label}<pre><code{cls}>{code}</code></pre></div>')
            continue

        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            close_lists()
            level = len(m.group(1))
            text = m.group(2).strip()
            anchor = "h-" + re.sub(r"[^\w\u4e00-\u9fff]+", "-", text).strip("-")
            out.append(
                f'<h{level} id="{anchor}">{inline(text)}'
                f'<a class="anchor" href="#{anchor}">#</a></h{level}>'
            )
            toc.append((level, text))
            i += 1
            continue

        # 分隔线
        if re.match(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$", line):
            close_lists()
            out.append("<hr>")
            i += 1
            continue

        # 表格
        if "|" in line and i + 1 < n and is_table_sep(lines[i + 1]):
            close_lists()
            header = split_row(line)
            i += 2
            rows = []
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(split_row(lines[i]))
                i += 1
            out.append('<div class="tablewrap"><table>')
            out.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in header) + "</tr></thead>")
            out.append("<tbody>")
            for r in rows:
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
            out.append("</tbody></table></div>")
            continue

        # 引用
        if stripped.startswith(">"):
            close_lists()
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip().lstrip(">").strip())
                i += 1
            out.append("<blockquote>" + inline(" ".join(buf)) + "</blockquote>")
            continue

        # 无序列表
        m = re.match(r"^\s*[-*+]\s+(.*)$", line)
        if m:
            if not in_ul:
                close_lists()
                out.append("<ul>")
                in_ul = True
            out.append(f"<li>{inline(m.group(1))}</li>")
            i += 1
            continue

        # 有序列表
        m = re.match(r"^\s*(\d+)[.)]\s+(.*)$", line)
        if m:
            if not in_ol:
                close_lists()
                out.append("<ol>")
                in_ol = True
            out.append(f"<li>{inline(m.group(2))}</li>")
            i += 1
            continue

        # 空行
        if not stripped:
            close_lists()
            i += 1
            continue

        # 普通段落
        close_lists()
        out.append(f"<p>{inline(stripped)}</p>")
        i += 1

    close_lists()
    return "\n".join(out), toc


CSS = """
:root {
  --bg: #ffffff; --fg: #24292f; --muted: #656d76; --border: #d0d7de;
  --code-bg: #f6f8fa; --accent: #0969da; --quote: #d8dee4;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --muted: #8b949e; --border: #30363d;
    --code-bg: #161b22; --accent: #58a6ff; --quote: #3d444d;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body {
  margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.75 -apple-system, "PingFang SC", "Noto Sans CJK SC",
        "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif;
  padding: 0 0 4rem;
}
.wrap { max-width: 900px; margin: 0 auto; padding: 0 16px; }
.topbar {
  position: sticky; top: 0; z-index: 10; backdrop-filter: blur(8px);
  background: color-mix(in srgb, var(--bg) 88%, transparent);
  border-bottom: 1px solid var(--border); padding: 10px 16px;
  display: flex; gap: 8px; align-items: center; flex-wrap: wrap;
}
.topbar a {
  color: var(--fg); text-decoration: none; font-size: 14px;
  padding: 5px 11px; border: 1px solid var(--border); border-radius: 999px;
}
.topbar a.active { background: var(--accent); border-color: var(--accent); color: #fff; }
.topbar .spacer { flex: 1; }
h1, h2, h3, h4 { line-height: 1.35; margin: 1.7em 0 .6em; position: relative; }
h1 { font-size: 1.6em; border-bottom: 2px solid var(--border); padding-bottom: .35em; }
h2 { font-size: 1.3em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
h3 { font-size: 1.12em; }
h4 { font-size: 1em; color: var(--muted); }
a { color: var(--accent); }
.anchor { opacity: 0; margin-left: .4em; font-size: .7em; text-decoration: none; }
h1:hover .anchor, h2:hover .anchor, h3:hover .anchor { opacity: .5; }
p { margin: .8em 0; }
ul, ol { padding-left: 1.5em; margin: .7em 0; }
li { margin: .35em 0; }
code {
  background: var(--code-bg); padding: .15em .4em; border-radius: 5px;
  font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  font-size: .88em; word-break: break-word;
}
.codeblock { position: relative; margin: 1em 0; }
.code-lang {
  position: absolute; top: 0; right: 0; font-size: 11px; color: var(--muted);
  background: var(--code-bg); border: 1px solid var(--border); border-bottom: none;
  border-radius: 0 6px 0 6px; padding: 2px 8px;
}
pre {
  background: var(--code-bg); border: 1px solid var(--border); border-radius: 8px;
  padding: 12px 14px; overflow-x: auto; margin: 0;
}
pre code {
  background: none; padding: 0; font-size: .85em; line-height: 1.6;
  white-space: pre; word-break: normal;
}
blockquote {
  margin: 1em 0; padding: .6em 1em; border-left: 4px solid var(--quote);
  color: var(--muted); background: var(--code-bg); border-radius: 0 6px 6px 0;
}
blockquote p { margin: .3em 0; }
.tablewrap { overflow-x: auto; margin: 1em 0; -webkit-overflow-scrolling: touch; }
table { border-collapse: collapse; width: 100%; font-size: .9em; }
th, td { border: 1px solid var(--border); padding: 7px 10px; text-align: left; vertical-align: top; }
th { background: var(--code-bg); font-weight: 600; white-space: nowrap; }
tbody tr:nth-child(2n) { background: color-mix(in srgb, var(--code-bg) 55%, transparent); }
hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
img { max-width: 100%; height: auto; }
.toc {
  border: 1px solid var(--border); border-radius: 8px; padding: 12px 16px;
  margin: 1.2em 0; background: var(--code-bg); font-size: .92em;
}
.toc-title { font-weight: 600; margin-bottom: .4em; }
.toc a { text-decoration: none; display: block; padding: 2px 0; color: var(--fg); }
.toc a.lv3 { padding-left: 1.1em; color: var(--muted); }
.toc a.lv4 { padding-left: 2.2em; color: var(--muted); font-size: .95em; }
.footer { margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--border);
          color: var(--muted); font-size: .85em; }
"""


def build_page(title: str, md_path: Path, nav: list[tuple[str, str]], active: str) -> str:
    """读取一个 Markdown 文件，产出完整可独立打开的单文件 HTML（样式内嵌、无外部依赖）。

    title 为页面标题，nav 为顶部导航项，active 标记当前页。
    """
    body, toc = convert(md_path.read_text(encoding="utf-8"))

    toc_html = ""
    items = [(lv, t) for lv, t in toc if lv <= 3]
    if len(items) > 3:
        links = []
        for lv, t in items:
            anchor = "h-" + re.sub(r"[^\w\u4e00-\u9fff]+", "-", t).strip("-")
            links.append(f'<a class="lv{lv}" href="#{anchor}">{html.escape(t)}</a>')
        toc_html = (
            '<div class="toc"><div class="toc-title">目录</div>'
            + "".join(links)
            + "</div>"
        )

    nav_html = "".join(
        f'<a class="{"active" if href == active else ""}" href="{href}">{html.escape(label)}</a>'
        for label, href in nav
    )

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>{CSS}</style>
</head>
<body>
<div class="topbar">{nav_html}<span class="spacer"></span></div>
<div class="wrap">
{toc_html}
{body}
<div class="footer">手机端本地大模型部署 · 由 Markdown 自动生成</div>
</div>
</body>
</html>
"""


def main():
    """命令行入口：argv[1] 为项目目录，argv[2] 为 HTML 输出目录。

    把所有列在 PAGES 里的 Markdown 转成网页，并生成一个自动跳转的入口 docs.html。
    """
    src = Path(sys.argv[1])
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)

    # 要转换的文档清单：(页面标题, 源文件名, 输出文件名)
    # 顺序同时决定顶部导航的排列，所以「交接文档」放最前 —— 拔线后先看它。
    pages = [
        ("交接文档", "交接文档.md", "docs-handover.html"),
        ("使用说明", "README.md", "docs-readme.html"),
        ("项目总结", "部署总结.md", "docs-summary.html"),
        ("提速调研", "提速调研报告.md", "docs-speed.html"),
        ("剪枝与容器", "端侧优化与容器化调研.md", "docs-optimize.html"),
        ("聊天界面", None, "/"),
    ]

    # 顶部导航：由 pages 派生，保证导航项与产出文件永远一致
    nav = [(title, fname) for title, _, fname in pages]
    nav = [(t, f) for t, f in nav if f]

    generated = []
    for title, md_name, out_name in pages:
        if md_name is None:
            continue  # 聊天界面是外部链接，不产生文件
        md_path = src / md_name
        if not md_path.exists():
            print(f"跳过（不存在）: {md_path}")
            continue
        htmltext = build_page(title, md_path, nav, out_name)
        (outdir / out_name).write_text(htmltext, encoding="utf-8")
        generated.append((title, out_name))
        print(f"生成 {outdir / out_name}  ({len(htmltext)} 字节)")

    # 入口页：自动跳到交接文档，同时给出所有页面的链接以备跳转失败
    links = " · ".join(f'<a href="{f}">{t}</a>' for t, f in generated)
    first = generated[0][1] if generated else "docs-readme.html"
    (outdir / "docs.html").write_text(
        '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
        f'<meta http-equiv="refresh" content="0; url={first}">'
        "<title>文档</title></head><body>"
        f"<p>正在跳转… {links}</p></body></html>",
        encoding="utf-8",
    )
    print(f"生成 {outdir / 'docs.html'}")


if __name__ == "__main__":
    main()
