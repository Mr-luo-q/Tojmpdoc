# fetch-speed-sources.py 中文说明

职责：下载手机模型提速调研的一手资料并保存原文，记录版本、SHA-256、下载时间和失败原因。仅使用 Python 标准库和系统 curl，不调用搜索摘要作为证据。

输入：脚本内 S01～S30 来源清单，包含现有 v0.6.0 和固定新版提交；`--out` 指定输出目录；`--only S01,S02` 可重试指定来源。

输出：每个来源保存为 `Sxx.txt`。GitHub 原始接口返回另存为 `Sxx-metadata.txt`，其中包含 blob SHA。`manifest.tsv` 保存完整清单，部分重试使用 `manifest-selected.tsv`，不覆盖完整清单。

同时在输出目录的上一级生成中文 `来源索引.md`，部分重试索引会与已有全量清单合并显示。控制台使用UTF-8，避免Windows中文代码页破坏输出。

```text
GitHub 固定提交请求 → 失败时回退 master，并在清单记录真实 ref 和错误
普通网页请求       → 保存网页字节与 SHA-256
两次均失败         → 写 FAILED，退出码 1
```

读取：HTTPS 文档与源码。写入：指定输出目录。不会安装手机软件或修改模型；内容哈希只能证明归档完整性，网页自身的结论仍需核对。固定提交回退后的文件必须按其实际版本解释，不可默认为与固定提交一致。

```powershell
python tools/fetch-speed-sources.py
python tools/fetch-speed-sources.py --only S16,S17
```

对应报告：[手机小模型提速调研与复现.md](../手机小模型提速调研与复现.md)。

Android 官网主域在本次网络环境超时，清单采用官方 `developer.android.google.cn` 中国镜像。旧的失败记录见报告中的来源说明；仍失败的来源不能作为已核验依据。
