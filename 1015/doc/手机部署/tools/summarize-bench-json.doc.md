# summarize-bench-json.py 说明

配套脚本：[summarize-bench-json.py](summarize-bench-json.py)

## 职责

把 [termux-bench-qwen35-08.sh](termux-bench-qwen35-08.sh) 与
[termux-bench-ranking.sh](termux-bench-ranking.sh) 产出的「一组一个 JSON」的
llama-bench 原始输出，聚合成三张 Markdown 表：逐次原始值、分组矩阵、跨组合并中位数。
它只读结果文件，不接触手机。

## 与既有汇总脚本的分工

```text
phone-speed-bench.py  →  results.tsv（A/B 交错写在一张表里）
                        └─ summarize-speed-results.py 读它

termux-bench-qwen35-08.sh  →  s0-06-a.json / s3-08-b.json …（一组一个文件）
                              └─ summarize-bench-json.py 读它
```

两套格式来自两种编排方式，前者由脚本内部生成 ABBA，后者由 shell 手工编排顺序。
不要把两个汇总脚本互换使用：`results.tsv` 里没有 `n_depth` 字段，
而 JSON 里没有 `experiment` 与 `arm` 这两个由 shell 命名的列。

## 输入

```text
位置      一个或多个结果目录，例如 ~/speed-results/rank-20261015-221321
文件名约定 <组>-<模型>[-<分支>].json
          s1-06-a   组 s1，Qwen3-0.6B，第一次
          b1-35     组 b1，Qwen3.5-2B，基线正序
          d2048-15  组 d2048，Qwen2.5-1.5B，深度 2048
字段      取 model_filename、n_prompt、n_gen、n_depth、n_threads、
          flash_attn、avg_ts、stddev_ts、samples_ts
```

## 输出

```text
第一张表  逐次原始值：每个 JSON 的每一行，保留线程数、FA 开关、样本数
第二张表  分组矩阵：按「深度 + 组 + 负载形状」分行，每个模型一列取中位数
第三张表  跨组合并：把同深度、同负载的所有组一起取中位数，并标出样本数 n
          排名用这一张，单组矩阵用于核对组间是否一致
```

样本数 n 小于 3 时中位数不够稳，需要回看 `bench-ranking.log` 里的频率读数，
确认各次运行是否处在同一档频点。

## 用法

```powershell
python tools/summarize-bench-json.py research/speed-20261015/device-20261015/s3-depth ^
    --title "S3 深度扫描" --out s3-summary.md
```

## 不负责

不判断收益是否可信，不做显著性检验，不解释频率漂移。失败行会被跳过并单独列出文件名，
不会以 0 混入中位数。
