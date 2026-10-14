# context2：MCP 落地、米家接入与 v2 通用化（2026-09-17 ~ 09-27 全过程记录）

本文件用于新对话接续，接在 `context1.md`（HA 接入方案与 MCP 设计，09-16~09-17）之后。
写法沿用 context1：把**怎么问的、怎么查的、怎么判断的、踩了什么坑**完整记下来，
不是交付清单。数字都是本机实测，标注了日期。

```text
工作目录      D:\D_coderesource\simuhome
本轮跨度      2026-09-17 ~ 09-27
本轮目标      把 MCP 从"设计"推到"能跑、能验收、能接真实设备"，并为通用化开分叉
当前状态      v1（沙盒版）冻结；v2（通用版）M1/M2 完成，已能读写真实的米家冰箱
远端仓库      https://github.com/juezhan340/simuhome（private，main，push 需走本机代理）
```

## 0. 一分钟结论

```text
实现      v1 ha_mcp_server：8 个工具（6 个做实），契约 12/12、真机端到端 21/21、降级 21/21、大模型冒烟 9/9
调研      外界控制 HA 的六条路线（A 内置对话代理 / B 官方 MCP / C 社区 MCP / D 反向 MCP / E 自建 / F 传统）
          B、C 都在本机跑通并量过接口面：B 12 工具≈1137 token，C 29 工具≈8907 token，E 8 工具≈1000 token
米家      官方插件 xiaomi_home v0.4.7 接入成功（账号 2646196763，中国大陆），导入 1 台对开门冰箱
分叉      ha_mcp_universal（v2）：M1 认领层、M2 角色层都完成；冰箱被拆成 cold/freeze 两台逻辑设备，
          用现有 8 个接口就能读能写（set_temperature / set_mode 都实测 verified）
未做      M3（命名泛化 + 第三方集成抽样）暂缓——目前只有米家一台真实设备，样本不够
```

## 1. 时间线（按日期）

### 1.1 09-17：v1 骨架与设计定稿

```text
M1 完成       entry / server / errors / contract 四件 / runtime(配置) / backend_ha（client+mapping+8 个工具骨架）
              observe_home 做实：3 房间 + 4 环境量 + 虚拟时间；契约 7/7、端到端 4/4
11 号文档      重写为"自洽可独立实现"的最终设计（含文件树、主题契约、8 工具契约、M1~M5、验收表）
```

### 1.2 09-18：v1 的 M2/M3、降级验证与文档收敛

```text
M2 完成       inspect_room / inspect_device / query_events；query_events 两层默认过滤
              （只看本家庭实体 + 排除 sensor.simuhome_virtual_time）；契约 10/10、端到端 11/11、冒烟 8/8
M3 完成       execute_action（四道闸门 + 回读）+ check_goal（conditions + keep）
              契约补齐 C 口径（switch 3 / climate 5 / fan 4）、状态收敛成六字段；
              契约 12/12、端到端 21/21、冒烟 9/9（模型真开灯并自动还原）
降级验证      停发布器 / 停 broker / 重建发现三例全过；掉线时六字段给 null（不谎报 on=false）；
              补上 verified=false 的分支测试（假 HA 吞写入）
一键拉起      _tools\start_simuhome_stack.ps1：Docker → HA → SimuHome → 载入 home_full.json → broker → 发布器
粒度决策      按方案 C：8 动作 + 6 状态字段；memory 简化成"只读整段、不落库"（SMH 口径）
文档收敛      11/12/13 三轮通读修正；13 号记录现状与 memory/预约的处理计划；14 号是给 RL demo 的接口交接
```

### 1.3 09-18 ~ 09-19：外界方案调研（B/C）与预实验

