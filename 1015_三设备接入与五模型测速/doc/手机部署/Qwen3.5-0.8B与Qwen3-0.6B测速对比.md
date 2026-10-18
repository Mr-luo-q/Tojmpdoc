# Qwen3.5-0.8B 与 Qwen3-0.6B 同口径测速 · Redmi K70E

实测日期：2026-10-15 21:36–22:02

```text
设备      Redmi K70E（2311DRK48C，duchamp），MediaTek MT6897 天玑 8300-Ultra
系统      Android 16（SDK 36），HyperOS OS3.0.305.0.WNLCNXM
运行时    llama-cpp 0.6.0（Termux 包），Clang 21.0.0 构建，纯 CPU
后端      -ngl 0，无 GPU、无 NPU、无 KV 卸载、无算子卸载
量化      两者均为 Q4_K_M，参数规模 0.6B 与 0.8B
```

模型身份（SHA-256）：

```text
Qwen3-0.6B-Q4_K_M.gguf      596,049,920 参数   390,753,280 字节
    ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a

Qwen3.5-0.8B-Q4_K_M.gguf    752,393,024 参数   532,517,120 字节
    bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517
```

## 一、结论

两者不是同一档位的替代关系，交叉点出现在上下文 512 到 2048 token 之间。

```text
浅上下文（< 512 token）      0.6B 更快
    短问短答、单轮工具调用、纯速度优先的场景
    tg 45.3 vs 31.6（历史口径），0.6B 快 43%

深上下文（≥ 2048 token）     0.8B 反超，且差距随深度拉大
    d=2048   0.8B 快 43%
    d=4096   0.8B 快 87%，两者的最差/最好样本不重叠，结论稳健

三个可能的提速维度，只有一个是真空间
    线程数   已榨干，t4 就是最优，往上加只掉 decode
    FA 开关  分阶段取舍，prefill 涨与 decode 跌同时发生
    架构     真正的变量。0.8B 是 SSM 混合架构，深上下文衰减只有 0.6B 的一半
```

答案质量上 0.6B 反而占优：三道有唯一答案的题里，0.6B 对两题，0.8B 只对一题，
两道算术题全部算错。追求长上下文吞吐选 0.8B，追求短对话速度与基本正确率选 0.6B。

## 二、测量口径

```text
标准口径（S1/S2/S3/S4）
    -ngl 0 -dev none -nkvo 1 -nopo 1 -t 4 -fa off
    -ctk f16 -ctv f16 -b 512 -ub 128 --repack 1
    -p 128 -n 64，重复 2~3 次，--no-warmup
    与仓库 phone-speed-bench.py 的默认设置一致，便于与既有结论对接

历史口径（S0）
    -ngl 0 -t 4 -p 128 -n 64 -r 3 --no-warmup
    与《四模型架构与性能对比》同参数，用于把新数据接回旧表
```

每个实验用 ABBA 顺序各跑一次（06 → 08 → 08 → 06），取两次的中位数。
这台机器的主频随温度持续漂移，把两个模型前后跑完会把温度差记成模型差。

```text
频率采样（每次运行前后各记一次，节选）
    s0-06-a   前 cpu4=600    后 cpu4=2660
    s3-06-a   前 cpu4=1500   后 cpu4=2400
    s3-06-b   后 cpu4=1400   （最后一次，已处热尾段）

漂移后果：S3 里 0.6B 的两次 d=0 相差 21%（70.33 与 55.55），
这是热状态差异，不是模型抖动。结论只取两次都成立的方向。
```

## 三、基线：0.8B 在两个口径下都更慢

| 口径 | 模型 | pp128 t/s | tg64 t/s | 0.8B / 0.6B |
|---|---|---|---|---|
| S0 历史 | Qwen3-0.6B | 81.39 | 45.26 | — |
| S0 历史 | Qwen3.5-0.8B | 62.31 | 31.55 | pp 0.77 / tg 0.70 |
| S1 标准 | Qwen3-0.6B | 70.81 | 40.15 | — |
| S1 标准 | Qwen3.5-0.8B | 60.89 | 30.78 | pp 0.86 / tg 0.77 |

