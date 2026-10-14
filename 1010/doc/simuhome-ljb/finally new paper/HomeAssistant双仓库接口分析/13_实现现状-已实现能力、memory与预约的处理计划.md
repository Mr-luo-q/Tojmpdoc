# 实现现状：已实现能力、memory 与预约的处理计划

本文盘点 2026-09-18 这一刻 MCP server 的真实状态，并写清两个还没实现的工具
（`memory`、`time_control`）怎么处理、计划怎么处理。数字都来自本机实测，
设计口径以 11 号文档为准、论文取舍以 `UbiComp三支柱讨论\12_投稿策略` 为准。

## 0. 一句话结论

```text
已实现   8 个工具里的 6 个（观察 3 个 + 控制 1 个 + 判定 1 个 + 事件 1 个），全部在真 HA 上跑通
未实现   time_control（含预约）是空实现，runtime 的 sqlite 与调度器也没写
可验收   契约 12/12、真机端到端 21/21、大模型冒烟 9/9、降级与恢复 21/21
记忆     2026-09-18 晚定稿：memory 工具保留，但按 SMH 的口径简化成只读——
         记忆由实验方准备成文件，memory() 原样返回整段；工具面仍是 8 个
下一步   先补两处规格（cancel 的 schedule_id、time 配置段）；advance 与相对时间已拍板去掉
         （2026-10-06），再按 M4a/M4b/M4c 开工
```

## 1. 已实现的功能

```text
M1（2026-09-17）  协议壳与骨架：entry / server / errors / contract 四件 / runtime(配置)
                  backend_ha：client(REST+WS) + mapping(注册表映射) + tools/ 八个文件
                  observe_home 做实：3 房间 + 4 环境量 + 虚拟时间
M2（2026-09-18）  inspect_room / inspect_device / query_events 做实
                  动作表 ACTIONS_BY_KIND；mapping 加 collect_env / summarize_state / to_number
                  query_events 两层默认过滤：只看本家庭实体、排除 sensor.simuhome_virtual_time
M3（2026-09-18）  execute_action：四道闸门 + 回读；check_goal：conditions + keep
                  契约补齐 C 口径（switch 3 / climate 5 / fan 4）；状态收敛成六字段
降级验证（09-18）  停发布器 / 停 broker / 重建发现三例全过；
                  掉线时六字段给 null（原来把 unavailable 说成 on=false）；
                  补上 verified=false 的分支测试（假 HA 吞写入）
一键拉起（09-18）  _tools\start_simuhome_stack.ps1：Docker → HA → SimuHome → 载入 home_full.json
                  → broker → 发布器，末尾自检 25 实体 / 0 unavailable
```

真机基线（可复核）：25 个 simuhome 实体 = 9 switch + 2 climate + 1 fan + 13 sensor；
设备注册 16 条 = 12 台可控 + 3 台房间虚拟设备 + 1 台网关；HA 2026.6.4；
一次命令 + 回读 236~388 ms；虚拟时钟 1:1（实测 20.0 s 对 20.0 s）。

## 2. 可用的接口

### 2.1 对外 8 个 MCP 工具（模型能调的）

| 工具 | 参数（? = 可选） | 返回 | 状态 |
| --- | --- | --- | --- |
| `observe_home` | 无 | rooms{name, env{}, devices[]} + time + counts | 已实现 |
| `inspect_room` | `room_id` | room{room_id, name, env{}, devices[], doors:null} | 已实现 |
| `inspect_device` | `device_id` | device{device_id, area_id, kind, state{}, actions[]} | 已实现 |
| `execute_action` | `device_id`、`action`、`?params` | result{device_id, action, state_after{}, steps[], elapsed_ms, verified, ?verify_note} | 已实现 |
| `check_goal` | `conditions`、`?keep` | goals[...] + keep[...] + all_pass | 已实现 |
| `query_events` | `?since`、`?until`、`?entity_id`、`?limit` | events[{ts, entity_id, state, name}] | 已实现（扩展项） |
| `time_control` | `op`(schedule/list/cancel)、`?at`、`?steps`、`?schedule_id` | {schedule_id} 或预约数组 | 未实现（NOT_IMPLEMENTED） |
| `memory` | 无（简化后） | `{text}`：整段记忆原文 | 未实现；新计划改成只读版（见 3.2） |

