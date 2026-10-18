# summarize-speed-results.py 中文说明

职责：把 [phone-speed-bench.py](phone-speed-bench.py) 产出的逐调用 `results.tsv` 聚合成 Markdown 对照表，省去手工算中位数与收益。只读结果，不碰手机。

输入：一个或多个结果目录（或直接给 results.tsv 路径）；`--label` 写明当时的电源、散热等条件。

输出：`--out` 指定的 Markdown 文件（UTF-8），含模型、实验、深度、负载形状、A/B 中位数、B/A 收益百分比、分块方向、有效样本数。不给 `--out` 时打印到标准输出，Windows 中文控制台可能显示成问号，以文件为准。

```text
分组键 = 模型 + 实验 + 已有深度 + 负载形状(n_prompt/n_gen)

  为什么必须这样分：pp 与 tg 是两种负载，
  t4 与 t8 的 tg 差一倍而 pp 几乎不变，
  混在一起聚合会得到一个没有意义的平均值。

每个分组：
  取 A 的中位数与 B 的中位数 → 收益 = B/A - 1
  再逐块比对方向 → 「一致」表示几个复验块都朝同一方向动
```

失败行策略：`status != OK` 或没有 `avg_ts` 的行不计入统计，只计数量并在表头报告。这样失败配置不会以 0 或空值混进中位数。

```powershell
python tools/summarize-speed-results.py research/speed-20261014/device-20261014/06-threads --label "AC充电 enhance 无风扇" --out 06-threads-summary.md
```

输入解码使用 `utf-8-sig` 以容忍 BOM。经 PowerShell 的 `>` 重定向拉取的文件会变成 UTF-16，本脚本会以解码错误拒绝，需要改用 `cmd /c "adb exec-out ... > 文件"` 重新拉取。

读取：结果目录。写入：无。不负责：判断收益是否可信（那要看分块方向与原始日志）、统计显著性、热状态解释。