两个口径的绝对值差异来自参数：标准口径显式关掉 FA、固定 f16 KV，
比历史口径慢约 12%（0.6B pp 81.39 → 70.81）。同一口径内两者可比，跨口径不可比。

S1 的重复性很好：0.6B 两次 70.76 与 70.86，0.8B 两次 61.32 与 60.46，
离散度都在 1.5% 以内，说明浅上下文区间的差异是真实的模型差异。

## 四、线程数：没有剩余空间

| 模型 | 线程 | pp t/s | tg t/s | tg 相对 t4 |
|---|---|---|---|---|
| 0.8B | 2 | 31.64 | 17.60 | −44.1% |
| 0.8B | 4 | 61.27 | 31.47 | 基准 |
| 0.8B | 6 | 56.13 | 18.64 | −40.8% |
| 0.8B | 8 | 61.01 | 20.76 | −34.0% |
| 0.6B | 4 | 70.76 | 40.60 | 基准 |
| 0.6B | 8 | 76.04 | 23.27 | −42.7% |

```text
两个模型给出同一个形状
    t2            算力不够，pp/tg 一起掉
    t4            最优，decode 拉满
    t6 / t8       pp 基本持平甚至小涨，tg 掉 34%~43%

原因      这台机器是三簇结构（4×A510 + 3×A715 + 1×A720）。
          decode 阶段是访存受限，线程一旦跨到小核簇，
          访存局部性被破坏，多出来的算力补不回损失。

结论      《CPU性能实测报告》里 t4 最优的结论对新模型同样成立，
          0.8B 上没有可以靠调线程拿到的收益。
```

## 五、上下文深度：交叉点在 512~2048 之间

| 深度 | 0.6B pp | 0.6B tg | 0.8B pp | 0.8B tg | tg 谁快 |
|---|---|---|---|---|---|
| 0 | 62.94 | 36.47 | 50.02 | 27.74 | 0.6B 快 31% |
| 512 | 49.89 | 27.67 | 47.97 | 25.37 | 基本持平 |
| 2048 | 29.21 | 15.75 | 42.67 | 22.52 | **0.8B 快 43%** |
| 4096 | 18.84 | 9.81 | 35.46 | 18.30 | **0.8B 快 87%** |

从 d=0 到 d=4096 的衰减：

```text
Qwen3-0.6B      pp 62.94 → 18.84    −70.1%
                tg 36.47 →  9.81    −73.1%

Qwen3.5-0.8B    pp 50.02 → 35.46    −29.1%
                tg 27.74 → 18.30    −34.0%

衰减比      0.6B 的衰减幅度是 0.8B 的两倍以上
```

稳健性检查，看两次 ABBA 样本的极值是否重叠：

```text
d=4096 tg   0.6B [9.32, 10.29]     0.8B [18.25, 18.34]    不重叠，可靠
d=2048 tg   0.6B [14.51, 17.00]    0.8B [21.56, 23.48]    不重叠，可靠
d=512  tg   0.6B [24.72, 30.61]    0.8B [24.00, 26.74]    重叠，只能算持平
d=0    tg   0.6B [32.44, 40.51]    0.8B [27.38, 28.10]    不重叠，可靠

d=0 那行 0.6B 的上界 40.51 取自热尾段之前的一次运行，
而 0.8B 两次都在热稳定之后。把 0.6B 压到最不利的 32.44、
与 0.8B 最有利的 28.10 相比，0.6B 仍快 15%，方向不变。
```

架构层面的解释（GGUF 元数据实测）：

```text
                        Qwen3-0.6B        Qwen3.5-0.8B
general.architecture    qwen3             qwen35
block_count             28                24
attention.head_count    16                8
head_count_kv           8                 2
key/value_length        128               256
context_length          40960             262144
rope.freq_base          1e6               1e7
SSM 字段                无                full_attention_interval = 4
                                          ssm.state_size = 128
                                          ssm.group_count = 16
                                          ssm.conv_kernel = 4
```