两点要注意：一是模型在 `tools/list` 里只看得到 `summary` + 参数的 JSON Schema，
契约里的 `returns` 字段不进模型视野（它是对内文档）；二是 `execute_action` 实际返回
`verified` 与 `verify_note`，契约的 `returns` 文本还没补这两个字段（见第 5 节待修项）。

### 2.2 规范动作与状态字段（工具层语义）

```text
动作词表 8 个   turn_on / turn_off / toggle（三类设备都有）
                set_mode(off|cool|heat)、set_temperature(7~32, 步长 0.5)   空调
                set_percentage(0~100)                                      风扇
                set_brightness / set_position                              词表预留（当前无 light / cover）
每类动作数      switch 3 / climate 5 / fan 4（真机逐类断言过）
状态字段 6 个   on / mode / target / level / position / current
                掉线（unavailable / unknown）或读不到 → 字段全为 null
```

### 2.3 支撑接口（server 依赖的下层）

```text
HA REST      /api/states、/api/states/{entity_id}、/api/services/{domain}/{service}、/api/logbook
HA WS        config/entity_registry/list、config/device_registry/list、config/area_registry/list
MQTT 主题    上行 state / mode / target_temp / current_temp / percent / <room>.<metric> / time
             下行 set / set_mode / set_temp / set_percent；可用性 simuhome/v1/status；回执 simuhome/v1/events
             （完整表见 11 号文档 §4.2，别在两处维护）
```

### 2.4 错误码（12 个，代码里全定义）

```text
HA_UNREACHABLE / UNKNOWN_DEVICE / UNKNOWN_ROOM / DEVICE_UNAVAILABLE / UNSUPPORTED_ACTION /
SERVICE_ERROR / VERIFY_TIMEOUT / INVALID_TIME / UNKNOWN_KEY / BAD_TARGET / BAD_REQUEST / NOT_IMPLEMENTED

已用到   除 VERIFY_TIMEOUT / INVALID_TIME / UNKNOWN_KEY 外的 9 个
未用到   INVALID_TIME 与 VERIFY_TIMEOUT 是给 M4 准备的（预约时间在过去 / 回读超时口径）；
         UNKNOWN_KEY 是原键值记忆留下的，简化成只读整段后没有 key 了，实际不会用到，
         先留在错误码表里备用
```

## 3. memory 怎么处理、计划怎么处理

### 3.1 现状

```text
代码      src\home_mcp\backend_ha\tools\memory.py 是空实现 → 抛 NOT_IMPLEMENTED
契约      memory(op=read|write, key, value?) → {key, value, updated_at}
          错误：UNKNOWN_KEY / BAD_REQUEST / NOT_IMPLEMENTED
存储      还没有。原设计是 sqlite 的 memory 表，2026-09-18 晚改成读文件（见 3.2）
落点      ha_mcp_server\data\memory.yaml（config 的 memory.file，相对配置文件目录）
          该目录已在 .gitignore 里（/ha_mcp_server/data/）
```

原设计是键值工具：模型通过 `memory(write)` 写键值、用 `memory(read)` 读回来，存在 sqlite。
SMH-Bench 走的是另一条路——记忆整段给定（`{{memory_list}}` 上下文注入），
12 号文档把它记为扩展项、不进论文主张。2026-09-18 晚定稿：工具保留，但按 SMH 的口径简化成
只读整段（细节见 3.2，理由见 3.3、3.4）。

### 3.2 计划

```text
做法（M4）   实验方把记忆写成 data\memory.yaml；服务端启动时读一次
工具行为     memory()（无参数）→ 原样返回整段记忆文本；只读，不给 key、不做写入
契约改动     memory 的 params 清空（去掉 op / key / value），returns 改成 {text}；
             memory.py 改成读文件返回；UNKNOWN_KEY 暂时用不到，先留在错误码表里
验收         调 memory() 返回的内容与 data\memory.yaml 一致；文件缺失时返回空记忆且不报错
不做的       写入、key-value、sqlite memory 表、遗忘策略、语义检索、跨实例共享
论文口径     扩展项：记忆由实验方给 → 只能测"会不会用"，测不到"会不会记"，如实写进 scoping
```

### 3.3 与 SMH-Bench 的记忆方案对比

先把两边的事实摆出来（SMH 侧来自它正文的 TC6 与附录 G 的提示模板）：

