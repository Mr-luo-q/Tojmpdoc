# collect.py 说明

对应文件：`tools/collect.py`（本仓库自带的归档脚本）

## 它解决什么问题

每次干活的产出散在几个工程目录里：文档在 `D:\项目\simuhome-ljb\_work`，配套脚本就在旁边；
手机端的东西在 `D:\项目\手机部署`；树莓派的东西在 `D:\项目\树莓派`。这个脚本把它们按**产出日期**
收进本仓库的 `MMDD/doc/<工程>/` 下，同时生成当天的索引和未入库登记表。

## 输入

```text
脚本内 PROJECTS 表声明的三个源工程：

  simuhome-ljb   D:\项目\simuhome-ljb      扫描 _work、deploy、context、_tools、finally new paper
  树莓派         D:\项目\树莓派            扫描整个目录
  手机部署       D:\项目\手机部署          扫描整个目录

命令行参数：--dry-run 只打印动作不落盘；--date MMDD 只归档指定日期，可重复传入。
```

常用命令：

```powershell
python tools\collect.py
python tools\collect.py --dry-run
python tools\collect.py --date 1019 --dry-run
python tools\collect.py --date 1019
```

## 输出

```text
Tojmpdoc/MMDD_短标题/doc/<工程>/<原相对路径>   复制过来的文件，保留原始修改时间
Tojmpdoc/MMDD_短标题/README.md                 当天索引：主题一句话 + 文件清单（文件 / 原路径 / 大小）
Tojmpdoc/source.md                             未入库登记：路径 / 体积 / 文件数 / 原因
```

## 判定顺序

```text
遍历源目录下的每个文件
  ├─ 路径命中 exclude 正则？
  │      → 跳过（第三方源码、浏览器 profile、运行时日志、离线安装包）
  ├─ 扩展名不在 TEXT_EXTS / ARCHIVE_EXTS，且没有命中该工程的 extra_exts？
  │      → 跳过（模型权重、图片、二进制）
  ├─ 体积超上限（文本 512 KB，压缩包 2 MB）？
  │      → 记进 source.md 的「超限」表，不复制
  └─ 其余复制到 <日期>/doc/<工程>/<原相对路径>

日期怎么算
  ├─ 先匹配 PROJECTS[].date_rules（写死的日期，用于时间戳被 git 检出覆盖的目录）
  └─ 没匹配上就用文件自身的修改时间得到 MMDD

目录名怎么定
  ├─ 取 DATE_TITLES[MMDD] 作为短标题
  ├─ 拼成 MMDD_短标题，例如 1012_MQTT与设备接入实测
  └─ 没登记短标题就退回纯 MMDD，并打警告
```

## 函数逐个说

`human(size)`：字节数转成 `12.3 KB` 或 `1.2 MB` 这种给人看的字符串，索引表和 `source.md` 都用它。

`dir_stats(path)`：对一个目录递归求和，返回总字节数与文件数；传入单个文件时返回它自己。
用于 `source.md` 里给未入库的目录报体积。

`is_excluded(rel, patterns)`：相对路径是否命中任一排除正则，命中就整棵子树不收。

`size_limit(ext)`：按扩展名给出单文件上限，压缩包走 2 MB，其余走 512 KB。

`pick_date(project, rel, mtime)`：决定一个文件进哪个日期目录，先看 `date_rules`，再看修改时间。

`scan_project(project)`：扫描一个工程，返回要收的文件记录和因超限被跳过的记录。每条记录带源路径、
相对路径、体积、修改时间。

`date_dir(date)`：把 `MMDD` 拼成目录名 `MMDD_短标题`，短标题来自 `DATE_TITLES`。

`dest_of(record)`：算出文件在本仓库里的落点，即 `MMDD_短标题/doc/<工程>/<原相对路径>`。

`copy_all(records, dry_run)`：按记录复制文件，用 `shutil.copy2` 保留原始修改时间。

`write_date_readme(dir_name, dry_run)`：扫描某个日期目录里的实际文件，生成 `README.md`，按工程
分组列清单，链接指向仓库内的相对路径。按目录内容生成，所以后来有文件改到别的日期时，旧目录的
清单仍然准确。

`write_source_md(oversized, dry_run)`：生成 `source.md`，登记按路径排除的目录、因体积跳过的文件，
以及「另有 git 远端、未并入」的外部仓库。

`main()`：入口，串起「扫描 → 复制 → 写索引与登记表」，并打印每个日期收了多少文件。
`--date` 只过滤要复制的记录和要重写的日期索引，`source.md` 仍保留全工程的超限登记。

## 怎么改

```text
新日期的一句话主题        改 DATE_NOTES
新日期的目录短标题        改 DATE_TITLES
新工程要归档              改 PROJECTS，加一条（key / root / scan / exclude / date_rules）
某个目录时间戳不可信      在该工程的 date_rules 里加一条 (正则, "MMDD")
体积大的东西要登记        改 UNTRACKED，加一条 (工程 key, 相对路径, 原因)
新增扩展名                改 TEXT_EXTS 或 ARCHIVE_EXTS
某个工程只放行少量图片/XML 改该工程的 extra_exts（正则白名单，避免全局收图）
```

当前只有 `手机部署` 工程配置了 `extra_exts`，用于收录 `research/mnn-20261019/termux*.png` 和 `termux*.xml` 这类 MNN 部署过程证据。其他目录的图片仍然不入库。

## 已验证与未验证

已核对：2026-10-18 在 `D:\项目\Tojmpdoc` 实际运行，收录 734 个文件、生成 13 个日期目录；
目录名已改成 `MMDD_短标题`；每个日期目录的 `README.md` 与目录里的实际文件数一致；
重复运行不产生差异；被排除的目录逐个确认过路径存在。

尚未验证：`1010` 与 `1004` 的日期是推断值（本机时间戳已被 git 检出覆盖），不是从文件内容确证的
事实。