```text
新文件夹      finally new paper\外界大模型与HA交互方式调研\
01 号文档     六条路线盘点（A HA 内置对话代理 / B 官方 MCP Server / C 社区 MCP Server /
              D HA 当 MCP 客户端 / E 直接 REST-WS / F 传统通道），含 HA 源码实测
02 号文档     B/C 冒烟记录：官方 MCP 12 工具（required 全空）、社区 hass-mcp 0.6.0 29 工具 / get_version 通
03 号文档     多维评测 + 论文预实验写法草稿：
              工具面 B 1137 / C 8907 / E 1000 token；单次读 B 697 / C 2234 / E 216 token；
              写调用先回、世界后变（B 119ms→190ms 落定、C 40ms→178ms 且返回空、E 572ms 内含回读）
新增工具      _tools\mcp_probe.py（统一探针）、mcp_surface_bench.py（接口面计量）、mcp_write_settle.py（写-落定计时）
```

### 1.4 09-23：米家接入（真实设备）+ 上云

```text
插件          HA 容器里早已装好官方 xiaomi_home v0.4.7（custom_components），只是没配置
登录成功      账号 2646196763（中国大陆），家庭"2646196763的家"，导入 1 台：米家对开门冰箱
              （midjd6.fridge.6101，did cn_911432173，12 个实体）
踩坑一        登录回调地址写死 http://homeassistant.local:8123（miot/const.py:135，注释写明注册过不能改），
              而本机解析不了 homeassistant.local → 浏览器 NXDOMAIN；代理开着时是 502
              修法：管理员在 hosts 加 127.0.0.1 homeassistant.local（已加）
踩坑二        代理（Clash Verge，127.0.0.1:7897）会把 localhost / homeassistant.local 的请求也代理掉 → 502；
              绕过清单里加上 homeassistant.local，或登录时临时关代理
上云          git 远端 https://github.com/juezhan340/simuhome（private）；直连会被 reset，
              push 要带 -c http.proxy=http://127.0.0.1:7897
新文档        14 号（RL demo 接口交接）、15 号（MCP 接入真实设备的映射扩展设计）
```

### 1.5 09-27：v2 分叉与 M1/M2

```text
分叉          ha_mcp_universal\（复制 v1 代码 62 文件；v1 一行不改，论文主实验口径不变）
原则          接口语义 = 外部设备"控制语义的最大公约数"：能投影就接，缺的维度只有跨多类设备才算公约数，
              单类设备特有的写进 scoping（不是"接口一字不改"，也不是"为米家写特例"）
M1 完成       认领层：registry\claim.py（平台/域/前缀/类别/黑名单规则）+ registry\aliases.py（别名文件）
              + mapping 区域别名与空区域过滤 + 环境量只取"所在设备没有可控实体"的传感器
              实测：认领 {'sandbox': 25, 'xiaomi': 10}；投影设备 12 台；可见房间 3 个（空区域被隐藏）；
              米家的 button/event 被域白名单挡住（"恢复出厂设置"不进认领）
M2 完成       角色层：registry\roles.py（角色推断 + 多值拆分 + 六字段）+ registry\actions.py（动作生成与执行方案）
              冰箱被拆成 cn_911432173_cold / cn_911432173_freeze 两台逻辑设备；
              inspect_device 给 {mode/target/current}；execute_action 用 number.set_value / select.select_option
              实测：冷藏设定 4→5 verified=true（约 3.8s 落定），越界 99 → BAD_REQUEST（本地拦下），已还原成 4
测试          v2：契约 12/12、认领 6/6、角色 4/4、真机端到端 21/21
暂缓          M3（命名泛化 set_temperature→set_target + 第三方集成抽样）——目前只有米家一台真实设备
```

## 2. 当前系统状态

### 2.1 四层运行时要一起在

```text
Docker Desktop → HA 容器 homeassistant（2026.6.4，:8123，挂载 D:\homeassistant\config）
SimuHome API   :8000（simuprocject\Simuhome_experiment，python -m src.simulator.api.app）
Mosquitto      :1883（仅 127.0.0.1，账号 simuhome，凭据在 publisher\broker\mosquitto.credentials.txt）
发布器          simuhome_mqtt_publisher\publisher\publisher.py（SimuHome ↔ MQTT ↔ HA）
一键拉起        powershell -File _tools\start_simuhome_stack.ps1（第 3 步会把 home_full.json 装回 SimuHome，
              不装的话设备接口全 404、HA 实体还在但写命令落空）
```

