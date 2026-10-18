# 安卓手机本地部署大模型（Termux + llama.cpp）

2026-10-14新增：[0.6B / 1.5B 提速调研与证据核对](手机小模型提速调研与复现.md)、[复现操作手册](手机小模型提速复现操作手册.md)、[真机实测结果](手机提速实测结果-20261014.md)。调研文档包含设备信息和旧测试解释的修正、CPU内核/FA/KV/缓存实验与归档的一手资料；实测结果来自同日接入 K70E 后的真机测量。

实测最主要的发现：默认的 `-fa auto` 在 2048 深度下等同于开启 Flash Attention，而该档位恰好是生成最慢的一档；改成 `-fa on -ctk q8_0 -ctv q8_0` 后，长上下文生成 0.6B 从 10.06 提到 17.61 t/s、1.5B 从 9.36 提到 11.24 t/s。线程仍是 t4 最优。前缀缓存的收益比这些都大：1166 token 的重复前缀，首字延迟从每轮 16.4 秒降到 0.087 秒。

整个实测的交付包：[手机提速实测包-20261014.zip](手机提速实测包-20261014.zip)，含实验设计、结果正文、各 suite 对照表、逐调用原始数据、工具与提示词、证据来源、历史基线。用 `python tools\make-speed-test-zip.py . <输出zip>` 重新生成，用 `python tools\verify-speed-test-zip.py .` 校验完整性（逐条目 SHA-256 + 清单一致性 + CRC）。

在安卓手机上用 Termux 编译 llama.cpp，本地运行 1.5B 级别的 GGUF 量化模型，可选对外提供
OpenAI 兼容接口。目标机型：任意安卓 7.0+，内存 4 GB 以上。

> 项目整体总结（结论、选型、资源清单、进度、验收标准）见 [部署总结.md](部署总结.md)。
> 本文件侧重具体操作步骤。

## 在手机上看这份文档

文档已转成手机友好的网页，**挂在手机上正在运行的 llama-server 里**，
所以不需要额外的 App，也不用传文件 —— 服务在跑就能看：

| 地址 | 内容 |
|---|---|
| `http://127.0.0.1:8080/docs-readme.html` | 本文件（使用说明） |
| `http://127.0.0.1:8080/docs-summary.html` | 部署总结（含完整构建过程与踩坑记录） |
| `http://127.0.0.1:8080/docs.html` | 文档入口（自动跳到使用说明） |
| `http://127.0.0.1:8080/` | 聊天界面 |

三个页面顶部有切换导航，正文自带目录，支持深色模式，表格可横向滑动。
**前提是服务在运行**（`bash ~/start-server.sh`）；服务停了这些页面也打不开。

手机里还各留了一份 Markdown 源文件，可以用任意 Markdown 阅读器打开：

```
/sdcard/Download/termux-deploy/README.md
/sdcard/Download/termux-deploy/部署总结.md
```

### 文档是怎么生成的

`tools/md2html.py` 把 Markdown 转成自带样式的单文件 HTML（无外部依赖、无 JS）：

```powershell
python tools\md2html.py . .docs-html
```

生成 `docs.html` / `docs-readme.html` / `docs-summary.html`，再推送到手机的服务目录：

```powershell
adb push .docs-html\docs-readme.html /data/local/tmp/
adb shell "run-as com.termux cp /data/local/tmp/docs-readme.html \
  /data/data/com.termux/files/home/llama-android/ui/llama-b11146/"
```

改完文档重新生成一次即可。

## 前置条件

- **Termux 必须从 F-Droid 或 GitHub Releases 安装。** Google Play 上那个版本已停止维护，
  装完 `pkg` 会各种报错，这是新手最容易踩的坑。下载地址：
  https://f-droid.org/packages/com.termux/ 或 https://github.com/termux/termux-app/releases
- 剩余存储 ≥ 5 GB（源码 + 编译产物约 2~3 GB，模型另算）。
- 建议插着电、连 WiFi 再开始编译。

## 手机连接电脑（USB 调试）

这是整个流程里唯一需要手动操作手机的部分。

**1. 用能传数据的线连接**

很多线只能充电。用手机原装线最稳。插上后手机通知栏应该出现「正在充电」，
如果电脑和手机都毫无反应，先换线、再换 USB 口（优先直连主板口，别用扩展坞）。

**2. 打开开发者选项**

