# 16：四个 Bench 的任务类型梳理（按 T 计数）

2026-10-07。目的：把四篇 benchmark（01 HomeBench、04 SimuHome、03 SMH-Bench、02 PersonalHomeBench）的任务类型按"有多少个 T"列清楚，并给出每一类的实例数量。数据来自 `4个bench\` 下的论文原文；分类口径参考同目录的《4个Bench分类对比.md》《4个Bench总结.md》。

## 1 一屏总览：每篇有多少个 T

```text
Bench              类型命名          类型数                        实例总量
-----------------------------------------------------------------------------
HomeBench          VS/IS/VM/IM/MM    5 类                          17 万+ 条指令
SimuHome           QT1~QT4           4 大类 / 6 查询类型 / 12 条件   600 回合
SMH-Bench          TC1~TC7           7 大类 / 22 子类               1,100 任务（分布口径见 §4）
PersonalHomeBench  IG/CF/MC/FR/PG   5 类（3 反应 + 2 主动）        9,168 任务
```

每篇的"T"命名不一样：HomeBench 是双字母缩写（VS/IS/…），SimuHome 是 QT，SMH-Bench 是 TC，PersonalHomeBench 是任务缩写（IG/CF/…）。下面逐篇拆开。

## 2 HomeBench：5 类

```text
VS  Valid Single        有效单设备指令：单设备、单方法，指令正确且可执行
IS  Invalid Single      无效单设备指令：单设备、单方法，但指令错误、不能执行
VM  Valid Multi         有效多设备指令：多设备多方法，全部正确可执行
IM  Invalid Multi       无效多设备指令：多设备多方法，全部错误、不能执行
MM  Mixed Multi         混合多设备指令：多设备多方法，有些正确有些错误
```

论文表 2 给出的指令数量（训练 / 验证 / 测试三档）：

```text
类型    训练集     验证集    测试集
VS      49,048     6,145     6,187
IS      53,771     6,731     6,765
VM       1,829       232       245
IM         826       124        97
MM      33,443     4,132     4,072
ALL    138,917    17,364    17,366

合计约 17.4 万条指令；100 个场景，每场景至少 47 台设备。
```

要点：5 类里两类是无效指令（IS / IM），一类是混合（MM）；这三类是 HomeBench 的核心考点（无效指令识别与拒绝）。

## 3 SimuHome：4 大类、6 个查询类型、12 个评测条件

```text
QT1  环境感知        正确感知环境条件与设备状态，并如实回答
QT2  隐含意图        从抱怨/间接表达里推断潜在目标
QT3  显式意图        准确执行指定设备 + 目标值的命令
QT4  时间推理（拆 3 个子类）
  QT4-1  未来调度     把多个设备调度到未来某个绝对时刻
  QT4-2  依赖调度     按设备完成时间建立依赖（如洗碗机洗完再开灯）
  QT4-3  并发调度     多个运行设备在时间约束下不冲突
```

```text
结构
  4 大类（QT1~QT4）
  其中 QT4 拆成 3 个子类 → 共 6 个查询类型
  每个查询类型再分可行（F）/ 不可行（IF）→ 12 个评测条件

数量
  每个评测条件 50 个回合
  12 × 50 = 600 回合（论文口径：12 种查询类型，600 回合）
```

要点：QT4 是唯一的时间/调度类，也是四篇里与我们的 time_control / 预约设计最直接对应的一类；QT1 是"先查状态再动作"的考点。

## 4 SMH-Bench：7 大类、22 子类

```text
TC1  Atomic Control                       原子控制：单意图、清晰/口语/带噪的措辞
TC2  Compositional Control                组合控制：多设备、状态依赖、房间依赖、选择式
TC3  Ambiguous Intent                     歧义意图：主观抱怨、场景级目标、指代不明
TC4  Automated Task Scheduling            自动化任务调度：持久的时间/状态触发规则
TC5  Context-Aware Multi-turn Interaction 上下文多轮：继承、修改、替换上一轮操作
TC6  Personalized Memory                  个性化记忆：短期记忆、长期偏好
TC7  Environment-Grounded Query           环境接地查询：只读检查与聚合，不改设备
```

论文正文给出的分类数量：

```text
TC1  原子控制              150
TC2  组合控制              250
TC3  歧义意图              150
TC4  自动化任务调度        150
TC5  上下文多轮            200
TC6  个性化记忆            100
TC7  环境接地查询          150
以上相加                  1,150

