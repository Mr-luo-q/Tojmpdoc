# termux-quality-check.sh 中文说明

职责：在接受 `-fa on -ctk q8_0 -ctv q8_0` 这类提速配置之前，确认它没有把答案改坏。同模型、同线程数、同上下文长度，只切换 KV 缓存类型，逐题对照。

输入：第一个参数是 GGUF 路径，第二个参数是标签（用于日志名）。提示词从 `~/prompts/题NN.txt` 读取。

输出：`~/quality-<标签>.log`。

```text
kv=f16   题01 / 题02 / 题06
kv=q8_0  题01 / 题02 / 题06
对照      fa off + f16，只跑题01，代表「默认档」的答案

固定参数  -t 4 -ngl 0 -dev none -nkvo --no-op-offload -c 2048 -fa on -n 128 -st --reasoning off
```

**必须带 `--reasoning off`。** Qwen3 默认开启思考模式，第一版脚本用 `-n 96` 且没关思考，六次输出全部停在推理段中间被截断，一个 JSON 字段都没产生——那样测的是思考前缀而不是答案。这与服务端 `start-server.sh` 里已经在用的 `--reasoning off` 是同一件事。

**参数写法差异（连踩两次，必须记住）**：同一个参数在两个程序里写法不同，而且报错会静默发生在每一题上，整份日志只剩重复的错误行。

| 参数 | `llama-bench` | `llama-cli` |
|---|---|---|
| 禁止 KV 卸载 | `-nkvo 1`（要取值） | `-nkvo`（不带值） |
| 禁止算子卸载 | `-nopo 1`（有短别名） | 只有 `--no-op-offload`，**没有短别名** |

把 `-nkvo 1` 搬到 `llama-cli` 会报 `error: invalid argument: 1`；把 `-nopo` 搬过去会报 `error: invalid argument: -nopo`。

为什么只挑这三题：01（JSON 抽取，total=41）与 02（订单字段抽取）考结构化输出是否仍然合法，06（17×23−19=372）有唯一数值答案，都能一眼判定对错。04、08 之类带长度与用词约束的开放题需要人读，放进人工验收而不混进自动对照。

为什么用 `-f` 传题：中文提示词走 shell 参数会被编码破坏，走文件不会。

读取：模型文件、`~/prompts/`。写入：`~/quality-<标签>.log`。不负责：中文长文质量、指令遵循的全面评估；日志里 `tail -20` 只保留答案区，模型加载日志被截掉。

```bash
tools/platform-tools/adb.exe push tools/termux-quality-check.sh /data/local/tmp/termux-quality-check.sh
tools/platform-tools/adb.exe shell run-as com.termux cp /data/local/tmp/termux-quality-check.sh \
  /data/data/com.termux/files/home/scripts/termux-quality-check.sh
tools/platform-tools/adb.exe shell run-as com.termux \
  /data/data/com.termux/files/home/scripts/termux-run.sh \
  shell bash /data/data/com.termux/files/home/scripts/termux-quality-check.sh \
  /data/data/com.termux/files/home/models/Qwen3-0.6B-Q4_K_M.gguf 06
```
