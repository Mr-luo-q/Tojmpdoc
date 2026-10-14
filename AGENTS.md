# AGENTS.md（Tojmpdoc 仓库）

本仓库是「按产出日期归档的交付文档仓库」。动手之前先读这一份。

## 1. 结构约定

```text
Tojmpdoc/
├─ README.md        总览：日期索引、归档规则、信度说明（手写，新增日期时同步更新）
├─ source.md        未入库内容登记（由 tools/collect.py 生成，不手改）
├─ .gitignore       兜底规则：模型权重、密钥、缓存、安装包
├─ tools/
│   ├─ collect.py   归档脚本
│   └─ collect.md   collect.py 的说明
└─ MMDD/            日期目录，MMDD = 月日，例如 1012
    ├─ README.md    当天索引（由 tools/collect.py 生成，不手改）
    └─ doc/<来源工程>/<原相对路径>
```

两个「不手改」的文件由脚本生成，手改下次跑脚本就没了。要改内容，改 `tools\collect.py` 里的
`DATE_NOTES`（每天一句话主题）、`UNTRACKED`（未入库登记）、`PROJECTS`（来源工程与排除规则）。

## 2. 往仓库里加东西

新产出不要手工拖文件。做法是：把当天产出写完（放在来源工程里），然后跑脚本。

```powershell
cd D:\项目\Tojmpdoc
python tools\collect.py --dry-run   # 确认会收哪些、日期对不对
python tools\collect.py             # 落盘
```

脚本自己判定日期（文件修改时间），所以产出文档不要事后改时间戳；如果某个源目录的时间戳被
git 检出覆盖过，在 `PROJECTS` 的 `date_rules` 里给该路径写死日期。

## 3. 不收什么

```text
模型权重          gguf / safetensors / pt / ckpt / onnx，GitHub 单文件 100 MB 上限，且不属于文档
第三方源码        从 HACS、GitHub 解压出来的组件（体积大、可再下载、有自己上游）
运行时产物        浏览器 profile、SQLite 数据库、常驻服务日志
单文件超限        文本 > 512 KB、压缩包 > 2 MB
含口令的配置      设备密码、热点 psk、API 密钥、密码文件（原文档自己要求不入 git）
```

这些东西不是丢掉，是在 `source.md` 里登记路径、体积、原因，用时回本机取。

## 4. 入库前脱敏

文档里顺手记的本机口令（HA 登录口令、手机热点口令、树莓派 SSH 口令）在**副本**里要被替换掉，
本机原件不动。规则写在 `tools\collect.py` 的 `GLOBAL_REDACT` 里，每跑一次归档都会对新副本和
仓库里已有的快照各过一遍；`tools/` 与 `.git/` 跳过（脚本自己写着这些口令的正则）。
命中清单会写进 `source.md` 第 4 节。要加新口令，往 `GLOBAL_REDACT` 里加一条 `(正则, 替换, 说明)`。

## 5. 写文档的规矩

沿用上层工程的写法：文件名用 `NN_主题.md` 编号；文档开头写清基于哪些源文件、核对时间、哪些结论
已核对、哪些尚未验证；代码配同名中文 `.md`，每个函数至少一行中文注释；结构用代码框画图，
不要把一个意思拆成十几条碎 bullet。

