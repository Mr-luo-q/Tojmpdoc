# phone-speed-bench.py 中文说明

职责：在 Termux 运行 `llama-bench`，以单变量、ABBA 顺序比较 CPU 参数。默认运行基线，不安装依赖、不停服务、不改电源策略、不修改 GGUF。

控制台使用UTF-8；输出文件也为UTF-8。

输入：`--models` 为一个或多个 GGUF 路径；`--bench` 可指定隔离构建的绝对路径；`--label` 人工注明电源模式、是否充电与散热条件；`--out` 必须是尚不存在的目录。

```text
--suite baseline   A 一次，模型 pp128 与 tg64 分别测试
--suite threads    A=t4，B=t2/t3/t6/t8
--suite batch      A=ub128，B=ub64/ub256/ub512，b 固定 512
--suite repack     A=重排开，B=重排关
--suite attention FA off/on；FA on 条件下分别比较 f16/q8_0 和 f16/q4_0
                   --depths 0 2048 指定上下文已有 token 数

每个 A/B 实验 → A → B → B → A
每次调用      → 内部重复 --repetitions 次（默认 3，保留预热）
每组之间      → 等待 --cooldown 秒（默认 15，只是间隔，不保证已经冷却）
```

CPU 控制固定为 `-ngl 0 -dev none -nkvo 1 -nopo 1`。脚本核对本机 `--help` 的必要选项，缺少就退出。`-p` 与 `-n` 分别产生 pp、tg 行，tg 的已有上下文由 `-d` 指定，不把 `-p` 自动算入 tg。

输出目录的 `metadata.txt` 保存版本、系统属性、CPU 特性、模型哈希和人工条件标签；`help.txt` 保存本机帮助；`results.tsv` 是逐测试汇总；`NNN-command.txt` 保存实际参数数组；`NNN-stdout.log` 和 `NNN-stderr.log` 保存原始结果和后端日志；`NNN-freq.tsv` 每秒保存 sysfs 频率读数。不可读的节点标成 `unavailable`，不作为零频率。

```bash
python ~/scripts/phone-speed-bench.py --models ~/models/Qwen3-0.6B-Q4_K_M.gguf --dry-run
python ~/scripts/phone-speed-bench.py --models ~/models/Qwen3-0.6B-Q4_K_M.gguf --suite attention --depths 0 2048 --out ~/speed-results/06-attention --label standard-unplugged-no-fan
```

读取：模型文件、`/proc`、sysfs、系统工具与基准帮助。写入：新输出目录。若可见推理进程仍运行则退出；Android 隐藏的进程无法完整检查，需要人工核对后台。模型哈希在正式计时前计算，正式测试保留 llama-bench 预热，不代表冷启动。

失败：依赖或必要选项缺失、模型不存在、输出目录已存在，退出码 1。每个实验调用有 `--timeout` 限制，失败不填 t/s；A 基线失败就停止，B 失败会保存记录并继续。拒绝非 JSON 数组、空结果、非有限值或无有效 `avg_ts` 的输出。结果 TSV 必须结合原始 stderr 确认 FA、KV 类型及实际张量位置。

不负责：聊天质量、TTFT、电量或热状态的测量；也不把 `backend` 列作为张量放置证据。HTTP 延迟由 [measure-phone-stream.py](measure-phone-stream.py) 测量。完整实验与验收见 [手机小模型提速调研与复现.md](../手机小模型提速调研与复现.md)。