### 2.2 三个工程

```text
ha_mcp_server\       v1：沙盒版，8 工具（6 做实），冻结不再改（论文主实验口径）
ha_mcp_universal\    v2：通用版分叉，M1/M2 完成（认领 + 角色 + 写路径）
simuhome_mqtt_publisher\  接入层：发布器 + broker + 改名/重置脚本（已上线）
```

### 2.3 米家现状

```text
集成        xiaomi_home v0.4.7（官方），账号 2646196763，中国大陆，云端轮询（ctrl_mode=auto）
设备        只导入了 1 台：米家对开门冰箱（12 实体；已认领 10 个，button/event 被挡）
HA 区域     2646196763de_jia（名字"2646196763的家"，v2 里 alias 成 home）
如果还有设备  检查账号是否一致（设备绑定在哪个小米账号）、家庭是否选全（集成配置里可补）
```

## 3. 关键决策与理由

### 3.1 统一粒度定在 C：房间 → 设备 → 动作类型 → 参数约束 → 关键状态

```text
比 SimuHome（endpoint/cluster/attribute）与 SMH-Bench（每设备自定义服务名 + 组件命名空间）都粗；
动作词表 8 个、状态字段 6 个、参数只带 type/min/max/step/enum。
理由：三个支柱要的语义它都够（任务能表达、训练能判分、两个后端能对齐），实现面比两篇少一大截。
```

### 3.2 memory 简化成只读整段

```text
原设计是 key-value + sqlite；改成 memory() 无参数返回 data\memory.yaml 整段，不落库、不做写入。
理由：对齐 SMH 的"记忆是题面给的"；端侧小模型少一次"要不要查、用什么 key"的决策。
代价：测不到"会不会记"这一环 → 写进 scoping。
```

### 3.3 8 个接口 = 控制语义的最大公约数（v2 的指导原则）

```text
定义：控制器只需要四种写（开关 / 模式 / 目标值 / 百分比）+ 一种读（当前值）。
新设备接入的判断顺序：
  ① 能投影到现有公约数 → 直接接（只加配置）
  ② 缺的维度跨 ≥3 类设备、跨 ≥2 个集成、可读回可判定、两个后端都能表达 → 扩词表/字段
  ③ 单类设备特有（剩余时间、故障位图、回放按钮）→ 不扩，写 scoping
待拍板：set_temperature 是否泛化成 set_target(value)（温度以外还有湿度/水位同形）；
        我建议泛化（只在 v2 做），但需要你确认。
```

### 3.4 为什么另起炉灶做 v2

```text
v1 的映射写死了三道闸门（platform==mqtt / 标识 simuhome_ / unique_id 后缀 _switch|_climate|_fan），
米家设备在闸门 1 就被丢掉。改 v1 会动到论文主实验口径，所以复制一份做 v2：
  v1 冻结；v2 把"认领规则、角色、动作生成"三层改成数据驱动，默认配置又与 v1 等价。
```

## 4. 可直接引用的实测数据

### 4.1 三条路线的接口面（09-19，本机）

| 指标 | B 官方 MCP | C 社区 hass-mcp 0.6.0 | E 自建 v1 |
| --- | --- | --- | --- |
| 工具数 | 12 | 29 | 8 |
| 工具面字节 / 估算 token | 4,551 / ≈1,137 | 35,663 / ≈8,907 | 4,182 / ≈1,000 |
| 必填为空的工具 | 12/12 | 19/29 | 2/8 |
| 带 enum / 上下界 | 2/12 | 0/29 | 2/8 |
| 单次读输出 | GetLiveContext ≈697 token | list_entities ≈2,234 token | observe_home ≈216 token |
| 错误反馈 | Python repr（无下一步提示） | 不置 isError | {code, message, hint} |

