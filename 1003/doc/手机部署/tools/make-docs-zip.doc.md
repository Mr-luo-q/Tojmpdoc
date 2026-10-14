# tools/make-docs-zip.py 说明文档

## 一、这个脚本解决什么问题

把项目文档与脚本打包成一个 zip，方便在手机或别的电脑上离线查看、传阅、备份。

看起来是「压缩一下」这么简单的事，但**中文文件名**在 zip 里有个历史坑：zip 规范原本规定文件名用 CP437 编码，不支持中文。后来的扩展用「general purpose bit 11」这个标志位表示「文件名是 UTF-8」。如果不设这个位，各平台会各自猜测编码，结果就是解压出来一堆乱码文件名。

所以这个脚本没有用 `shutil.make_archive` 之类的快捷方式，而是逐个条目手工构造 `ZipInfo` 并显式设置 UTF-8 标志位。

```text
源文件                                    归档内路径
────────────────────────────────────────────────────────────────
README.md                        ──►     README.md
部署总结.md                       ──►     部署总结.md
start-server.sh                  ──►     start-server.sh
termux-llama-prebuilt.sh         ──►     termux-llama-prebuilt.sh
termux-llama-setup.sh            ──►     termux-llama-setup.sh
.docs-html/docs.html             ──►     html/docs.html
.docs-html/docs-readme.html      ──►     html/docs-readme.html
.docs-html/docs-summary.html     ──►     html/docs-summary.html
tools/deploy-to-phone.ps1        ──►     tools/deploy-to-phone.ps1
tools/md2html.py                 ──►     tools/md2html.py
（脚本自动生成）                  ──►     说明.txt   ← 放在最前
```

所有条目都带 `flag_bits |= 0x800`，即 UTF-8 文件名标志。

## 二、命令行用法

```powershell
python tools\make-docs-zip.py <项目目录> <输出zip路径>
```

实际例子（本项目用的命令）：

```powershell
python tools\make-docs-zip.py . "手机部署文档包.zip"
```

| 位置 | 含义 | 本项目取值 |
|---|---|---|
| argv[1] | 项目目录，脚本按固定清单在此取文件 | `.` |
| argv[2] | 输出的 zip 完整路径 | `手机部署文档包.zip` |

## 三、输出结果

一个 zip 文件，实测 52221 字节（11 个条目）。

其中 `说明.txt` 是脚本**在运行期生成的**，不是磁盘上的文件。内容包含六部分：

| 章节 | 内容 |
|---|---|
| 一、包里有什么 | 逐条列出文件及其用途 |
| 二、手机上已装好什么 | 说明这是文档包，不是重装包，并列出手机上已有的目录与体积 |
| 三、怎么用 | 三种使用方式（浏览器界面 / Termux 命令行 / API 调用）与启停命令 |
| 四、实测性能 | 60.2 t/s 提示处理、19.1 t/s 生成、常驻内存 1.9 GB |
| 五、四个必须知道的坑 | 不要在手机上编译、必须用 android-arm64、bionic 不支持 $ORIGIN、Web UI 要单独装 |
| 六、换新手机怎么装 | 从装 Termux 到跑通的最短步骤 |

打包时间会写进 `说明.txt` 第一行，所以每次运行内容都不同。

## 四、内部结构与函数

脚本分三段：模块级配置、说明文本常量、`main()`。

### 模块级配置

```text
SRC = Path(sys.argv[1])      项目目录（命令行第一个参数）
OUT = Path(sys.argv[2])      输出 zip 路径（第二个参数）
FILES = [...]                (归档内路径, 源文件 Path) 的清单
STAMP = ...                  打包时间字符串
README_TXT = f"""..."""      要写进 zip 的说明文本
```

`FILES` 是唯一的「要打包什么」的事实来源，增删文件只改这一个列表。

### main()

职责：打开 zip、写入说明文件、按清单写入其余条目、结束时报告缺失项。

输入：无参数（直接读模块级 `SRC` / `OUT`）
输出：无返回值，向 stdout 打印每个文件的生成结果；源文件缺失时打印跳过清单

关键实现是**不用 `write()` 而用 `writestr()` 配合手工构造的 `ZipInfo`**：

```text
ZipInfo(arcname)              建立条目，指定归档内路径
   │
   ├─ flag_bits |= 0x800      标明文件名是 UTF-8  ← 中文不乱码的关键
   ├─ compress_type = DEFLATED 用 deflate 压缩
   ├─ external_attr = ...<<16  写权限位（.sh 标 0o755，其余 0o644）
   └─ z.writestr(zi, bytes)    写入内容
```

`external_attr` 左移 16 位是因为 zip 把 Unix 权限存在高 16 位。这样 `.sh` 脚本解压出来就自带可执行权限，不用再 `chmod`。

缺失的源文件不会让脚本失败，只记进 `missing` 列表最后统一提示 —— 因为 `.docs-html/` 是生成目录，没跑过 `md2html.py` 时它本来就不存在。

## 五、验证方式

打完包必须验两件事：文件名解码正确、内容没损坏。

```text
Python 侧（编码/解码自洽）
  zipfile.ZipFile(...).namelist()      列出条目，确认中文名正确
  zipfile.ZipFile(...).testzip()       全量 CRC 校验，返回 None 表示无损坏

.NET 侧（Windows 资源管理器同源实现）
  [System.IO.Compression.ZipFile]::OpenRead(...)   看能否正确解析中文名

字节级比对
  Expand-Archive 解压后与原文件做 SHA256 比对
```

本次实测结果：

| 检查项 | 结果 |
|---|---|
| Python 列出的中文名 | 全部正确（`说明.txt`、`部署总结.md`、`手机部署文档包`） |
| .NET 列出的中文名 | 全部正确，11 个条目 |
| CRC 整体校验 | OK（无损坏） |
| 解压后 SHA256 比对 | README.md / 部署总结.md / start-server.sh / termux-llama-prebuilt.sh 全部 IDENTICAL |

`.NET 侧`这一步是关键：它证明的不只是「Python 自己读写一致」，而是**别的程序**也能正确解码，也就是真正解决了乱码问题。

## 六、未收录的文件

`tools/termux-universal.apk` 是 117 MB 的 Termux 安装包，不适合并入 52 KB 的文档包，而且它可以从官方渠道重新获取（https://f-droid.org/packages/com.termux/ ），所以没进清单。需要离线分发时单独拷贝。
