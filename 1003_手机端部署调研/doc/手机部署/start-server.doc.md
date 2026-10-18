# start-server.sh 说明文档

## 一、职责

在手机 Termux 里启动 / 停止 / 查询 `llama-server`，并选择使用哪个模型。
它把三件容易出错的事一次性处理好，让人不必每次手敲一长串参数。

```text
输入                                    输出
──────────────────────────────────────────────────────────────────
MODEL=15|06        选模型              后台起一个 llama-server 进程
THREADS=8          线程数              写入 ~/server.log
CTX=2048           上下文              打印访问地址与当前配置
PORT=8080          端口
THINK=0|1          思考模式
stop / status      子命令
```

## 二、它替你挡掉的四个坑

这四个坑都是本项目实测踩出来的，每一个都会让人以为「服务坏了」。

**第一，动态库找不到。** Android 的 bionic linker 不支持 `$ORIGIN` RPATH，
直接跑解压出来的二进制会报 `library "libllama-server-impl.so" not found`。
脚本显式导出 `LD_LIBRARY_PATH` 指向二进制所在目录来绕开。

**第二，Web 界面打不开。** 官方 Android 包不含内置 UI，缺失时浏览器报
`Error: gzip is not supported by this browser`（HTTP 415）。
脚本用 `--path` 指向 `~/llama-android/ui/llama-b11146`。

**第三，Qwen3 回答为空。** Qwen3 默认开启思考模式，会把 `max_tokens` 全花在思考上、
`content` 返回空字符串。脚本默认加 `--reasoning off` 在服务端关掉。
需要思考能力时用 `THINK=1`。

**第四，家目录判断错。** 通过 `adb shell run-as com.termux` 调用时，
`$HOME` 可能是 `/data/user/0/com.termux`，而 Termux 真正的家目录是
`/data/data/com.termux/files/home`。脚本从**自身路径**推导家目录，
并保留硬编码兜底，这样在 Termux 里直接跑和在 adb 下跑都正确。

## 三、命令行用法

```bash
bash ~/start-server.sh               # 启动，默认 1.5B
MODEL=06 bash ~/start-server.sh      # 启动，用 0.6B（快约 3 倍）
THINK=1 bash ~/start-server.sh       # 允许思考模式
bash ~/start-server.sh stop          # 停止
bash ~/start-server.sh status        # 查看状态与当前模型
```

可覆盖的环境变量：

| 变量 | 默认 | 含义 |
|---|---|---|
| `MODEL` | `15` | `15` 用 1.5B，`06` 用 0.6B |
| `THREADS` | `8` | 线程数。本机 `nproc` 为 8，实测 `-t 8` 最优 |
| `CTX` | `2048` | 上下文长度 |
| `PORT` | `8080` | 端口 |
| `THINK` | `0` | `1` 允许思考模式 |

## 四、启动时实际执行的命令

```bash
LD_LIBRARY_PATH=<二进制目录>:<Termux lib>
nohup <D>/llama-server -m <模型> -t 8 -c 2048 \
  --host 0.0.0.0 --port 8080 --jinja \
  --path <UI 目录> --metrics \
  [--reasoning off] > ~/server.log 2>&1 &
```

各参数的作用：

```text
-m            模型文件路径
-t 8          线程数，8 = 本机全部物理核
-c 2048       上下文长度
--host 0.0.0.0 监听所有网卡，局域网其他设备可访问
--port 8080   端口
--jinja       使用模型自带的对话模板
--path        静态资源目录，提供 Web 聊天界面
--metrics     开启 /metrics 端点，返回 Prometheus 格式指标
--reasoning off  关闭思考模式（THINK=0 时）
```

## 五、内部函数

| 函数 | 职责 |
|---|---|
| `server_pids()` | 扫 `/proc/*/comm`，找出所有 llama-server 的 PID。不用 `pgrep`，因为 Termux 下不保证有 |
| `lan_ip()` | 从 `ifconfig` 提取非 127.0.0.1 的 IPv4，用于打印局域网访问地址 |
| `current_model()` | 从 `server.log` 尾部抓 `models/xxx.gguf`，让 status 能显示当前加载的模型 |
| `stop_server()` | 逐个 `kill -9`，并报告是否本来就没有在跑 |
| `status_server()` | 打印 PID、两个访问地址、当前模型、思考模式开关状态 |

服务就绪的判定是轮询 `/health` 直到返回 `ok`，最多等 40 秒。
比固定 `sleep` 可靠 —— 模型加载耗时随模型大小变化（1.5B 约 2 秒，更大模型更久）。

## 六、实测验证状态

**已验证的事实**

| 验证项 | 结果 |
|---|---|
| 启动 1.5B 并返回 `服务已就绪` | 通过，`/health` 返回 `{"status":"ok"}` |
| 启动 0.6B（`MODEL=06`） | 通过，日志与 `/v1/models` 均确认加载的是 Qwen3-0.6B |
| `stop` 子命令 | 通过，正确报告「已停止 PID xxxx」 |
| `status` 子命令 | 通过，显示 PID、地址、当前模型、思考模式 |
| `--reasoning off` 生效 | 通过，`finish_reason` 由 `length` 变为 `stop`，content 不再是空 |
| Web 界面可访问 | 通过，`/` 与 `/docs-*.html` 均返回 HTTP 200 |
| 从 adb 与从 Termux 两种方式调用 | 通过（家目录推导 + PATH 兜底同时覆盖两种场景） |

**待确认的风险**

`THREADS`、`CTX`、`PORT` 三个覆盖变量没有逐一实测。默认值均已验证可用。

## 七、两个使用上的注意事项

**服务不会自动随手机重启启动。** 手机重启、或 Termux 被系统彻底清掉后，
需要重新执行 `bash ~/start-server.sh`。这是 Android 对普通应用的限制，不是脚本问题。

**持续跑会热降频。** 实测 SoC 温度从 46°C 升到 73°C 只需一个 15 秒的基准测试，
`cpu7` 频率上限会被热保护从 2.30GHz 逐步压到 335MHz（最低档），
此时生成速度从 22.6 t/s 掉到 5.6 t/s。要恢复满速只能静置降温。
用 0.6B 模型可把温升从 +36°C 降到 +18°C，这也是推荐它的原因之一。

详细数据见 [提速调研报告.md](../提速调研报告.md)。