### 4.2 写调用 vs 世界落定（09-19）

```text
B 开灯：调用 119 ms，状态落定 190 ms；关灯：58 ms / 409 ms
C 开灯：调用 40 ms，状态落定 178 ms（返回内容为空）；关灯 7 ms / 177 ms
E 开灯：调用 572 ms（回读在调用内部完成），返回 verified=true 与 state_after
```

### 4.3 米家冰箱的真机读写（09-27）

```text
inspect_device(cn_911432173_cold)   → {mode: "手动", target: 4, current: 2}
  动作 set_mode(enum=手动/智能/假日/速冷/速冻)、set_temperature(2~8, 步长 1)
inspect_device(cn_911432173_freeze) → {target: -18, current: -21}
  动作 set_temperature(-24~-15, 步长 1)
execute_action(set_temperature, 5)  → number.set_value → verified=true（约 3.8 s 落定）→ 已还原成 4
execute_action(set_temperature, 99) → BAD_REQUEST（本地拦下，范围 [2,8]）
```

## 5. 踩过的坑（技术）

```text
系统代理         Clash Verge 系统代理 127.0.0.1:7897 会把 localhost / homeassistant.local 也代理走 → 502；
                httpx 同理（探针里已把 localhost/127.0.0.1/::1 写进 NO_PROXY）；
                git push 直连 GitHub 会被 reset，要 -c http.proxy=http://127.0.0.1:7897
homeassistant.local  本机解析不了（NXDOMAIN），而米家插件把 OAuth 回调写死成它 →
                已在 hosts 加 127.0.0.1 homeassistant.local（需要管理员）才登录成功
米家元数据        12 个实体全部 entity_category=None（连"恢复出厂设置"都没标）→
                过滤必须"域白名单 + 角色推断 + 黑名单"三重，不能只信一个信号
云端设备落定慢     米家一次写入落定约 3.8 s；v2 的 verify 从 500ms×3 调到 800ms×4
SimuHome 冷启动    重启后 home 是空的（房间数 0），设备接口全 404、写命令落空（verified=false 而不是 DEVICE_UNAVAILABLE）
                → 一键拉起脚本第 3 步会载入 home_full.json
WS 客户端 id 复用  早期 MCP 的 WS 客户端多条命令共用 id=1，第二条起收不到结果（已修）
风扇档位 0         HA 里 percentage=0 就是关机，发布器原来只断电不写档位 → 脏状态；
                改成先补 On、写 PercentSetting=0、再断电（回执 ["On","PercentSetting=0","Off"]）
参数越界         把 40°C 发给 HA 的 climate.set_temperature，HA 返回 500（不是 400）且不写状态 →
                范围必须在本地校验
```

## 6. 踩过的坑（协作与文档）

```text
用户要"另起炉灶"时，不要顺手把它做成 v1 的补丁——v1 冻结是论文口径问题，不是懒
用户说"不要动别的"，就真的只动那一处：改 memory 那次我顺手把 time_control 改名成 advance_time、
  砍掉预约、改错误码，被要求全部回滚（教训）
分析类任务先给事实与判据，再给建议；不要擅自把建议落成方案文档
文档之间要对齐：11/12/13/14/15 里同一件事（工具数、动作数、错误码、memory 形态）出现多次，
  改一处要全文搜一遍；本轮做过一次"逐模块通读 + 残留清理"
每写/改一个 .py 或 .json，必须同步同名中文 .md（仓库硬规则）
```

## 7. 未做与待办

```text
M3（暂缓）        命名泛化（set_temperature→set_target，A/B/C 待拍板）+ 第三方集成抽样 + 文档收尾
米家其他设备      目前只导入冰箱一台；如果你账号里还有设备，先在集成里补家庭/设备再谈映射
v1 的端到端       米家接入后 v1 会看到第 4 个房间（空区域），端到端 20/21；用户决定不动 v1
代理与 hosts      这是本机环境的既有配置；换机器要重做（hosts 那行 + 代理绕过）
长时间运行        soak（内存/日志/死锁）没跑；M5-1/M5-2 已在 09-18 验证过
论文侧            三支柱的策略以 UbiComp三支柱讨论\12_投稿策略 为准；预实验写法见 03 号文档第 7 节
```