| 品牌 | 路径 |
|---|---|
| 小米 / Redmi | 设置 → 我的设备 → 全部参数 → 连点「MIUI 版本」7 次 |
| 华为 / 荣耀 | 设置 → 关于手机 → 连点「版本号」7 次 |
| OPPO / vivo / 一加 | 设置 → 关于手机 → 连点「版本号」7 次 |
| 三星 | 设置 → 关于手机 → 软件信息 → 连点「编译编号」7 次 |
| 原生 Android | 设置 → 关于手机 → 连点「版本号」7 次 |

注：部分 MIUI/HyperOS 版本要求在「开发者选项」里插着 SIM 卡并登录小米账号，才能打开 USB 调试。

**3. 打开 USB 调试**

设置 → 系统 → 开发者选项 → 找到「USB 调试」并打开。

**4. 改 USB 用途并授权**

连上后下拉通知栏，把 USB 用途从「仅充电」改成「传输文件 / MTP」；
手机上会弹「允许 USB 调试吗」，勾选「一律允许」再点允许。

**5. 验证**

电脑上执行，能列出你的设备就说明通了：

```powershell
tools\platform-tools\adb.exe devices
```

**没有数据线？走无线调试（安卓 11+）**

手机：设置 → 开发者选项 → 无线调试 → 使用配对码配对设备，记下屏幕上的
IP、配对端口和 6 位配对码，然后用 adb 配对：

```powershell
tools\platform-tools\adb.exe pair <手机IP>:<配对端口> <6位配对码>
tools\platform-tools\adb.exe connect <手机IP>:<调试端口>
```

## 快速开始

**推荐走预编译路线**（`termux-llama-prebuilt.sh`），不要自己编译 —— 原因见下节。

把脚本传到手机，然后在 Termux 里执行：

```bash
cp /sdcard/Download/termux-llama-prebuilt.sh ~/
bash ~/termux-llama-prebuilt.sh --model
```

脚本依次完成：装 curl/tar → 下载官方 **Android arm64** 预编译包（72 MB，约 10 秒）
→ SHA256 校验 → 解压到 `~/llama-android/` → 安装分发器到 `~/.local/bin`
→ 下载 Qwen2.5-1.5B-Instruct Q4_K_M 到 `~/models`。

### 为什么不要自己在手机上编译

本机实测（华为 HBN-AL80，Android 12，Termux 0.118.3，clang 21.1.8），
`make llama-cli llama-server` 会在链接阶段失败：

```
ld.lld: error: undefined reference: std::__ndk1::__hash_memory(void const*, unsigned long)
>>> referenced by ../../bin/libllama-server-impl.so (disallowed by --no-allow-shlib-undefined)
c++: error: linker command failed with exit code 1
```

`std::__ndk1` 是 Android libc++ 的命名空间，`__hash_memory` 在该版本的
`libc++_shared.so` 里没有导出 —— 属于 **Termux 预置 clang 与 llama.cpp 新版源码的 libc++ ABI 不匹配**，
不是代码问题。反复重试只会撞同一面墙。

官方 CI 用 Android NDK 产出的 `llama-<tag>-bin-android-arm64.tar.gz` 是 bionic 版本，
和 Termux 完全兼容。同一个 release 里那个 `ubuntu-arm64` 才是 glibc 版（给树莓派用的），
**不要拿错** —— 两者指令集相同但 C 运行库不同，glibc 版在 Android 上会
`interpreter /lib/ld-linux-aarch64.so.1 not found`。

### 运行前必读：bionic 不支持 $ORIGIN

解压出来的二进制**不能直接运行**，会报：

```
CANNOT LINK EXECUTABLE "./llama-cli": library "libllama-cli-impl.so" not found
```

因为 Android 的 bionic linker 不支持 `$ORIGIN` RPATH，不会去可执行文件所在目录找依赖库。
必须设置 `LD_LIBRARY_PATH` 指向该目录 —— 上面的脚本已经用
`~/.local/bin/llama-dispatcher` 分发器自动处理了。手动跑的话：

```bash
export LD_LIBRARY_PATH=~/llama-android/<tag>:${LD_LIBRARY_PATH:-}
```

### llama-cli 和 llama-server 的区别

| | 现象 | 怎么用 |
|---|---|---|
| `llama-cli` | 启动后显示带边框的界面和 `>` 提示符 | 直接输入问题；退出用 `/exit` |
| `llama-server` | **什么界面都没有，看起来像卡住** | 它在监听 HTTP，用 curl 或浏览器访问 8080 |

`llama-server` 不打印对话界面是正常的，不要以为它挂了。

### 旧路线：手机内编译（不推荐，会失败）

`termux-llama-setup.sh` 会装依赖 → 拉源码 → 全量编译。当前版本已不能成功编译
（原因见上），保留仅作参考。

