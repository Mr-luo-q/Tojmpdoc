# termux-speed-env.sh 中文说明

职责：提速复现的第 0 步。把设备、系统、运行时、模型、当前负载和可读的温度节点一次性记录下来，作为后续所有 t/s 数字的对照身份。全程只读，不安装、不停服务、不改模型。

输入：无参数。需要以 Termux 应用身份运行，否则读不到 `~/models` 和私有目录。

输出：`~/speed-environment/env-snapshot.log`，分 8 段。

```text
1 采集时间与运行身份   时间戳、uid、PREFIX
2 系统与 SoC           Android 版本/SDK、SoC 型号、内核、电源模式
3 CPU 拓扑与特性        Features 行、nproc、各核 cpuinfo_max_freq
4 内存                 MemTotal / MemAvailable / Swap
5 运行时版本           llama-cpp 等包版本、llama-bench --version、二进制哈希
6 llama-bench 参数     完整 --help，用于核对复现脚本所需选项是否存在
7 模型文件             四个 GGUF 的大小与 0.6B / 1.5B 的 SHA-256
8 温度与电源节点        尽力读取，被拒时记录 Permission denied
9 推理进程             遍历 /proc 找出 llama-server 等
```

第 6 段是关键判定依据：`--device`、`--no-kv-offload`、`--no-op-offload`、`--repack`、`--flash-attn`、`--cache-type-k`、`-d` 缺任何一个，[phone-speed-bench.py](phone-speed-bench.py) 都会拒绝运行并提示，而不是换一组参数悄悄跑。

读取：`getprop`、`/proc`、sysfs、`dpkg-query`、模型文件。写入：`~/speed-environment/`。

不负责：性能测量、服务开关、温度控制。手机无 root 时读不到 SoC 热区是预期结果，脚本会记成 Permission denied，不会填 0 冒充读数。

```bash
# 电脑侧调用（以 Termux 应用身份执行）
tools/platform-tools/adb.exe shell run-as com.termux \
  /data/data/com.termux/files/home/scripts/termux-run.sh \
  shell bash /data/data/com.termux/files/home/scripts/termux-speed-env.sh

# 取回快照
tools/platform-tools/adb.exe shell run-as com.termux cat \
  /data/data/com.termux/files/home/speed-environment/env-snapshot.log > env-snapshot.log
```
