# termux-bench-qwen35-08.sh 说明

配套脚本：[termux-bench-qwen35-08.sh](termux-bench-qwen35-08.sh)

## 职责

在手机上用同一套参数、同一段热状态，比较 Qwen3-0.6B 与 Qwen3.5-0.8B 的 prefill 与 decode 速率，
并把原始结果按「一组一文件」落盘，供后续汇总与复核。

## 输入

```text
命令行    无参数，直接 bash termux-bench-qwen35-08.sh
模型      ~/models/Qwen3-0.6B-Q4_K_M.gguf
          ~/models/Qwen3.5-0.8B-Q4_K_M.gguf
依赖      llama-bench（llama-cpp 包自带）
```

## 输出

```text
~/speed-results/0608-<时间戳>/
    metadata.txt       系统版本、llama-bench 版本、两个模型的 SHA-256
    s0-06-a.json       每组一条：llama-bench -o json 原始输出
    s0-06-a.stderr.log 每组一份原始 stderr
    ...
~/bench-qwen35-08.log  全过程日志，含每次运行前后的频率读数
```

## 读取

只读取模型文件与 `/sys/devices/system/cpu/cpu{0,4,7}/cpufreq/scaling_cur_freq`，
不改动任何系统设置。频率采样仅作为「同批数据是否在同一热状态」的旁证。

## 写入

只写 `~/speed-results/0608-<时间戳>/` 与 `~/bench-qwen35-08.log`；
目录用时间戳命名，重复执行不会覆盖上一次的结果。

## 不负责

不负责下载模型，不负责开关 GPU/NPU 后端，不做质量评分，也不杀任何已有推理进程。
运行前请自行确认没有 llama-server / llama-cli 在跑，否则吞吐会被抢占。

## 实验组

```text
S0 历史口径基线   -p 128 -n 64 -d 0 -r 3 -t 4 -ngl 0
                  │ 与《四模型架构与性能对比》同参数，用于把新数据接回旧表
                  ▼
S1 标准口径基线   -ngl 0 -dev none -nkvo 1 -nopo 1 -t 4 -fa off
                  -ctk f16 -ctv f16 -b 512 -ub 128 --repack 1
                  │ 与仓库 phone-speed-bench.py 的默认设置一致
                  ▼
S2 线程扫描       t=2/4/6/8（0.8B 全扫，0.6B 抽 t4/t8 对照）
                  │ 验证「t4 最优」这条旧结论对新模型是否仍然成立
                  ▼
S3 深度扫描       -d 0,512,2048,4096
                  │ Qwen3.5 是注意力+SSM 混合架构，衰减应明显小于纯注意力
                  ▼
S4 深度 2048 FA   -fa off 与 -fa on 对照
```

## 为什么是 ABBA 顺序

```text
测量顺序   06 → 08 → 08 → 06

理由       K70E 的主频随温度持续漂移，先跑完 A 再跑完 B，
           会把「后跑的那个更热」记成「后跑的那个更慢」。
           ABBA 让两个模型各自经历一次「先跑」和「后跑」，
           取两次的中位数即可把单向漂移抵消掉大半。
```

## 判定口径

同一实验组的两次结果若偏差超过 10%，先怀疑热状态或后台进程，
不要直接把它解释成模型差异。此时应看 `bench-qwen35-08.log` 里每条记录前后的频率读数：
两次运行若频率档位不同，数据不可直接相减。