```text
Qwen3-0.6B      28 层全部是标准自注意力
                每生成一个 token 要扫描全部历史位置的 K/V
                上下文翻倍，扫描量翻倍

Qwen3.5-0.8B    24 层里每 4 层才有 1 层全注意力（共 6 层），其余是 SSM 层
                SSM 的状态是固定大小的递归状态，不随上下文增长
                需要扫描历史的部分只剩约四分之一
```

衰减比例对得上：0.8B 的 tg 衰减 34%，0.6B 是 73%，比值 0.47。
全注意力层数之比是 6/28 = 0.21，比 0.47 更小，说明衰减虽然主要来自全注意力层，
但 SSM 层本身在深上下文下也有固定开销，两者不是严格成比例。

## 六、Flash Attention：prefill 与 decode 方向相反

在 d=2048 下切换 `-fa`，其余参数不动：

| 模型 | fa | pp t/s | tg t/s | pp 变化 | tg 变化 |
|---|---|---|---|---|---|
| 0.6B | off | 27.36 | 14.51 | 基准 | 基准 |
| 0.6B | on | 45.16 | 10.62 | **+65.1%** | **−26.8%** |
| 0.8B | off | 40.74 | 21.53 | 基准 | 基准 |
| 0.8B | on | 44.82 | 20.65 | +10.0% | −4.1% |

```text
0.6B 对 FA 极其敏感     28 层全是注意力，FA 直接作用在这 28 层上，
                        2048 深度的 prefill 提速 65%，代价是 decode 掉 27%

0.8B 几乎不受 FA 影响   只有 6 层全注意力，FA 能优化的对象少了四分之三，
                        prefill 只 +10%，decode 只 −4%

实用含义
    长提示词 + 短回答（摘要、抽取、分类）  开 FA，收益立刻兑现
    短提示词 + 长回答（写作、对话）        关 FA，decode 才是瓶颈
    0.8B 上这个开关几乎无所谓，保持默认即可
```

## 七、答案质量：0.6B 反而更稳

三道具唯一正确答案的题，同参数（`-fa off -ctk f16 -n 128 -st --reasoning off`）各问一次：

| 题 | 考点 | Qwen3-0.6B | Qwen3.5-0.8B |
|---|---|---|---|
| 01 | JSON 抽取，total=41、currency=CNY | `"total": 3 * 12 + 5` 非法 JSON | `[{"total": 39, ...}]` 数值算错 |
| 02 | 订单字段抽取 | 全对 | 全对 |
| 06 | 17×23−19=372 | 372（带推理过程） | **22（错）** |

```text
逐题判定
    0.6B    题01 格式错、题02 对、题06 对          2 / 3
    0.8B    题01 数值错、题02 对、题06 数值错      1 / 3

失败模式
    0.6B 知道公式但直接把表达式写进 JSON 字段，没做求值
    0.8B 两次真算错了：3×12+5 得 39，17×23−19 得 22
```

思考模式的成本，同一题、同一预算 `-n 64`：

```text
Qwen3-0.6B       默认开思考   [Start thinking] 占满 64 token，content 为空
                 --reasoning off  直接输出 "2 + 2 equals 4."

Qwen3.5-0.8B     默认开思考   [Start thinking] Thinking Process: 1. Analyze... 同样占满
                 --reasoning off  直接输出 "2+2 equals 4."

两者行为一致：默认开、必须显式关闭。服务端 --reasoning off 对 0.8B 同样有效，
不需要为新模型单独适配。关闭后速度不变（pp 44.0 → 44.3，tg 25.7 → 24.8）。
```

## 八、选型