```text
SMH-Bench：记忆是"题目给、模型用"
  提示模板里直接拼：## 家庭环境 {{home_environment}}  ## 用户记忆 {{memory_list}}
  TC6 个性化记忆分两种：短期记忆（最近的交互事实）、长期记忆（存储的用户偏好）
  判分前提写死："该任务不应在未使用所提供的记忆的情况下，以预期方式解决"
  EIA 的工具面是"查询属性 / 检索服务 / 执行操作"——记忆不在工具面里，是从上下文进来的

我们（旧设计）：记忆是"模型自己写、按需取"
  memory(read | write, key, value?) + sqlite 的 memory 表；不自动进上下文，要模型主动调 read
```

| 维度 | SMH-Bench（上下文注入） | 我们旧设计（工具 + sqlite） |
| --- | --- | --- |
| 记忆从哪来 | 评测生成，随题面给 | 模型自己写 |
| 模型怎么拿到 | 每轮都在上下文里 | 主动按 key 取 |
| 上下文成本 | 记忆越长越贵，无关记忆还会干扰 | 只花用到的那一条 |
| 失败模式 | 几乎没有"没拿到"这一条 | 多三条：该记没记、该查没查、key 写错或覆盖 |
| 可复现性 | 高（同题同记忆） | 低（依赖模型行为，跨会话才显形） |
| 测到的能力 | 会不会用（读） | 会不会记 + 会不会用 + 记忆治理 |
| 实现成本 | 0（拼字符串） | 半天（一张表 + 两个 op + 验收） |
| 离真实部署 | 远（记忆由评测方准备） | 近（助手自己攒） |
| 跨后端一致性 | 与后端无关 | 与后端无关，两个后端共用同一张表 |

```text
SMH 式的优势   把"会不会用记忆"做成可判定任务：确定、可复现、判分简单
工具式的优势   贴近真实部署，且两个后端都能用同一份实现；能顺带观察"记"这一环
工具式的代价   评测方差大：模型忘了查就等于任务失败，会把"记忆能力"和"检索自觉性"混在一起
SMH 式的代价   记忆由评测方准备，测不到"记"；每轮注入会稀释注意力，记忆一多就是噪声
               （SMH 自己的错误分类里就盯"过度使用工具、低效交互"这类问题）
```

2026-09-18 晚定稿：采用 SMH 的"记忆给定"口径，但保留工具外壳——工具不删，只是把内部
简化成"读文件、返回整段"。理由是判据落在端侧小模型上（见 3.4）：小模型只需要记住
"调 memory 这么一个无参数工具"，不用学 key 词表，也不会出现"写 bedtime 读 sleep_time"。
后续怎么落：

```text
1 memory 工具保留，params 清空（去掉 op / key / value），returns 改成 {text}；工具面仍是 8 个
2 记忆写成 data\memory.yaml，服务端启动时读一次，memory() 原样返回整段
3 以后真要做"模型自己攒记忆"，再把 write 加回来，报告分两栏：给定记忆的使用率、
  自主记忆的保持率，两者不要混成一个指标
4 scoping 写清：不做遗忘策略、不做语义检索、不做跨用户隔离
  （语义检索是 PersonalHomeBench 的路线：它有"获取_家庭_记忆 / 获取_家庭成员_记忆"
   这类自然语言查询工具，比我们的键值取法重一档）
```

### 3.4 判据要落在"端侧小模型学不学得会"

功能齐不齐不是关键，这套接口最终的消费者是小模型。所以判据是：
**小模型吃这个接口要花多少学习代价**（零样本成功率 + 学会所需的轨迹数），
而不是"方案本身先不先进"。

SMH-Bench 自己的数据可以先当先验（它有 4B 级模型的结果）：

```text
工具对中档开源模型是净收益   Qwen3.5-9B / GLM-5 在有工具的 EIA 下比纯推理的 DR 平均 +15.1% / +10.9%
但小模型只能扛原子操作    最小模型 Qwen3.5-4B：TC1 原子控制 69.3% / 76.0% 还行，
                        TC4 复合任务掉到 21.3%
代价是级联                论文自己写：EIA 会引入"多步级联错误"（DR 靠单次全局推理规避）
典型错误                  无效工具调用（缺参、None、参数名错）+ 低效交互（过度调用工具）
```