## 8. 怎么把环境拉起来、怎么验证

```powershell
# 1 四层服务（冷启动也行）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\D_coderesource\simuhome\_tools\start_simuhome_stack.ps1

# 2 令牌
$env:HA_TOKEN = (Get-Content D:\D_coderesource\simuhome\_secrets\ha_token.txt -Raw).Trim()
$env:MCP_TOKEN = "local-dev-token"

# 3 v1（沙盒版）验收
cd D:\D_coderesource\simuhome\ha_mcp_server
C:\ProgramData\anaconda3\python.exe tests\test_contract_tools.py            # 12/12
C:\ProgramData\anaconda3\python.exe tests\test_e2e_real_ha.py --config config.yaml

# 4 v2（通用版）验收
cd D:\D_coderesource\simuhome\ha_mcp_universal
C:\ProgramData\anaconda3\python.exe tests\test_contract_tools.py            # 12/12
C:\ProgramData\anaconda3\python.exe tests\test_claim.py                     # 6/6
C:\ProgramData\anaconda3\python.exe tests\test_roles.py                     # 4/4
C:\ProgramData\anaconda3\python.exe tests\test_e2e_real_ha.py --config config.yaml   # 21/21

# 5 用探针直接调（列工具 / 调一个工具）
$env:PYTHONPATH = "D:\D_coderesource\simuhome\ha_mcp_universal\src"
C:\ProgramData\anaconda3\python.exe D:\D_coderesource\simuhome\_tools\mcp_probe.py `
  --stdio "C:\ProgramData\anaconda3\python.exe -m home_mcp.entry --config D:\D_coderesource\simuhome\ha_mcp_universal\config.yaml"

# 6 推送（直连会被 reset）
git -C D:\D_coderesource\simuhome -c http.proxy=http://127.0.0.1:7897 push
```

## 9. 关键文件索引

```text
设计文档    finally new paper\HomeAssistant双仓库接口分析\
              11_最终设计_接入层与统一语义MCP.md        （实现以它为准）
              12_统一能力接口设计.md                    （C 粒度：8 动作 + 6 字段 + 覆盖缺口）
              13_实现现状-已实现能力、memory与预约的处理计划.md
              14_接口交接-八个工具与统一语义.md          （RL demo 用）
              15_MCP接入真实设备的映射扩展设计.md        （三道闸门与 A/B/C 方案）
投稿策略    finally new paper\UbiComp三支柱讨论\12_投稿策略-把三个支柱的故事讲圆.md （绝对关键路径）
调研        finally new paper\外界大模型与HA交互方式调研\01/02/03（含论文预实验写法草稿）
v1          ha_mcp_server\（PLAN.md 记进度；src\home_mcp\contract\tools.py 是契约唯一来源）
v2          ha_mcp_universal\（方案-通用化设备接入设计.md 是设计；registry\ 是 M1/M2 新增的三层）
接入层      simuhome_mqtt_publisher\（publisher / broker / rename / reset_discovery，各配 .md）
探针        _tools\mcp_probe.py、mcp_surface_bench.py、mcp_write_settle.py（各配 .md）
本地数据    ha_mcp_universal\data\device_aliases.yaml（别名，不入库）、_secrets\ha_token.txt（令牌，不入库）
```

## 10. 下次开新对话时可以直接说

```text
"读 finally new paper\new context\context2.md 和 11/12/15 号文档，继续 v2 的 M3"
"接着做 M3：先定 set_temperature 要不要泛化成 set_target，再做第三方集成抽样"
"把 v2 的 M1/M2 过程与验收整理进文档/论文附录"
"米家又接了新设备，先跑一遍认领与角色投影看漏了什么"
```
