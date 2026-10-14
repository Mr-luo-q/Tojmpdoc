# termux-start-bench-server.sh 中文说明

职责：为「首字延迟 / 前缀缓存」这类必须走真实 HTTP 的测量启动一个受控的 llama-server。默认端口 8081，与日常 `start-server.sh` 的 8080 互不干扰，可以同时存在。

输入：`<模型路径> [端口] [fa] [kv]`，或 `stop <端口>`。fa 取 `on|off|auto`，kv 取 `f16|q8_0|q4_0`。

输出：`~/bench-server-<端口>.log`，包含加载日志与每次请求的计时。

```text
固定参数（全部显式写出，不依赖默认值）
├─ -t 4 -tb 4            生成与批处理同为 4，避免引入第二个变量
├─ -c 4096 -b 512 -ub 128
├─ -ngl 0 --device none   双重禁用 GPU
├─ --no-kv-offload --no-op-offload
├─ -fa <fa> -ctk <kv> -ctv <kv>
├─ --jinja --reasoning off  关闭 Qwen3 默认思考
└─ --parallel 1 --metrics

启动流程
├─ 先按端口停掉同名旧服务，避免两个进程抢核
├─ nohup 后台启动，日志落盘
└─ 轮询 /health 最多 60 秒，就绪返回 0，失败则打印日志末尾并返回 1
```

为什么必须显式写 `-fa` 与 `--device none`：`-fa` 的默认 `auto` 会随上下文深度切换行为，`-ngl 0` 也不足以保证张量留在 CPU（本机装有 Vulkan 后端）。做对照实验时这两个默认值都会污染结论。

读取：模型文件、`/proc`（用于按端口定位旧进程）。写入：日志文件。不负责：停掉日常 8080 服务（`stop` 只按端口匹配）；也不负责测量本身，测量用 [measure-phone-stream.py](measure-phone-stream.py)。

```bash
tools/platform-tools/adb.exe push tools/termux-start-bench-server.sh /data/local/tmp/
tools/platform-tools/adb.exe shell run-as com.termux cp /data/local/tmp/termux-start-bench-server.sh \
  /data/data/com.termux/files/home/scripts/
tools/platform-tools/adb.exe shell run-as com.termux \
  /data/data/com.termux/files/home/scripts/termux-run.sh \
  shell bash /data/data/com.termux/files/home/scripts/termux-start-bench-server.sh \
  /data/data/com.termux/files/home/models/Qwen3-0.6B-Q4_K_M.gguf 8081 on f16
tools/platform-tools/adb.exe shell run-as com.termux \
  /data/data/com.termux/files/home/scripts/termux-run.sh \
  shell bash /data/data/com.termux/files/home/scripts/termux-start-bench-server.sh stop 8081
```
