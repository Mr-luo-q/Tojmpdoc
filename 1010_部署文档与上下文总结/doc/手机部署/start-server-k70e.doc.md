# start-server-k70e.sh 说明

## 这个脚本解决什么问题

在红米 K70E 上启停 llama.cpp 的 HTTP 服务，并支持四个已实测模型之间切换。

它与上一台设备（华为 Pura 70）那份 `start-server.sh` 的关键区别在于**默认参数不同，而且这些参数都是实测确定、不能随手改的**。上一台用的是手工装的 `llama-android` 预编译包，二进制在 `~/llama-android/llama-b11146/`，需要手设 `LD_LIBRARY_PATH` 并用 `--path` 指向单独下载的 Web UI；这台用的是 Termux 官方 `llama-cpp` 包，二进制在 `/usr/bin` 下，依赖由包管理器管理，不需要手设库路径。

## 输入

### 命令行参数

```text
（无）              启动服务，默认 Qwen2.5-1.5B
stop               停止服务
status             查看状态、访问地址、健康检查
log                看日志尾部
```

### 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `MODEL` | `15` | 选模型，见下表 |
| `THREADS` | `4` | 线程数。**实测最优，不要改** |
| `CTX` | 见下 | 上下文长度 |
| `PORT` | `8080` | 监听端口 |
| `THINK` | `0` | 是否允许思考模式 |

### 模型代号与实测数据

```text
代号                    模型                 pp128    tg64    说明
──────────────────────────────────────────────────────────────────────────
15（默认）              Qwen2.5-1.5B        28.54    18.86   通用
06 / 0.6 / qwen3-0.6    Qwen3-0.6B          80.41    43.19   最快，浅上下文首选
17 / 1.7 / qwen3-1.7    Qwen3-1.7B          25.10    15.44   深上下文衰减重
35 / 2b / qwen35        Qwen3.5-2B          22.45    13.52   混合架构，长对话首选
```

上下文长度按模型自动区分：选 `35`（Qwen3.5-2B）时默认 `4096`，其余默认 `2048`。Qwen3.5-2B 虽然支持 262144，但手机内存有限且实测 decode 随上下文衰减，所以不默认放开。

## 输出

启动成功后打印模型名、线程数、上下文、思考模式开关状态、本机与局域网访问地址。服务本身以 `nohup` 后台运行，日志写入 `~/server.log`。

## 三个实测确定的关键参数

**1. `-t 4`，不要用 `-t 8`。**

这台机器的 CPU 是三簇结构（cpu0-3 A510 2.2GHz / cpu4-6 A715 3.2GHz / cpu7 A720 3.35GHz）。实测：

```text
线程数    pp512    tg128
   4      约 22    约 15~16     ← 最优
   6      约 21    约 11
   8      约 22    约 7.8       ← tg 掉一半
```

prefill 与 decode 对线程数的响应方向相反。原因是线程跨越频率跨度大的簇时会反复迁移，破坏缓存局部性，而 decode 是访存受限的，受害最重。

**2. `-ngl 0`，必须显式指定。**

Mali-G615 虽然能被 llama.cpp 认出（`Vulkan0: Mali-G615 MC6`），但实测比 CPU 慢 10~20 倍。硬件原因是 `ggml_vulkan` 报告的 `int dot: 0`——不支持整数点积，而 Q4_K_M 这类量化的推理核心就是整数点积，只能退化到通用 ALU 模拟。

**3. `--reasoning off`，默认关闭思考模式。**

Qwen3 与 Qwen3.5 默认开启思考模式，会把 `max_tokens` 全花在思考上、`content` 返回空字符串，表现为「模型不回答」。实测四种关法：

```text
不加参数                  content=""                    无效
--reasoning-budget 0      content="Okay, the user..."   无效
--reasoning off           content="2"                   有效
--chat-template-kwargs    content="2"                   有效
```

采用最简洁的 `--reasoning off`。**Qwen3.5-2B 换了混合架构，但这个行为完全一致**，所以同一套参数对新模型照样有效。需要思考能力时用 `THINK=1` 启动。

## Web UI 资源

官方 Android/Termux 的 `llama-cpp` 包不含内置界面，缺失时浏览器打开返回 HTTP 415（44 字节）。脚本会从 `~/.llama-ui-path` 读取 UI 目录并传给 `--path`。

这个文件由 `termux-install-ui.sh` 生成。注意 `ui.tar.gz` 解开后内部多一层 tag 目录（`llama-b11429/`），`--path` 指错一层同样报 415。

若该文件不存在，脚本会告警但仍能启动（只是浏览器界面不可用）。

## 不负责

不改系统任何设置。不改动模型文件。不做 GPU/NPU 相关配置（已实测不可用，显式固定为纯 CPU）。

## 用法

```bash
bash ~/start-server.sh                    # 启动，1.5B
MODEL=06 bash ~/start-server.sh           # 启动，0.6B（最快）
MODEL=35 bash ~/start-server.sh           # 启动，Qwen3.5-2B（长对话）
CTX=8192 MODEL=35 bash ~/start-server.sh  # 长上下文
THINK=1 MODEL=17 bash ~/start-server.sh   # 开启思考模式
bash ~/start-server.sh stop               # 停止
bash ~/start-server.sh status             # 状态
bash ~/start-server.sh log                # 日志
```

## 相关文件

```text
~/start-server.sh                        本脚本（从 start-server-k70e.sh 拷入）
~/server.log                             服务日志
~/.llama-ui-path                         Web UI 目录路径（由 install-ui 写入）
~/llama-ui/llama-b11429/                 Web UI 资源
~/models/*.gguf                          四个模型

tools/termux-check-server.sh             全面自检（进程/健康/UI/模型/地址）
tools/termux-install-ui.sh               安装 Web UI 资源

Token速率详表.md                           prefill/decode 曲线与三后端对比
四模型架构与性能对比.md                     四模型架构差异与深度衰减
```
