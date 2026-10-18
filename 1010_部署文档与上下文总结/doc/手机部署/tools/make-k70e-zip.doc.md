# tools/make-k70e-zip.py 说明

## 一、这个脚本解决什么问题

把红米 K70E 的部署文档、脚本与原始日志打包成一个 zip，便于离线查看、传阅与备份。

看起来是「压缩一下」，但有两处不能走捷径。

**第一，中文文件名在 zip 里是历史坑。** zip 规范原本规定文件名用 CP437 编码，不支持中文；后来的扩展用「general purpose bit 11」标志位声明「文件名是 UTF-8」。不设这个位，各平台会各自猜编码，解压出来一堆乱码。所以脚本没有用 `shutil.make_archive` 之类的快捷方式，而是逐个条目手工构造 `ZipInfo`。

**第二，为什么不复用 `tools/make-docs-zip.py`。** 那个脚本的文件清单与说明文本是为上一台设备（华为 Pura 70）写死的，对应的是另一批文档。改掉它会丢掉原包的复现能力，所以另起一个，两者并存。

## 二、命令行用法

```powershell
python tools\make-k70e-zip.py <项目目录> <输出zip路径>
```

实际使用的命令：

```powershell
python tools\make-k70e-zip.py . "手机部署文档包-K70E.zip"
```

| 位置 | 含义 | 本项目取值 |
|---|---|---|
| argv[1] | 项目目录，脚本按固定清单在此取文件 | `.` |
| argv[2] | 输出 zip 的完整路径 | `手机部署文档包-K70E.zip` |

## 三、输入

无配置文件。打包内容由模块级常量 `FILES` 决定，它是「要打包什么」的唯一事实来源，增删文件只改这一个列表。

清单分四组：

```text
报告/          5 份核心报告 + 交接文档
脚本/          启停脚本与 GPU/NPU 脚本（含各自的 .doc.md）
脚本/tools/    32 个探测与测试脚本 + 索引 README.doc.md
原始日志/      9 份关键测量的原始输出
```

## 四、输出

一个 zip，实测 199,906 字节，65 个条目。

```text
说明.txt                        运行期生成，不在磁盘上
报告/  （6 个文件）
脚本/  （6 个文件）
脚本/tools/  （52 个文件）
原始日志/  （6 个文件）
```

`说明.txt` 的内容包含七部分：

| 章节 | 内容 |
|---|---|
| 一、这个包是什么 | 设备信息与本次重点做的两件事 |
| 二、包里有什么 | 逐条列出文件与用途 |
| 三、核心结论 | 三后端可用性、GPU 慢的硬件原因、NPU 封堵的三层原因 |
| 四、四个模型 | 性能表 + 两个反直觉的发现（GQA 影响、SSM 抗衰减） |
| 五、怎么用 | 启动命令、模型切换、三个必须遵守的参数 |
| 六、九个环境坑 | HyperOS 三条、Termux 四条、测量与自动化两条 |
| 七、数据局限 | 主频漂移、频率锁定、中文质量未评估、热降频未测 |

打包时间写在 `说明.txt` 第一行，所以每次运行内容都不同。

## 五、内部结构

脚本分三段：模块级配置、说明文本常量、`main()`。

```text
SRC = Path(sys.argv[1])      项目目录
OUT = Path(sys.argv[2])      输出 zip 路径
FILES = [...]                (归档内路径, 源文件相对路径) 的清单
STAMP = ...                  打包时间字符串
README_TXT = f"""..."""      写进 zip 的说明文本（用 f-string 插入时间）
```

`main()` 的关键实现是**不用 `write()` 而用 `writestr()` 配合手工构造的 `ZipInfo`**：

```text
ZipInfo(arcname)                建立条目，指定归档内路径
   │
   ├─ flag_bits |= 0x800        标明文件名是 UTF-8   ← 中文不乱码的关键
   ├─ compress_type = DEFLATED  用 deflate 压缩
   ├─ external_attr = ...<<16   写权限位（.sh 标 0o755，其余 0o644）
   └─ z.writestr(zi, bytes)     写入内容
```

`external_attr` 左移 16 位是因为 zip 把 Unix 权限存在高 16 位。这样 `.sh` 脚本解压出来自带可执行权限，在 Linux 或 Termux 上不用再 `chmod`。

缺失的源文件不会让脚本失败，只记进 `missing` 列表最后统一提示——因为脚本清单是按类别批量列出的，某些可选文件（如中途废弃的脚本）不存在是正常的。

`main()` 结束前会自校验并打印结果：

```text
生成 <路径>  (199906 字节)
条目数 65
CRC 校验: OK
```

## 六、验证方式

打完包必须验两件事：文件名解码是否正确、内容有没有损坏。

```text
Python 侧（编码/解码自洽）
  zipfile.ZipFile(...).namelist()    列出条目，确认中文名
  zipfile.ZipFile(...).testzip()     全量 CRC 校验，返回 None 表示无损坏

.NET 侧（与 Windows 资源管理器同源实现）
  [System.IO.Compression.ZipFile]::OpenRead(...)   看别的程序能否正确解析中文名

内容比对
  解压后与原文件做 SHA256 比对
```

本次实测结果：

| 检查项 | 结果 |
|---|---|
| 条目数 | 65 |
| CRC 整体校验 | OK |
| .NET 读中文名 | 全部正确（`报告/GPU-NPU探测报告.md`、`说明.txt` 等） |
| 目录分组 | `报告/`、`脚本/`、`原始日志/` 三层清晰 |

**`.NET 侧`这一步是关键**：它证明的不只是「Python 自己读写一致」，而是**别的程序**也能正确解码，才真正解决了乱码问题。

## 七、未收录的文件

```text
tools/termux-universal.apk     117 MB 的 Termux 安装包
    不适合并入 200 KB 的文档包，且可从官方渠道重新获取
    （https://f-droid.org/packages/com.termux/）

models/*.gguf                  四个模型共 3.9 GB
    体积太大，手机上已有

probe-reports/ 下的截图        screen.png / screen2.png 共 630 KB
    是当时验证「终端注入是否生效」的过程证据，
    对理解报告结论价值不大，未收录
```

## 八、对应文件

```text
tools/make-k70e-zip.py        本脚本
tools/make-k70e-zip.doc.md    本说明
tools/make-docs-zip.py        上一台设备的打包脚本（并存，未改动）
```

输出：`手机部署文档包-K70E.zip`