脚本原本会依次完成：装依赖 → 拉 llama.cpp 源码 → Release 编译 → 安装到 `~/.local/bin`
→ 下载 Qwen2.5-1.5B-Instruct Q4_K_M 到 `~/models`。

编译在手机上大约 10~30 分钟。脚本已调用 `termux-wake-lock` 防止中途被挂起，但还是建议
把 Termux 加进电池优化白名单。

### 编译太慢或中断了？只编译要用的两个程序

上面的脚本会编译 llama.cpp 的全部示例、测试和工具，手机上很费时间，切后台也更容易被系统杀掉。
如果已经执行过一次（依赖装好、源码 clone 好了），可以直接单点编译：

```bash
cd ~/llama.cpp && make -C build -j"$(nproc)" llama-cli llama-server && cmake --install build --no-build
```

`--no-build` 是关键：没有它，`cmake --install` 会把全部目标重新编译一遍。
这样只链接 `llama-cli` 和 `llama-server`，几十分钟能缩短到几分钟。
已编译的库会被复用，重复执行是安全的。

## 手动步骤（脚本出问题时的参考）

```bash
pkg update && pkg install -y git cmake clang make
git clone --depth 1 https://github.com/ggml-org/llama.cpp ~/llama.cpp
cmake -S ~/llama.cpp -B ~/llama.cpp/build -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF
cmake --build ~/llama.cpp/build --config Release -j$(nproc)
```

编译产物在 `~/llama.cpp/build/bin/`。

## 在手机上怎么用

### 方式一：浏览器聊天界面（最省事，推荐）

服务跑起来后，直接在手机浏览器打开：

```
http://127.0.0.1:8080
```

就能看到官方 Web 聊天界面（支持多轮对话、参数调节），不用记任何命令。
局域网里其他设备（电脑、平板）用 `http://<手机IP>:8080` 访问，手机 IP 在
设置 → WLAN → 当前网络里看，或 `ifconfig | grep 'inet '`。

启停服务用 `start-server.sh`：

```bash
bash ~/start-server.sh          # 启动（后台常驻）
bash ~/start-server.sh stop     # 停止
bash ~/start-server.sh status   # 查看状态和访问地址
```

> **重要：Web 界面资源要单独装。** 官方 Android 二进制**不含内置 UI**
> （编译时下不到），不装的话浏览器打开会报 `Error: gzip is not supported by this browser`
> 加 HTTP 415。需要额外下载 `llama-<tag>-ui.tar.gz`（3 MB），
> 并用 `--path` 指向解压后的 `index.html` 所在目录：
>
> ```bash
> UI_DIR=~/llama-android/ui/llama-b11146   # 注意包里多一层 tag 目录
> llama-server -m <模型> --path "$UI_DIR" ...
> ```

### 方式二：Termux 里命令行对话

```bash
llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 8 -c 2048
```

会出现带边框的交互界面和 `>` 提示符，直接输入问题回车。退出用 `/exit`。
内置命令：`/regen` 重新生成、`/clear` 清空历史、`/read <文件>` 附加文本文件。

单次提问（回答完自动退出并打印速度）：

```bash
llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 8 -c 2048 -n 128 -st -p "你的问题"
```

### 方式三：当 API 用（给其他程序调用）

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"你好"}],"max_tokens":128}'
```

接口与 OpenAI 兼容，任何支持自定义 base_url 的客户端都能接
（Cherry Studio、ChatterUI、NextChat 等），base_url 填 `http://<手机IP>:8080/v1`。

## 常用命令

```bash
# 交互对话（带边框界面，输入问题回车即可）
llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 -t 8

# 单次提问（-st = 单轮，回答完自动退出并打印速度）
llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 -t 8 -n 128 -st -p "你好"

# OpenAI 兼容服务（无界面，用 curl / 浏览器访问）
llama-server -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 -t 8 --host 0.0.0.0 --port 8080 --jinja

# 后台常驻
nohup llama-server -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 2048 -t 8 --host 0.0.0.0 --port 8080 --jinja > ~/server.log 2>&1 &
```

> `-st` 是单轮模式，回答完直接退出。**不加 `-st` 会进入交互界面并等待输入**，
> 脚本或管道里调用时容易看起来像卡死，务必加上。
> 旧版本的 `-no-cnv` 已被移除，用它会报 `invalid argument: -no-cnv`。

验证服务是否正常：

```bash
curl http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"你好"}]}'
```

局域网内其他设备访问时用手机 WiFi IP（系统设置里查看，或 `pkg install net-tools && ifconfig`）。

