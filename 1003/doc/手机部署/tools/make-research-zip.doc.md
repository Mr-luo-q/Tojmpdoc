# make-research-zip.py 说明文档

## 一、职责

把「GPU/NPU 调研」「测速」「Home Assistant 构建」三类文档打成一个聚焦的 zip，
并在包里生成一份 `说明.txt`，讲清每份文档分别回答什么问题。

```text
输入                                          输出
──────────────────────────────────────────────────────────────
argv[1]  项目目录                             一个 zip，内部按主题分四个目录
argv[2]  输出 zip 路径                        + 自动生成的 说明.txt
--with-rpi <目录>（可选）                       + 05-树莓派对照/（可选）
```

## 二、与 tools/make-docs-zip.py 的分工

两个脚本都打 zip，但目标不同，不要混用：

| | `make-docs-zip.py` | `make-research-zip.py` |
|---|---|---|
| 定位 | 完整文档包 | 聚焦调研包 |
| 收录 | 全部脚本 + 各脚本说明书 + 网页版 | 只收三类文档 + 原始数据 |
| 目录结构 | 平铺（按文件类型） | 按主题分目录（01~05） |
| 典型体积 | 约 128 KB / 25 个条目 | 更小，便于单独传阅 |
| 适用 | 交接、备份、换新机 | 分享调研结论、给他人参考 |

## 三、命令行用法

```powershell
# 只打三类文档
python tools\make-research-zip.py . "手机端调研文档包.zip"

# 附带树莓派对照数据
python tools\make-research-zip.py . "手机端调研文档包.zip" --with-rpi ..\树莓派
```

## 四、包内目录结构

```text
说明.txt                              自动生成，含关键数字速查
01-GPU与NPU调研/
    提速调研报告.md
    端侧优化与容器化调研.md
02-测速/
    部署总结.md
    bench-server.ps1
    bench-server.doc.md
03-HomeAssistant构建/
    HomeAssistant构建文档.md
    start-homeassistant.sh
    start-homeassistant.doc.md
04-参考/
    交接文档.md
    README.md
05-树莓派对照/                         仅当传了 --with-rpi 且目录存在
    pi-bench.sh
    bench-report-raw.txt
    部署报告.md
```

## 五、内部函数

| 函数 | 职责 |
|---|---|
| `build_manifest()` | 构造 `(归档内路径, 源文件)` 清单。树莓派那三项只在 `--with-rpi` 指向的目录真实存在时才加入，所以不带该参数也能正常打包 |
| `write_entry(z, arcname, data, mode)` | 写单个条目。手工构造 `ZipInfo` 并设置 UTF-8 标志位、压缩方式与权限位 —— 中文名不乱码的关键就在这里 |
| `make_readme_txt()` | 生成包内 `说明.txt`。除逐条介绍文档外，还汇总了带宽、速度、热降频、HA 版本等关键数字，便于不开文档就快速查阅 |
| `main()` | 命令行入口。写说明文件 → 按清单逐个写入 → 最后统一报告缺失项 |

## 六、两个实现要点

**UTF-8 文件名标志位。** zip 规范原本只认 CP437，中文名靠 general purpose
bit 11 声明「文件名是 UTF-8」。不设这一位，各平台会各自猜编码，解压出乱码文件名。

```python
zi.flag_bits |= 0x800          # bit 11
zi.external_attr = mode << 16  # Unix 权限存在高 16 位
```

**权限位左移 16 位。** `.sh` 传 `0o755`、其余传 `0o644`，
这样脚本解压出来自带可执行权限，不用再 `chmod`。

## 七、实测验证状态

**已验证的事实**

| 验证项 | 方式 | 结果 |
|---|---|---|
| 脚本语法 | AST 解析 | PASS |
| 打包执行 | 带 `--with-rpi` 实跑 | 成功 |
| 中文文件名 | Python 侧 `namelist()` | 全部正确 |
| 中文文件名（他方实现） | .NET `ZipFile.OpenRead` 读取 | 全部正确 |
| 完整性 | `testzip()` 全量 CRC 校验 | OK |
| 缺失项处理 | 源文件不存在时 | 打印跳过清单，不中断 |

**待确认的风险**

未做「解压后与原文件逐字节 SHA256 比对」这一步。
`make-docs-zip.py` 做过该验证并通过，两者写入逻辑相同，但仍属未直接验证。

## 八、修改清单后要同步的事

`build_manifest()` 是「打什么」的唯一事实来源。新增文档时改这里一处即可，
但**归档内路径要与主题目录的语义保持一致**（01 调研 / 02 测速 / 03 HA / 04 参考 / 05 对照），
否则 `说明.txt` 里的描述会与实际的目录结构对不上。

改了 `make_readme_txt()` 里的内容，也要回头确认与各文档正文的结论一致 ——
这份说明是包里最先被读到的文件，它说错了比正文说错影响更大。
