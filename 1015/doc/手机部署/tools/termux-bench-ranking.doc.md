# termux-bench-ranking.sh 说明

配套脚本：[termux-bench-ranking.sh](termux-bench-ranking.sh)

## 职责

把手机上现有的五个 Q4_K_M 小模型放进同一场次测速，产出可排名、可复核的原始数据。
只负责测量与落盘，不做评分与排名结论。

## 输入

```text
模型      ~/models/Qwen3-0.6B-Q4_K_M.gguf          596 M
          ~/models/Qwen3.5-0.8B-Q4_K_M.gguf        752 M   SSM 混合
          ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf  1.78 B  纯注意力
          ~/models/Qwen3-1.7B-Q4_K_M.gguf          1.72 B  纯注意力
          ~/models/Qwen3.5-2B-Q4_K_M.gguf          1.88 B  SSM 混合
依赖      llama-bench（llama-cpp 0.6.0）
```

## 输出

```text
~/speed-results/rank-<时间戳>/
    metadata.txt     系统、运行时、五个模型的 SHA-256
    b1-06.json …     基线正序 d=0，-r 3
    b2-35.json …     基线逆序 d=0，-r 3
    d512-06.json …   深度 512，-r 2
    d2048-*.json     深度 2048
    d4096-*.json     深度 4096
    *.stderr.log     每次调用的原始 stderr
~/bench-ranking.log  全过程日志，含每次运行前后的频率读数
```

## 固定参数

```text
-ngl 0 -dev none -nkvo 1 -nopo 1 -t 4 -fa off
-ctk f16 -ctv f16 -b 512 -ub 128 --repack 1
```

与仓库 `phone-speed-bench.py` 的默认设置一致。`-t 4` 是这台机器实测的最优线程数，
往上加会因跨簇访存让 decode 掉 30% 以上。

## 顺序设计

```text
基线   正序 06→08→15→17→35 与逆序 35→17→15→08→06 各一轮
       └ 两个方向的差可以互相抵消：若某模型只在正序里快，
         说明它吃到的是开场低温，而不是模型本身快

深度   深度放外层，模型放内层，方向逐层翻转
       d=512   06→08→15→17→35
       d=2048  35→17→15→08→06
       d=4096  06→08→15→17→35
       └ 让每个模型都拿到过早、中、晚三种槽位
```

## 不负责

不杀任何推理进程，不评答案质量，不判断名次是否可信。
运行前必须自行确认没有 llama-server 在跑（它会同时抢 CPU 与内存带宽），
质量评分请用 `phone-model-ranking.py`。