## 量化与参数

模型首选 Qwen2.5-1.5B-Instruct，中文能力在这档里最好。量化版本：

- Q4_K_M（约 1.0 GB）：体积最小、速度最快，日常首选
- Q8_0（约 1.6 GB）：质量更好，1.5B 这个规模完全扛得住

不要用 FP16 原始权重，手机上既慢又占内存。

| 参数 | 建议值 | 说明 |
|---|---|---|
| `-c` | 2048~4096 | 上下文长度，1.5B 开太大纯浪费 |
| `-t` | 用满可用核心 | 本机 `nproc` = 8（8 物理核，无 SMT），实测 `-t 8`；一般手机设成大核数量 |
| `-n` | 256~512 | 单次最大输出 token |
| `-st` | 脚本/单次提问必加 | 单轮模式，回答完退出 |
| `--jinja` | server 模式建议加 | 使用模型自带对话模板 |

### 实测性能（华为 HBN-AL80，Android 12，16 GB，8 核）

| 场景 | 提示处理 | 生成 |
|---|---|---|
| `llama-cli` 单轮 | 59.4 t/s | 20.4 t/s |
| `llama-server` HTTP | 57.8 t/s | 18.2 t/s |

模型 Qwen2.5-1.5B-Instruct Q4_K_M（1.04 GB），上下文 2048，`-t 8`。
生成速度已接近原文档里「旗舰机型 40~60 tok/s」的水平，远高于 4 GB 入门机的预估。

模型加载后常驻内存约 **1.9 GB**（`VmRSS`），16 GB 内存余量很充裕，
可以放心换更大的 3B 模型。

## 常见问题

**`pkg` 报一大堆错 / 提示仓库不可用**：多半是 Play 版 Termux，换 F-Droid 版重装。

**编译中断或报 OOM**：用 `bash termux-llama-setup.sh -j2` 降低并行度重跑，已编译部分会复用。

**`Permission denied`**：`/sdcard` 是 noexec 挂载，脚本必须先 `cp` 到 `~` 再执行。

**切到后台就被杀**：设置 → 应用 → Termux → 电池 → 无限制；再从最近任务列表锁定 Termux。

**速度只有几 tok/s**：检查 `-t` 是否设成了大核数量（一般 4），以及手机是否在降频（插电发烫时明显掉速）。

**想换模型**：任何 GGUF 都能用，放进 `~/models/` 改 `-m` 路径即可，例如
DeepSeek-R1-Distill-Qwen-1.5B、Llama-3.2-1B、Gemma-2-2B。带 thinking 的模型要限制思考长度，
否则输出很长、体感很慢。

## 目录里已经准备好的东西

| 文件 | 说明 |
|---|---|
| `C:\Users\18343\Downloads\qwen2.5-1.5b-instruct-q4_k_m.gguf` | 已有模型，1.04 GB，SHA256 已校验，部署脚本会自动找到它 |
| `termux-llama-setup.sh` | 手机端一键安装脚本（装依赖 → 编译 → 下载模型 → 打印用法） |
| `tools/termux-universal.apk` | Termux v0.118.3（GitHub 官方 release，SHA256 已校验） |
| `tools/platform-tools/` | ADB，用于从电脑推送文件到手机 |
| `tools/deploy-to-phone.ps1` | 电脑端推送脚本：装 Termux + 推模型和脚本到手机 |

## 路线 A：电脑推送（手机插数据线，省事）

1. 手机打开开发者选项（设置 → 关于手机 → 连点版本号 7 次），再打开「USB 调试」
2. 数据线连电脑，手机上点「允许 USB 调试」
3. 电脑上执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy-to-phone.ps1
```

脚本会自动装 Termux、把模型和安装脚本推进 `/sdcard/Download/termux-deploy/`，并在手机上打开 Termux。
最后在手机 Termux 里长按 → Paste，粘贴脚本打印出来的那一行命令即可（模型已经在手机上，不会再下载）。

## 路线 B：纯手动（不用数据线）

1. 手机装 Termux（`tools/termux-universal.apk`，或 F-Droid）
2. 把 `C:\Users\18343\Downloads\qwen2.5-1.5b-instruct-q4_k_m.gguf` 和 `termux-llama-setup.sh` 传到手机 `/sdcard/Download/`
3. Termux 里执行

```bash
cp /sdcard/Download/termux-llama-setup.sh ~/
mkdir -p ~/models && cp /sdcard/Download/qwen2.5-1.5b-instruct-q4_k_m.gguf ~/models/
bash ~/termux-llama-setup.sh
```
