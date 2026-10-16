# termux-quality-0608.sh 说明

配套脚本：[termux-quality-0608.sh](termux-quality-0608.sh)

## 职责

在同一个温度状态与同一套推理参数下，把 Qwen3-0.6B 与 Qwen3.5-0.8B 对三道有唯一正确答案的
题目各问一遍，用于判断「快一点」是否以答错为代价。

## 输入

```text
提示词   ~/prompts/题01.txt   JSON 抽取，正确结果 total=41、currency=CNY
         ~/prompts/题02.txt   订单字段抽取，要求字符与数量准确
         ~/prompts/题06.txt   17×23−19，正确结果 372
模型     ~/models/Qwen3-0.6B-Q4_K_M.gguf
         ~/models/Qwen3.5-0.8B-Q4_K_M.gguf
```

## 输出

`~/quality-0608.log`，按「模型 → 题号」分段，每段保留最后 14 行（答案区）。
模型加载日志被截掉，因为其中不含答案信息。

## 固定参数

```text
-ngl 0 -dev none -nkvo --no-op-offload -t 4 -c 2048
-fa off -ctk f16 -ctv f16 -n 128 -st --reasoning off
```

与测速用的标准口径一致，差别只在测速用 `-o json` 输出吞吐，这里用单轮提问输出文本。

## 为什么必须写 `--reasoning off`

Qwen3 与 Qwen3.5 默认开启思考模式，128 token 的预算会全部花在推理段上，
`content` 留空，表现为「模型不回答」。这不是模型坏掉，而是思考前缀吃掉了全部预算。
服务端 `start-server.sh` 用的也是同一个开关。

## 参数写法差异（连踩两次的坑）

```text
禁止 KV 卸载     llama-bench  -nkvo 1       llama-cli  -nkvo
禁止算子卸载     llama-bench  -nopo 1       llama-cli  --no-op-offload

把带值的写法搬到 llama-cli 会报 error: invalid argument: 1，
而且这个错误会在每一题上重复发生，日志里看不到任何答案。
```

## 不负责

不评估中文长文质量、指令遵循的细节约束、拒绝伪造等开放题；
这些题需要人读答案，属于人工验收环节。