```text
上下文 < 512 token（短问短答、单轮工具调用、翻译改写）
    → Qwen3-0.6B    tg 40 vs 31（标准口径），快 30% 且答案更稳

上下文 512 ~ 2048（多轮对话、带少量背景的问答）
    → 两者接近，按回答质量决定。本批数据里 0.6B 更稳

上下文 > 2048（长文档、长对话、长背景）
    → Qwen3.5-0.8B  衰减只有一半，d=4096 时快 87%

长提示词 + 短回答   0.6B 开 -fa on 可以再拿 65% 的 prefill
长提示词 + 长回答   保持 -fa off
线程数              两个模型都固定 -t 4
```

## 九、复现步骤

```powershell
# 1. 取模型（hf-mirror 实测 8 MB/s）
curl.exe -L -o C:\Users\18343\Downloads\Qwen3.5-0.8B-Q4_K_M.gguf `
  https://hf-mirror.com/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf

# 2. 推送并校验（目标必须写完整文件名，写目录会被截断）
tools/platform-tools/adb.exe push C:\Users\18343\Downloads\Qwen3.5-0.8B-Q4_K_M.gguf `
  /data/local/tmp/Qwen3.5-0.8B-Q4_K_M.gguf
tools/platform-tools/adb.exe shell run-as com.termux cp /data/local/tmp/Qwen3.5-0.8B-Q4_K_M.gguf `
  /data/data/com.termux/files/home/models/Qwen3.5-0.8B-Q4_K_M.gguf
tools/platform-tools/adb.exe shell run-as com.termux sha256sum `
  /data/data/com.termux/files/home/models/Qwen3.5-0.8B-Q4_K_M.gguf
```

```bash
# 3. 手机上跑（测速前确认没有 llama-server 在跑，它会抢 CPU 与带宽）
bash termux-bench-qwen35-08.sh          # 约 26 分钟，产出 ~/speed-results/0608-*/
bash termux-quality-0608.sh             # 约 27 秒，产出 ~/quality-0608.log

# 4. 取回结果
adb exec-out run-as com.termux tar -czf - -C <结果目录> . > 0608-results.tar.gz
```

```powershell
# 5. 汇总成表
python tools/summarize-bench-json.py research/speed-20261015/device-20261015 `
    --out research/speed-20261015/device-20261015/汇总.md
```

## 十、已知局限

```text
1. 质量对照每题只问了一次，没有多次采样，不能作为严格的能力排名。
   结论只到「0.8B 在这两道算术题上答错」这一层。

2. 主频在测量期间持续漂移，S3 里 0.6B 的 d=0 两次相差 21%。
   已用 ABBA 与极值区间处理，绝对值的精度只到区间级别。

3. 没有测热降频的稳态：本批全部在插电、无风扇、起始温度 30°C 上下完成，
   连续跑 30 分钟之后的稳态速率低于本表数字。

4. 没有测 HTTP 路径的首字延迟与流式表现，
   本表是 llama-bench 的裸吞吐，与界面上的体感不完全等价。

5. 0.8B 标称 262144 上下文，本批最深只测到 4096。
```

## 十一、对应文件

```text
tools/termux-bench-qwen35-08.sh        本次测速脚本
tools/termux-bench-qwen35-08.doc.md    测速脚本说明
tools/termux-quality-0608.sh           质量对照脚本
tools/termux-quality-0608.doc.md       质量脚本说明
tools/summarize-bench-json.py          JSON 结果汇总
tools/summarize-bench-json.doc.md      汇总脚本说明

research/speed-20261015/device-20261015/
    0608-results.tar.gz                手机上结果目录的原始归档
    汇总.md                            自动生成的两张对照表
    s*.json / s*.stderr.log            20 组原始 llama-bench 输出
    metadata.txt                       系统、运行时、模型哈希取证

手机上
    ~/bench-qwen35-08.log              测速全过程日志（含频率采样）
    ~/quality-0608.log                 三题答案原文

相关文档
    四模型架构与性能对比.md             0.6B / 1.5B / 1.7B / 3.5-2B 的旧结论
    手机提速实测结果-20261014.md        线程、FA、KV 量化的前一轮实测
    Token速率详表.md                    前两个模型的 prefill/decode 曲线
```