对着我们现在的接口看，小模型要过的坎在哪：

```text
一次开灯 3 次调用   inspect_room → inspect_device → execute_action
                   每一步都是一次决策，级联风险按步数放大（SMH 点名的两类错误都在这里）
记忆若是"全工具"    还要自己决定"要不要查、用哪个 key"；key 是自由字符串，
                   小模型最容易写 "bedtime"、读 "sleep_time" → 直接对应 SMH 说的"参数名错"
我们目前的数据      只有 DeepSeek flash（大模型）的冒烟 9/9；4B 级小模型一次都没测过
                   → "小模型是否适配"目前是未验证项，文档里不能当已知
```

按"小模型友好度"排的三条口径：

```text
采用：只读工具（SMH 口径）  记忆整段给定，工具只读返回；模型零决策，但记忆要模型主动取
A 注入式（SMH 原样）       记忆整段进上下文：更零决策，但吃上下文窗口、对噪声敏感，
                          客户端未必支持（依赖 instructions 字段）
B 混合                    读注入 + 留 write 工具：小模型不用学"怎么查"，仍能自己攒
C 全工具（原设计）         read 与 write 都靠模型自己调：最贴近部署，学习成本最高
```

当前决定：工具保留、只读整段（参数最少，调用动作单一）。下面这套验证方案先留档，
等要评估"小模型适配"或要加回写入能力时再跑——它本身就是支柱 2 训练实验的前置。

```text
硬件      本机 31.5 GB 内存 + RTX 5060 8 GB 显存：4B 4-bit 没问题，8B 4-bit 勉强
模型梯度  Qwen3-4B（本地）+ 一个 8~9B + 一个强模型作上限
任务      同一批：原子动作 / 先查再动（2~3 步）/ 记忆类（TC6 型：给定偏好 + 跨会话）
三条臂    A 注入 / B 混合 / C 全工具（其余完全一致：同一套工具契约、同一批任务）
指标      ① 任务成功率 ② 工具调用步数 ③ 非法调用率 ④ 该调未调率 ⑤ 跨会话记忆一致性
学习成本  再用 N 条轨迹做小规模 SFT（正好接支柱 2），看"到 X% 成功率要多少条轨迹"
判据      C 臂上 4B 明显差于 B、且训练要明显更多轨迹 → 维持只读工具（或退成注入 A）
```

对 M4 的影响：

```text
记忆部分：memory 工具改成只读版（清空 params、读 data\memory.yaml 返回整段）——半天里的一部分
时间部分：time_control 与预约机制不受影响，按第 4 节原计划走
不新增：sqlite 的 memory 表（schedules / calls 两张表仍然要）
```

## 4. 预约机制怎么处理、计划怎么处理

### 4.1 现状

```text
代码      src\home_mcp\backend_ha\tools\time_control.py 是空实现 → 抛 NOT_IMPLEMENTED
调度器    没有。runtime.py 只有配置加载（78 行），没有 sqlite、没有后台循环
契约      time_control(op=schedule|list|cancel, at?, steps?, schedule_id?)
两处缺口   ① cancel 没有 schedule_id，"取消哪个预约"没法表达；list 也没有窗口或状态过滤
          ② config.example.yaml 里没有 time 段（时区 / 预约期限 / 清理策略没地方配）
          （原第②条 advance 上限已作废：2026-10-06 拍板去掉 advance 与相对时间）
```

### 4.2 计划

三个 op 的语义：

```text
schedule(at, steps) at 是绝对时间（ISO，未来），steps 是 [{device_id, action, params}]
                   → 校验 at 在未来（过去 → INVALID_TIME）、逐个动作过 execute_action 的同一套闸门
                   → 写一行 schedules(id, due_at, steps, status='pending', created_at) → 返回 {schedule_id}
list(?)            列出本实例的预约与结果（M4 先返回全部，窗口过滤二期）
cancel(schedule_id) pending → cancelled；已完成/已取消失败 → BAD_REQUEST 并说明当前状态
                   advance 与相对时间已拍板去掉（2026-10-06），不做等待
```

调度器的位置与执行路径：

