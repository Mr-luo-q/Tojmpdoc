# source.md

本文件由 `tools/collect.py` 生成，登记**没有进这个仓库**的东西：体积大的、第三方的、或者含本机口令的。需要时按路径回本机取，不用从仓库里找。

生成时间：2026-10-19 22:38（本机 `D:\项目`）

## 1. 按路径排除，未入库

| 来源工程 | 路径 | 体积 | 文件数 | 原因 |
| --- | --- | --- | --- | --- |
| simuhome-ljb | `_work\chrome-ha-profile` | 21.6 MB | 417 | 浏览器用户数据（登录态），可再生成 |
| simuhome-ljb | `_work\edge-ha-profile` | 1095.5 MB | 5726 | 浏览器用户数据（登录态），可再生成 |
| simuhome-ljb | `_work\logs` | 6.6 MB | 16 | HA / MQTT 等运行时日志 |
| simuhome-ljb | `_work\llm\extract` | 218.3 KB | 55 | HACS 组件解压出来的第三方源码 |
| simuhome-ljb | `_work\llm\extract202` | 218.3 KB | 55 | HACS 组件解压出来的第三方源码 |
| simuhome-ljb | `_work\llm\removed_extended_openai_conversation` | 242.7 KB | 28 | 撤除前的第三方组件副本 |
| simuhome-ljb | `_work\llm\ext-2.0.2.zip` | 81.4 KB | 1 | 第三方组件安装包 |
| simuhome-ljb | `_work\llm\ext-2.0.3.zip` | 81.4 KB | 1 | 第三方组件安装包 |
| simuhome-ljb | `_work\midea\extract` | 1.8 MB | 101 | 第三方 midea_auto_cloud 源码 |
| simuhome-ljb | `_work\midea\midea_auto_cloud-master.zip` | 729.3 KB | 1 | 第三方组件安装包 |
| simuhome-ljb | `_work\pi\wheels` | 1.5 MB | 7 | 树莓派离线 wheel 安装包 |
| simuhome-ljb | `_work\broker\logs` | 649 B | 2 | MQTT broker 运行时日志 |
| simuhome-ljb | `_work\bt_speaker\logs` | 4.3 KB | 6 | 蓝牙音箱桥运行时日志 |
| simuhome-ljb | `_work\bt_speaker\media\announce.wav` | 215.4 KB | 1 | 提示音素材 |
| simuhome-ljb | `_work\mcp\data\schedules.db*` | 76.3 KB | 3 | MCP 运行时 SQLite 数据库 |
| simuhome-ljb | `finally new paper\**\*.png` | 2.9 MB | 18 | 论文资料里的截图，正文 md 里用相对路径引用 |
| 树莓派 | `cloud-init` | 5.6 KB | 4 | 系统镜像自带模板 |
| 树莓派 | `bootfs-user-data-patch` | 5.0 KB | 2 | 含手机热点 psk 的修补脚本 |
| 树莓派 | `树莓派配置记录.md` | 20.0 KB | 1 | 含树莓派与热点口令，文档自身要求不入 git |
| 手机部署 | `.docs-html` | 134.9 KB | 6 | 由 markdown 生成的手机端 HTML，内容与 md 重复 |
| 手机部署 | `tools\platform-tools` | 16.7 MB | 14 | Android 官方 platform-tools 二进制 |
| 手机部署 | `research\mnn-20261019\mnn_chat_0_8_3.apk` | 41.8 MB | 1 | MNN Chat 官方 APK，HyperOS 安装受限，可重新下载 |
| 手机部署 | `research\mnn-20261019\toolchain` | 2886.4 MB | 7673 | Android NDK r28b 压缩包与解压目录，体积大 |
| 手机部署 | `research\mnn-20261019\src\extracted` | 240.3 MB | 8314 | MNN 3.6.1 解压源码，构建时可重新生成 |
| 手机部署 | `research\mnn-20261019\build` | 447.4 MB | 487 | Android 编译产物，可重新编译 |
| 手机部署 | `research\mnn-20261019\tmp` | 0 B | 0 | 编译临时目录 |
| 手机部署 | `research\mnn-20261019\llama-cpp` | 1.0 MB | 1 | llama.cpp Android 预编译包下载未完成，仅用于对照尝试 |
| 手机部署 | `research\mnn-20261019\test.o` | 1.1 KB | 1 | 编译测试临时对象 |
| 手机部署 | `research\mnn-20261019\model\Qwen3.5-0.8B-MNN\llm.mnn` | 2.0 MB | 1 | MNN LLM 计算图，可重新下载 |
| 手机部署 | `research\mnn-20261019\model\Qwen3.5-0.8B-MNN\llm.mnn.weight` | 448.6 MB | 1 | MNN 4-bit 主权重，约 470 MB，可重新下载 |
| 手机部署 | `research\mnn-20261019\model\Qwen3.5-0.8B-MNN\visual.mnn` | 245.6 KB | 1 | MNN 视觉编码器计算图，可重新下载 |
| 手机部署 | `research\mnn-20261019\model\Qwen3.5-0.8B-MNN\visual.mnn.weight` | 60.1 MB | 1 | MNN 视觉编码器权重，约 60 MB |
| 小模型研究 | `models` | 1777.1 MB | 14 | Qwen3-0.6B 原权重与导出模型，体积大，可重新下载/导出 |
| 小模型研究 | `toolchains` | 2997.0 MB | 7936 | Android NDK 等工具链，体积大，可重新下载 |

## 2. 单文件体积超过上限，未入库

| 来源工程 | 路径 | 体积 |
| --- | --- | --- |
| 手机部署 | `research/mnn-20261019/src/MNN-3.6.1.zip` | 94.7 MB |
| 手机部署 | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/tokenizer.txt` | 6.2 MB |
| 手机部署 | `research/mnn-20261019/model/Qwen3.5-0.8B-MNN/llm.mnn.json` | 5.1 MB |

## 3. 另有 git 远端的仓库，未并入

| 本地路径 | 远端 | 说明 |
| --- | --- | --- |
| `D:\项目\autodl-tmp` | https://github.com/juezhan340/autodl-tmp.git | 科研主线文档仓库（训练数据、接口交接、UbiComp 讨论等），文件时间戳被 git 检出覆盖，无法按日期归档，未并入 |
| `D:\项目\simuhome-ljb` | https://github.com/Mr-luo-q/simuhome-ljb.git | 智能家居工程本体：代码、部署脚本、MQTT/MCP 工程、论文资料。本仓库只镜像它的文档 |
| `D:\项目\小模型研究\MNN` | https://github.com/Mr-luo-q/MNN.git | MNN 源码与构建工程；本仓库只归档 1019.md 架构文档 |

## 4. 入库时脱敏

写文档时顺手记进去的本机口令，在仓库里的**副本**已经按 `tools/collect.py` 的 `GLOBAL_REDACT` 替换成 `<...已脱敏>`，本机原件一个字没动。

| 本仓库里的文件 | 替换掉的内容 |
| --- | --- |
| `1013_端侧缓存测评与树莓派排障/doc/树莓派/树莓派有线直连排障手册.md` | 树莓派 SSH 登录口令（速查表） |

## 5. 重新生成

```powershell
cd D:\项目\Tojmpdoc
python tools\collect.py
```
