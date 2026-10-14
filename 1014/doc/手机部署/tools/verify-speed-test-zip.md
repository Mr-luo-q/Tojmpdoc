# verify-speed-test-zip.py 中文说明

职责：校验提速实测打包结果的完整性，做三件事。

```text
1 逐条目 SHA-256     把 zip 里的内容与磁盘源文件直接比，确认打包没改动任何字节
2 清单.tsv 一致性    清单覆盖的条目 == 实际内容条目，且每行哈希可复算、字节数吻合
3 CRC 全量校验       testzip() 检查每个条目的压缩数据是否完整
```

第 1 步是仓库里其他打包脚本没有做的：`make-research-zip.py` 的说明文档自己写明「未做解压后与原文件逐字节 SHA256 比对，属未直接验证」。本脚本把这一步补上。

输入：`<项目目录> [zip 路径]`。不给 zip 时自动取项目目录下最新的 `*20261014.zip`。

输出：标准输出各校验项的结论与最终 `RESULT=PASS|FAIL`，退出码 0/1。

清单规则不在本脚本里重复定义，而是按路径载入 `make-speed-test-zip.py` 并调用它的 `build_manifest()`，所以「包内该有哪些文件」只有一处事实来源；改了打包清单，校验会自动跟着变。

```powershell
python tools/verify-speed-test-zip.py .
python tools/verify-speed-test-zip.py . 手机提速实测包-20261014.zip
```

读取：项目目录源文件与 zip。写入：无。不负责：文档内容与实测结论是否一致（那要靠人工对照 `06-历史基线/` 与 `02-实测结果/原始数据/`）；也不校验 zip 之外的中文文件名在第三方解压器里的显示效果，只保证 Python zipfile 侧读取正确。