论文摘要/图里另有"1,100 个任务"的口径；
两者差 50，以最终发布的数据集为准（引用时注明口径）。
22 个细分子类；环境复杂度分简单(8台)/中等/复杂(135台)。
```

要点：TC4 是唯一真正的规则/调度类（persistent time- or state-triggered rules），包含"时间特定、状态驱动、时间+状态"三种玩法；TC6 是记忆类；这两类分别对应我们的 time_control 和 memory。

## 5 PersonalHomeBench：5 类（3 反应 + 2 主动）

```text
反应式（问答）
  IG  Information Grounding   信息接地：从家庭记忆/画像里检索事实并作答
  CF  Counterfactual          反事实：改动一个条件后推断结果（成对变体）
  MC  Multiple Choice         多项选择：受限选项下的信息接地

主动式（规划）
  FR  Feature Recommendation  特征推荐：按偏好做排序/推荐
  PG  Plan Generation         计划生成：生成结构化多步计划
```

论文给出的实例数量（纯文本子集 + 多模态子集）：

```text
类型    纯文本    多模态    合计
IG       1,000       742     1,742
CF       2,000     1,484     3,484
MC       1,000       742     1,742
FR       1,000       100     1,100
PG       1,000       100     1,100
合计     6,000     3,168     9,168
```

要点：5 类里 2 类是主动规划（FR/PG）；工具型 agent 设置下 IG/CF/PG 掉点最严重，"会不会主动查、会不会稳定调工具"是主要瓶颈。

## 6 横切对比

```text
维度              HomeBench        SimuHome        SMH-Bench         PersonalHomeBench
类型命名          VS/IS/VM/IM/MM   QT1~QT4         TC1~TC7           IG/CF/MC/FR/PG
类型数            5                6（12 条件）     7（22 子类）       5
实例量            17万+ 指令       600 回合        1,100~1,150       9,168
时间/调度         ○                ●（QT4）        ●（TC4）          ◐
规则/自动化       ○                ◐               ●（TC4）          ○
记忆/个性化       ○                ○               ●（TC6）          ●（核心）
无效/拒绝         ●（IS/IM/MM）     ●（IF）         ●（TC3）          ◐
多设备组合        ●（VM/IM/MM）     ◐               ●（TC2）          ◐
```

## 7 与我们项目的关系

```text
SMH-Bench TC4 自动化调度     → time_control（一次性预约）+ manage_rule（持久规则，未实现）
SMH-Bench TC6 个性化记忆     → memory（整段文本读写）
SimuHome QT4 时间推理        → time_control 的时间/调度语义
HomeBench IS/IM/MM 无效指令  → finish 的 refused，以及 execute_action 的错误码路径
PersonalHomeBench IG/CF      → memory 读、check_goal 判定
```

## 8 来源

```text
论文原文
  01  HomeBench（ACM CHI 2024，中文译本）
  04  SimuHome（2025 arXiv，中文译本）
  03  SMH-Bench（2026 arXiv，英文原文）
  02  PersonalHomeBench（2026 arXiv，中文译本）
  ——均在 finally new paper\4个bench\

已有梳理
  4个bench\4个Bench分类对比.md        三大类分组 + 四篇任务分类体系
  4个bench\4个Bench总结.md            逐篇总结（含任务类型与规模）
  三类内部对比分析-Bench四篇与方法BC.md  27 个方面的覆盖打表
```