```text
谁起     L1（entry 组装），随 server 进程起；runtime 只提供 sqlite 读写，
         不允许 runtime import backend（否则破 11 号 §5.1 的依赖规则）
怎么跑   每 1 秒查一次 "due_at <= now 且 status='pending'"
到点     status 改 running → 按序调用 contract 层的 execute_action 实现
         （与模型直接调用同一条代码路径，保证语义一致）
         → 每步的回读、耗时、错误写进 result，status 改 done / failed
重启     启动时把 due_at > now 的 pending 行装回内存；已过期的标 missed（不静默补跑）
状态机   pending → running → done / failed；pending → cancelled；pending → missed
```

边界与 scoping（要写进文档，别让读者以为它能扛长时序）：

```text
生命周期   stdio 传输下客户端断开就等于调度停摆（server 进程随会话结束）
          → HA 侧只承诺"进程存活期间的秒级预约"；http 传输下随进程存活
时间尺度   虚拟时钟 1:1，空调 1.8 °C/h、风扇 0.72 °C/h
          → 分钟级以上的时序任务留给二期沙盒后端（快进），HA 侧不承诺
并发       单实例一个库；多实验实例各起一份 server + 各自 sqlite
```

工时拆分（比 11 号写的"约 1 天"多一点）：

```text
M4a  sqlite + calls + memory 只读化（清空参数、读 data\memory.yaml 返回整段）   0.5 天
M4b  schedule / list / cancel（调度器 + 重启装载）   1 天
M4c  三个单测（conditions / clock / runtime）+ M4 验收                 0.5 天
```

## 5. 开工前要先修的 5 处（都是文档或契约文本，不影响已实现行为）

```text
1  contract\tools.py 里 time_control 的 summary 还写着"advance 等到某时刻 / 条件"
   —— 按新口径改成"预约单：schedule 写单 / list 查单 / cancel 撕单"，
   这是模型在 tools/list 里读到的原文
2  execute_action 契约的 returns 文本没写 verified / verify_note（实现已经返回这两个字段）
3  VERIFY_TIMEOUT 只在 errors.py 与 time_control 契约里出现，代码里没人抛；
   本期 time_control 不再声明它（没有等待）；该码保留给二期条件等待，或从契约里删
4  派生目录 README 说"12 号以能力标签与动作词表为准"，但 12 号已取消能力标签体系
5  11 号 §3.2 的 _tools 清单漏了 start_simuhome_stack.ps1 / .md
另有一处死配置：发布器 discovery payload 里的 "object_id" 无效果（HA 的 MQTT discovery
只在主题段认 object_id，payload 键会被 schema 丢掉），可以删
记忆相关的改动（memory 只读化：清空 op / key / value 参数、returns 改成 {text}、
memory.py 改成读文件返回）随 M4 一起做；工具面仍是 8 个
```

## 6. 还没实现的总清单

```text
M4 范围      time_control（schedule / list / cancel）、runtime 的 sqlite 与调度器、
             memory 简化（只读返回 data\memory.yaml 的整段，不留 key / write / 表）、
             三个单测（conditions / clock / runtime）
M5 范围      第 10 节验收表填满、8 动作 × 2 后端覆盖率报告、calls 表统计、探针复跑
二期         query_topology（门磁或 edges 配置）、light / cover（亮度与窗帘位置）、
             backend_sandbox（同一份 contract 接 Gym 与快进）、资源 / 提示 / 进度 / 澄清
三期         双后端迁移实验（成对任务、成功率保持与适配成本）
已决定不做   长时间运行 soak（内存 / 日志 / 死锁）本轮不跑；录制器与进程守护不做
```

## 7. 怎么算做完（M4 的验收方式）

```text
参数校验     过去时间 → INVALID_TIME；steps 空 / 超限 → BAD_REQUEST；不带偏移的 at 按 home 时区解释
schedule     schedule(at=now+10s, steps=[关灯]) → {schedule_id}；
             list 里能看到 pending；10 秒后 list 显示 done，回读灯确为 off
cancel       schedule 之后立刻 cancel → list 显示 cancelled，到点灯不动
memory       调 memory() 返回的内容与 data\memory.yaml 一致；文件缺失时返回空记忆且不报错；
             工具面仍是 8 个（契约里 memory 的参数为空）
calls        M5 能直接 SQL 出"每个工具调了多少次、成功率、平均耗时"
回归         契约 12/12、真机端到端 21/21、大模型冒烟 9/9、降级与恢复 21/21 保持全绿
```
