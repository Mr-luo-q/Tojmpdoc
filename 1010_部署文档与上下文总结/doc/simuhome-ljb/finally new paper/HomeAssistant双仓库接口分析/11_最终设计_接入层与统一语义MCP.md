# 最终设计：接入层与统一语义 MCP

本文是当前项目的最终完整设计方案，自洽可独立实现，覆盖三件事：

```text
一  接入层：把 SimuHome 世界投影进 Home Assistant（已上线，实测数据在本文）
二  统一语义 MCP server：8 个工具，先接 HA 后端，将来接沙盒后端（待实现）
三  实施计划、模块规格与验收标准（M1~M5）
```

文档关系：01~10 是过程记录与选型讨论（含已退役方案），冲突之处以本文为准；实现只看这一份，
不需要回看任何旧文档。本文数字都是 2026-09-17 ~ 09-18 在本机实测得到的，不是设计意图；
标注了日期的以标注为准，未标日期的是最近一次实测值（改设计前重新核一遍）。

## 1. 目标与边界

```text
目标
  1  设备、房间、档位能力与可用性真实进入 HA：不是把开关换个名字，而是让世界状态可读可控
  2  提供独立 MCP server，对外 8 个工具，覆盖观察 / 控制 / 时间 / 验证 / 记忆
  3  同一份工具契约将来可换到沙盒后端，训练与部署共用一套语义

本版本不做
  query_topology    没有门磁与房间连通数据，先不做空间拓扑
  light / cover     SimuHome 里有亮度与窗帘位置属性，本版本不接
  沙盒后端          与 Gym 侧的对接放到二期
  OAuth / 多会话     初稿静态 Bearer + 单实例，多用户留到二期
  录制器 / 守护      不做回放录制与进程守护，崩溃时靠 unavailable 安全失败
  快进              沙盒侧快进能力本轮不用，时间语义见第 6 节
  记忆写入          memory 只读：不给 key、不做写入、不落库（SMH 式：记忆由实验方准备，见 5.7）

扩展项（超出 SimuHome 与 SMH-Bench 的语义维度，写清边界后保留）
  query_events      两篇都没有事件查询工具（SimuHome 只有 workflow 列表）
  memory            两篇都没有记忆工具（SMH 用 {{memory_list}} 上下文注入）：我们保留一个
                    简化版只读工具——不给 key、不做写入，返回实验方准备的整段记忆
  房间连通 / 拓扑   两篇都没有空间连通，这是我们的 T1 创新，二期再做
```

## 2. 实测基线

以下事实决定了后面所有设计，改设计前先确认这些数字是否还成立。

```text
HA              Container 形态，2026.6.4，:8123；集成 mcp_server 已启用（llm_hass_api=["assist"]）
MCP SDK         容器内 mcp 1.26.0；25 个 Request 类型，含 Elicit / Task / CreateMessage / ListRoots
broker          Mosquitto 2.0.20，仅监听 127.0.0.1:1883，账号密码认证（u'simuhome'）
SimuHome        :8000，15 台设备 / 3 房间（living_room、kitchen、utility_room）

实体             /api/states 44 个，其中 simuhome 25 个 = 9 switch + 2 climate + 1 fan + 13 sensor
设备注册表        21 台，其中 simuhome 16 台 = 12 台可控 + 3 台房间虚拟设备 + 1 台网关
可控设备分布      living_room 5、kitchen 3、utility_room 4
未接入设备        窗帘、冰箱、冷冻柜（没有 OnOff 属性）

映射链           entity → device_id → area_id
                实体自身的 area_id 全是 None，房间只能从 device 取
                device_id 前缀不可靠：utility 房间是 utility_ac / utility_light，
                与 living_room_* / kitchen_* 的写法不一致

命令时延         MQTT 命令 → 发布器 → SimuHome → 回读：236~388 ms（多次实测：空调设温度 236/280、
                空调设模式 258/373、风扇设档 236/388）
时间语义         虚拟时钟按 1:1 真实时间推进（实测 20.0 s 对 20.0 s），HA 侧无法快进
logbook          近 8 小时 3107~9599 条，其中虚拟时间传感器占 91%~96%
                （两次实测：2820/3107 于 09-17、9271/9599 于 09-18；非虚拟时间约 300 条）
recorder         12 项环境量统计 has_mean=True（state_class=measurement 生效）

能力接口          get_services_for_target 只返回服务名列表，且会混入 homeassistant.reload_config_entry
                 supported_features 对 switch 返回 null
                 服务参数 schema 要用 REST /api/services 取
                 extract_from_target(area_id) 可直接给出该区域内的实体集合
```

## 3. 系统架构

### 3.1 数据流

```text
上行（状态）
  SimuHome /api/home/state ──HTTP 轮询──► 发布器 ──MQTT──► Mosquitto ──► HA MQTT 集成
  轮询节奏：活跃 1 s / 空闲 10 s；数值带死区；开关状态一变就发；全部 retained

下行（控制）
  HA 服务调用 → MQTT 命令主题 → 发布器 → SimuHome 命令 / 属性写入
  → 回读属性 → 发布状态主题 → HA 更新 → 写 simuhome/v1/events 回执

可用性
  发布器连 broker 时发 status=online；进程被杀由 LWT 发 offline → 全部实体 unavailable
```

### 3.2 文件树

```text
D:\D_coderesource\simuhome\                    工作区根目录（★ = git 跟踪）
│
├─★ simuhome_mqtt_publisher\                   【已上线】接入工程
│  ├─ README.md / requirements.txt             启动方式、进度、依赖
│  ├─ broker\                                  mosquitto.conf + 凭据 + 启停脚本 + health_check
│  ├─ publisher\                               6 个模块（publisher / discovery / mapping /
│  │                                           simuhome_client / rename_entities / reset_discovery）
│  │                                           各配同名 .md，加 config.yaml 与启停脚本
│  └─ logs\                                    运行日志（gitignore）
│
├─★ ha_mcp_server\                             【M1~M3 已实现】统一语义 MCP server（M4 起待做）
│  ├─ PLAN.md / README.md                      计划与文档地图
│  ├─ pyproject.toml                           依赖 pin（mcp==1.26.0）+ entry point ha-mcp
│  ├─ config.example.yaml                      ${VAR} 占位符配置模板
│  ├─ src\home_mcp\
│  │  ├─ __init__.py
│  │  ├─ entry.py                              L1  CLI、配置、日志（只写 stderr）、选传输、注入后端
│  │  ├─ server.py                             L1  按契约注册工具、错误映射、通知
│  │  ├─ errors.py                             L1+L3  错误码与异常映射
│  │  ├─ runtime.py                            基础设施：配置、sqlite、调度器
│  │  ├─ contract\                             L2  只依赖标准库
│  │  │  ├─ __init__.py
│  │  │  ├─ tools.py                           8 个工具的契约（唯一语义来源）
│  │  │  ├─ conditions.py                      目标条件求值
│  │  │  ├─ clock.py                           虚拟 / 真实时间语义与格式
│  │  │  └─ sinks.py                           ProgressSink / CancelToken / SessionScope
│  │  └─ backend_ha\                           L3  只放 HA 相关，换后端就换这一个目录
│  │     ├─ __init__.py                        导出 {工具名: 实现}
│  │     ├─ client.py                          REST + WebSocket 连接与订阅
│  │     ├─ mapping.py                         device_id ↔ entity_id、区域关联、动作翻译
│  │     └─ tools\                             8 个工具，一工具一文件，M1 先建骨架
│  │        ├─ __init__.py                     收集 8 个实现，拼成 TOOLS 字典
│  │        ├─ observe_home.py                 M1  全屋快照：area 注册表 + 环境量 + 虚拟时间
│  │        ├─ inspect_room.py                 M2  房间：设备清单 + 环境量 + doors=null
│  │        ├─ inspect_device.py               M2  设备：状态 + 动作与参数范围
│  │        ├─ execute_action.py               M3  执行：规范动作 → 服务调用 + 回读
│  │        ├─ check_goal.py                   M3  判定：调 contract\conditions.py
│  │        ├─ query_events.py                 M2  事件：logbook + 排除清单
│  │        ├─ time_control.py                 M4  时间：advance / schedule / list / cancel
│  │        └─ memory.py                       M4 简化：只读返回整段记忆（不给 key、不写入）
│  ├─ tests\
│  │  ├─ __init__.py / fake_ha.py              假 HA，供契约测试
│  │  ├─ test_contract_tools.py                8 个工具跑同一套契约用例
│  │  ├─ test_e2e_real_ha.py                   连真实 HA 的端到端脚本（手动跑）
│  │  ├─ test_llm_smoke.py                     DeepSeek 直连服务，验模型选工具与诚实性
│  │  ├─ test_degraded_backend.py              停发布器 / 停 broker / 重建发现（破坏性，手动跑）
│  │  └─ test_unit_conditions.py / test_unit_clock.py / test_unit_runtime.py  待补（随 M4）
│  └─ data\home_mcp.sqlite3 + memory.yaml      调度与调用日志落 sqlite；记忆是实验方准备的文件
│
├─★ _tools\
│  ├─ ha_ws.py / .md                           读 HA 注册表的小工具（REST 没有这些端点）
│  ├─ update_source.py / .md                   生成 source.md 登记表
│  └─ mqtt\                                    离线包与探针（安装包与 wheels 不入库）
│
├─★ old_simuhome_bridge_project\               早期桥接工程（bridge 已停用）
│  ├─ compose.yaml                             仍在用：起 HA 容器（项目名固定 simuhome_bridge_project）
│  ├─ start_simuhome_server.ps1                仍在用：起 SimuHome（:8000）
│  ├─ reset_simuhome_home.ps1                  仍在用：重置仿真场景
│  └─ bridge\app.py 等                          已停用（:8010 未监听）
│
├─★ finally new paper\                         研究文档与文献（本目录 01~06、08~13；UbiComp 目录另有 1~9 与 12_投稿策略）
├─★ context\                                   跨会话上下文
├─★ README.md / source.md / AGENTS.md
│
├─ 外部目录（不入库，source.md 登记）
│  ├─ simuprocject\Simuhome_experiment\        SimuHome 仿真内核与 HTTP API
│  ├─ ha_core_official\core\                   HA 官方源码（dev @ 2008551），只读参考
│  ├─ sandbox\firstdemo\                       7 月的沙盒薄切片（二期要用）
│  └─ oldmcp\ / related paper\ / .git_old_20260917\ 等
│
└─ HA 侧（Docker 挂载进容器的 /config）
   D:\homeassistant\config\
   ├─ configuration.yaml                       已删掉旧的 simuhome YAML 平台（有 .bak 备份）
   ├─ .storage\                                auth / config_entries / entity_registry / device_registry
   ├─ home-assistant_v2.db                     recorder 历史库
   ├─ dashboards\simuhome-dashboard.yaml       仪表盘（用 climate / fan / switch 新实体 id）
   └─ custom_components\simuhome\              旧自定义集成：保留但不加载
```

### 3.3 进程、端口与读写归属

| 角色 | 位置 / 端口 | 读什么 | 写什么 |
| --- | --- | --- | --- |
| SimuHome 仿真内核 | `simuprocject\Simuhome_experiment`，:8000 | 场景 JSON | 世界状态、设备属性、调度队列 |
| 发布器 | `simuhome_mqtt_publisher\publisher` | `/api/home/state`、`/api/time`、`/api/devices/{id}/attributes` | MQTT 主题；经 HTTP 写 SimuHome |
| broker | `simuhome_mqtt_publisher\broker`，127.0.0.1:1883 | 连接与订阅 | retained 消息、`logs\mosquitto.db` |
| HA | Docker 容器，:8123 | MQTT 主题 | 实体注册表、recorder 库、服务调用 |
| 改名脚本 | `publisher\rename_entities.py` | HA 实体注册表（WS） | 实体 id |
| MCP server | `ha_mcp_server`，本地进程 | HA REST + WS；data\memory.yaml；自己的 sqlite | HA 服务调用；sqlite |

状态归属：世界状态归 SimuHome；HA 只持有投影；发布器的映射写在 `discovery.py`，
MCP 侧的映射在启动时从 HA 注册表生成；记忆是一份实验方准备的文件（data\memory.yaml），
预约与调用日志归 MCP 的 sqlite，HA 都不持有。

## 4. 实体与主题契约

### 4.1 实体清单与命名规则

```text
HA 实体                          数量   来源
switch.simuhome_<device_id>        9   只有 OnOff 的设备
climate.simuhome_<device_id>       2   living_room_ac、utility_ac
fan.simuhome_<device_id>           1   kitchen_fan
sensor.simuhome_<room>_<metric>   12   房间 × {temperature, humidity, illuminance, pm10}
sensor.simuhome_virtual_time       1   SimuHome 虚拟时钟
```

命名规则（实现按这张表，不能靠字符串切分）：

```text
unique_id（发布器写死，用来认领实体）
  switch    simuhome_<device_id>_switch
  climate   simuhome_<device_id>_climate
  fan       simuhome_<device_id>_fan
  sensor    simuhome_<room>_<metric>
  time      simuhome_virtual_time

entity_id（对外使用的规范名）
  <domain>.simuhome_<...>，由 rename_entities.py 用 WS config/entity_registry/update 强制
  原因：HA 的 MQTT discovery 不支持 payload 里的 object_id（2026.6 源码无该常量），
        id 会按「区域 + 设备名 + 实体名」自动拼成
        climate.living_room_air_conditioner_air_conditioner 这类形式；
        实体重建（跑过 reset_discovery 或改过 unique_id）后要重跑一次改名脚本

房间
  只从 device.area_id 取；entity.area_id 恒为 None
```

### 4.2 主题契约 v1（冻结）

| 主题 | 方向 | payload | retain |
| --- | --- | --- | --- |
| `homeassistant/switch/<device_id>/config` | 发布器 → HA | discovery 配置 | 是 |
| `homeassistant/climate/<device_id>/config` | 发布器 → HA | discovery 配置 | 是 |
| `homeassistant/fan/<device_id>/config` | 发布器 → HA | discovery 配置 | 是 |
| `homeassistant/sensor/<room>_<metric>/config` | 发布器 → HA | discovery 配置 | 是 |
| `simuhome/v1/<device_id>/state` | 发布器 → 所有 | `ON` / `OFF` | 是 |
| `simuhome/v1/<device_id>/mode` | 发布器 → 所有 | `off` / `cool` / `heat` | 是 |
| `simuhome/v1/<device_id>/target_temp` | 发布器 → 所有 | 摄氏度 | 是 |
| `simuhome/v1/<device_id>/current_temp` | 发布器 → 所有 | 摄氏度（设备温度计） | 是 |
| `simuhome/v1/<device_id>/percent` | 发布器 → 所有 | `0`~`100` | 是 |
| `simuhome/v1/<room>/<metric>` | 发布器 → 所有 | 数值（已换算） | 是 |
| `simuhome/v1/time` | 发布器 → 所有 | 虚拟时间字符串 | 是 |
| `simuhome/v1/<device_id>/set` | HA → 发布器 | `ON` / `OFF` | 否 |
| `simuhome/v1/<device_id>/set_mode` | HA → 发布器 | `off` / `cool` / `heat` | 否 |
| `simuhome/v1/<device_id>/set_temp` | HA → 发布器 | 摄氏度 | 否 |
| `simuhome/v1/<device_id>/set_percent` | HA → 发布器 | `0`~`100`（0 等于关机） | 否 |
| `simuhome/v1/status` | 发布器 → 所有 | `online` / `offline`（LWT） | 是 |
| `simuhome/v1/events` | 发布器 → 所有 | 命令回执 JSON | 否 |

命令回执：`{device_id, command, payload, steps, ok, ms, ts}`，失败时附 `error`。
`steps` 记录真实发生的每一步，例如空调开制冷是 `["On", "SystemMode=3"]`——档位属性有上电依赖，
发布器先补一条开机并把这一步暴露出来，不做隐式修改。

注意这是两层命名，不要求同名：主题是发布器层的契约（`target_temp`、`percent`、`set_mode`），
模型层看到的是统一动作与状态字段（`target`、`level`、`set_mode`）。改一层不要顺手改另一层。

### 4.3 设备动作与物理效应

```text
类别      动作（C 口径，按类别取子集）                        SimuHome 落点
switch    turn_on / turn_off / toggle                      OnOff 命令（9 台）
climate   上述 3 个 + set_mode(off|cool|heat)               OnOff 命令 + Thermostat.SystemMode（2 台）
          + set_temperature(7~32，步长 0.5)                  OccupiedCooling/HeatingSetpoint（0.01°C 整数）
fan       上述 3 个 + set_percentage(0~100)                 OnOff 命令 + FanControl.PercentSetting（1 台）
sensor    只读                                             房间温湿度 / 照度 / PM10、虚拟时间

代码现状（2026-09-18，M3 完成）：switch 3 个 / climate 5 个 / fan 4 个
```

约束与物理速率（读 SimuHome 源码得到，决定任务的时间尺度）：

```text
上电依赖   Thermostat 与 FanControl 的属性只能在设备 On 时写，否则 DEPENDENCY_VIOLATION
温度死区   制冷设定点 − 制热设定点 ≥ 0.25°C，写制热设定点时可能被拒
空调制冷   速率 = min(0.0005, 温差°C × 1.0) × 风速百分比 ÷ 100  °C/s
           满风、温差 ≥1°C 时约 0.0005 °C/s = 1.8 °C/h
风扇降温   速率 = min(0.0002, 温差°C × 0.5) × 档位 ÷ 100  °C/s
           满档约 0.72 °C/h，目标是「基线 − 2 °C」
含义       "20 分钟内降温 3 度"这类任务在真实时间轴上不可达，只能在沙盒侧用快进跑；
           HA 侧的时序任务必须限定在秒级窗口
```

## 5. MCP server 设计

### 5.1 分层与依赖规则

```text
外层（谁负责）
  ① Host / ② Client   客户端，不在本仓库
  ③ 传输层 / ④ 协议层  mcp SDK 提供（stdio 与 Streamable HTTP）
  ⑤ Server            本仓库：L1 协议壳 + L2 语义层 + L3 融合层

依赖方向
  entry.py     → server、backend_ha、runtime       唯一把它们接起来的地方
  server.py    → contract、errors                   不认识任何后端
  backend_ha\  → contract、errors、runtime          不认识 server
  contract\    → 只依赖标准库
  runtime.py   → 只依赖标准库与 PyYAML

硬规则
  一  server.py 里不出现 entity、domain、service、rest、ws、sqlite 这类后端词汇
  二  backend_ha\ 里不 import server
  三  contract\ 里不 import 本包内其它模块
  例外：entry 到后端是动态导入（importlib + BACKENDS 表），静态扫描看不到，靠表本身声明
```

### 5.2 工具契约（8 个）

ToolSpec 是唯一语义来源，每个工具五个字段：

```text
name / params / returns / errors / time_semantics
另加一个 maps_to：论文口径的接口名，统计与写作时按它对齐
```

| 工具 | 参数 | 返回 | 关键实现点 | maps_to（论文口径） |
| --- | --- | --- | --- | --- |
| `observe_home` | 无 | 房间清单 + 每房间环境量 + 虚拟时间 | area 注册表 + 按 area 过滤（44 → 25） | `observe_home` |
| `inspect_room` | `room_id` | 环境量 + 设备清单 + `doors: null` | 房间→设备与传感器的映射来自注册表视图；环境量聚合与 observe_home 共用 | `inspect_room` |
| `inspect_device` | `device_id` | 设备元信息 + 六个状态字段 + 该设备的动作清单 | 状态字段固定 6 个（见下）；动作与范围取设备自报值（空调 7~32/0.5、风扇 0~100/1） | `inspect_device` |
| `execute_action` | `device_id`、`action`、参数 | 执行结果与回执 | 规范动作 → 服务调用；执行前查可用性；回读 500 ms × 3 | `execute_device_action` |
| `time_control` | `op`（advance / schedule / list / cancel）、参数 | 快照或预约 id | advance 真等（超时 30 s）；schedule 走 runtime 调度器 | `wait_for_event` + 预约类 |
| `check_goal` | `conditions`（必填）、`keep`（可选） | 两组条件各自的判定结果 | `conditions` 是目标条件、`keep` 是必须保持不变的条件（对齐两篇的"无关状态保持"）；目标命名空间 `<room>.<metric>` / `<device_id>.<attr>` | `check_goal_state` |
| `query_events` | 时间窗、可选实体 | 事件序列 | logbook + 两层默认过滤（只看本家庭、排除虚拟时间），显式实体时全关 | `query_events`（扩展项） |
| `memory` | 无 | `{text}`：整段记忆原文 | 读 `data\memory.yaml` 原样返回；只读、不给 key、不做写入（见 5.7） | `memory_read`（扩展项） |

统一返回外壳：`{"ok": bool, "data": {...}, "error": {"code","message","hint"}, "meta": {"elapsed_ms","clock"}}`。
`meta.clock` 标明这次调用消耗的是 `virtual` 还是 `real` 时间。

规范动作词表（固定 8 个，按设备类别取子集；两个后端各自翻译，工具层只认这套）：

```text
turn_on / turn_off / toggle                       任意可控设备
set_mode(off|cool|heat)                           空调
set_temperature(value, 7~32, 步长 0.5)             空调
set_percentage(value, 0~100)                      风扇
set_brightness(value, 0~100)                      词表预留：当前没有 light 实体
set_position(value, 0~100)                        词表预留：当前没有 cover 实体

落到 HA 是 switch.turn_on / climate.set_temperature / fan.set_percentage 等服务调用；
落到沙盒是 Matter 风格命令或属性写入。
```

`inspect_device` 的状态字段固定六个，按设备类别取子集：

```text
on(bool) / mode(string) / target(number) / level(number) / position(number) / current(number)
范围与步长不放在状态里，它们属于动作参数；单位由文档约定（摄氏度、百分比）
```

这套粒度比 SimuHome（endpoint/cluster/attribute）与 SMH-Bench（设备自定义服务名 + 组件命名空间 +
状态转移规则）都粗，取舍过程与覆盖缺口见 `12_统一能力接口设计.md`。

### 5.3 错误码

```text
HA_UNREACHABLE      连不上 HA 或超时
UNKNOWN_DEVICE      查不到 device_id 对应的实体
UNKNOWN_ROOM        查不到 room_id 对应的 area
DEVICE_UNAVAILABLE  实体处于 unavailable / unknown（发布器掉线）
UNSUPPORTED_ACTION  该实体不支持这个动作
SERVICE_ERROR       HA 返回服务调用失败
UNKNOWN_KEY         读记忆时键不存在（简化后的 memory 不再用 key，这个码先留在表里备用）
VERIFY_TIMEOUT      调用成功但状态未按时变化（不算失败，附在返回值里）
INVALID_TIME        预约时间在过去
BAD_TARGET          条件里的目标无法解析
BAD_REQUEST         参数不合 schema
NOT_IMPLEMENTED     该工具本阶段还没实现（M1 会出现，逐步消失）
```

`DEVICE_UNAVAILABLE` 必须在调用前判定：先读实体状态，unavailable / unknown 直接返回该错误，
不要发服务调用——MQTT 实体掉线时 HA 仍会把命令发进主题，只是没人执行，会得到假成功。

### 5.4 后端映射规则（HA 后端）

```text
建表      启动时读 WS config/entity_registry/list + config/device_registry/list，
          生成 {device_id → entity_id, domain, area_id, category, unique_id}；
          实体自身 area_id 为 None，房间经 device 取
          （area_id 是 HA 侧字段名，对外给模型时叫 room_id；category 在代码里叫 kind）
动作判定  domain + 属性 → 该设备支持哪些动作：switch/light/fan/climate 都给 on_off 三件套；
          climate 另有 set_mode 与 set_temperature，范围取**实体属性**里的
          min_temp / max_temp / target_temp_step（不是从六个状态字段里取，状态字段只放当前值）；
          fan 另有 set_percentage（0~100，步长取实体属性 percentage_step）；
          light 有 brightness 属性时给 set_brightness；cover 有 current_position 时给 set_position
          不依赖 get_services_for_target（它只给服务名还混着管理员服务，supported_features 对 switch 为 null）
动作      规范动作 → HA 服务；无对应服务返回 UNSUPPORTED_ACTION；
          参数超出设备范围先在本地校验：用设备自报的 min/max（如空调 7~32）比对，
          超界直接 BAD_REQUEST。实测教训：把 40°C 发给 HA 的 climate.set_temperature，
          HA 返回的是 500 Internal Server Error 而不是 400，不能指望它兜住参数校验
目标      check_goal 的目标命名空间：<room>.<metric>（环境量）、<device_id>.<attribute>（设备属性）
事件      query_events 走 logbook，默认排除 sensor.simuhome_virtual_time
可用性    调用前读状态，见 5.3
回读      verify_delay_ms = 500、attempts = 3（实测一次命令 + 回读 236~388 ms）
```

### 5.5 配置格式

完整模板在 `ha_mcp_server\config.example.yaml`（`${VAR}` 占位符、令牌不入库），本文只列四条非显然约定：

```text
room_env / devices / doors   留空：环境量按 area + sensor.device_class 推导，
                             设备映射由注册表在启动时生成，配置只作覆盖
verify_delay_ms = 500        实测一次命令 + 回读 236~388 ms，300 ms 会误判
events.exclude_entities      默认排除 sensor.simuhome_virtual_time（占 logbook 91%~96%）
memory.file                  记忆文件（默认 data\memory.yaml），相对配置文件所在目录解析；
                             格式与读取方式见 5.7
```

### 5.6 状态归属与并发

```text
HA 状态        由 HA 持有，我们只读；不缓存成"真相"，每次按需拉
设备映射       启动时从注册表生成并缓存，可手动 refresh
记忆           data\memory.yaml，实验方准备，启动时读一次；不给模型写回（见 5.7）
预约与调用日志 由 runtime 的 sqlite 持有，是唯一需要我们持久化的东西

两张表
  schedules(id, due_at, steps, status, created_at, result)
  calls(id, ts, tool, args, ok, ms, error)

并发           一个实验实例 = 一个 server 进程 + 一个 sqlite 文件；session 维度留到二期
```

### 5.7 memory 工具（简化版：只读整段记忆）

```text
做法      实验方把记忆写成 data\memory.yaml；服务端启动时读一次
工具行为  memory()（无参数）→ 原样返回整段记忆文本；只读，不给 key、不做写入
为什么    对齐 SMH-Bench 的口径（记忆是"题面给、模型用"），但保留工具外壳，
         让模型自己决定什么时候取；小模型只需要记住"调 memory"这一个动作，
         不用学 key 词表、也不会出现"写 bedtime 读 sleep_time"这类参数错
不做      不落库（没有 sqlite memory 表）、不做 write、不做遗忘与语义检索；
         短期记忆（最近几轮对话）由客户端自己带，我们不重复实现
边界      测不到"会不会记"这一环 → 写进 scoping；UNKNOWN_KEY 这个错误码先留着不用
```

## 6. 时间语义

```text
HA 后端     无快进。实测虚拟时钟 1:1 真实时间推进，advance 就是真等，单项超时上限 30 s
沙盒后端    有 fast_forward_to 接口，本轮不用；训练与离线评测按决策点推进（二期）
统一要求    两个后端返回同一结构，meta.clock 标明这次等待消耗的是哪种时间；
            迁移实验里"等待代价"单独统计，不混进成功率
```

## 7. 实施计划

### 7.1 M1 骨架 + observe_home（约 1 天）

状态：已完成（2026-09-17）

```text
交付   entry / server / errors / contract 四件 / runtime(配置) / backend_ha(client + mapping + tools 八个)
验收   tools/list = 8 个工具；observe_home = 3 房间 + 4 环境量 + 虚拟时间；
       其余 7 个 NOT_IMPLEMENTED；契约 7/7、端到端 4/4、协议壳词汇检查无命中
模型   tests\test_llm_smoke.py（DeepSeek deepseek-flash）两轮 8/8：
       第 1 轮命中 observe_home 并给出中文汇总；第 2 轮要求开灯（当时未实现），
       模型如实说明、没有谎报成功
沿路修  WS 客户端多命令共用写死的 id（第 2 条起收不到结果）；
       工具 schema 的 array 缺 items、object 缺 properties（主流 function calling 会拒收）；
       错误 hint 泄漏内部文档编号（会被模型转述给用户）
证据   逐项记录在 ha_mcp_server\README.md 与 PLAN.md，本文不重复
```

### 7.2 M2 只读三件套（约 1 天）

状态：已完成（2026-09-18）

```text
交付   inspect_room / inspect_device / query_events；契约动作表 ACTIONS_BY_KIND；
       mapping 取值辅助（collect_env / summarize_state / to_number）；client 加 get_state 与 get_logbook
验收   inspect_room(living_room) = 5 设备 + 4 环境量 + doors=null；不存在 → UNKNOWN_ROOM
       inspect_device(空调) = set_mode / set_temperature，范围取设备自报 7~32 / 0.5；不存在 → UNKNOWN_DEVICE
       query_events(近 8 小时) = 239 条匹配、返回 50 条，无虚拟时间、实体全在本家庭前缀内
       契约 10/10、端到端 11/11、大模型 8/8
口径   query_events 默认只返回本家庭实体（logbook 混有 HACS 更新等别的集成事件）；
       "非空"验收从近 10 分钟改为近 8 小时（安静时段 508 条全是虚拟时间、排除后为 0）；
       错误 hint 指向 tools/list，不列具体工具（会随分期过时）
模型   大模型第 2 轮改走 inspect_room → inspect_device → execute_action，即"先查再动"
证据   逐项记录在 ha_mcp_server\README.md 与 PLAN.md
```

### 7.3 M3 写与判定（约 1 天）

状态：已完成（2026-09-18）

```text
交付   execute_action（四道闸门 + 回读验证）+ check_goal（conditions + keep）；
       契约补齐到 C 口径（climate 5 个动作、fan 4 个）与 keep 参数；
       inspect_device 状态换成六字段；mapping 加 device_actions 与 resolve_target
验收   真机端到端 21/21：灯 turn_on → on=True；空调 set_mode cool / set_temperature 25 →
       回读一致；风扇 set_percentage 60 → level=60；空调 turn_off 生效；
       越界 40°C → BAD_REQUEST（本地拦下）；对开关发 set_temperature → UNSUPPORTED_ACTION；
       check_goal 目标不成立 + 保持条件成立；还原校验三台设备回到测试前状态
       契约测试 12/12；大模型冒烟 9/9（模型先说"已帮您打开客厅的侧灯"，
       实机 on=true，随后自动还原 off）
口径   四道闸门顺序固定：设备存在 → 实体可用 → 动作支持 → 参数范围；
       回读用 verify_delay_ms 500 × 3，未变只标 verified=false 不算失败
沿路修  风扇档位 0 的语义：HA 里 percentage=0 就是关机，发布器原来只断电不写档位，
       留下"已关机但档位仍显示 60"的脏状态 → 改成先补 On、写 PercentSetting=0、再断电
       （回执 ["On","PercentSetting=0","Off"]），否则实验条件还原不回去
```

### 7.4 M4 时间与记忆（约 1 天）

```text
交付   time_control（advance / schedule / list / cancel）+ runtime 的 sqlite 与调度器；
       memory 改成简化只读版：memory() 返回 data\memory.yaml 的整段记忆（不给 key、不写入）
验收   advance(seconds=5) 返回快照，超时 30 s 记 VERIFY_TIMEOUT（不算失败）；
       schedule 10 秒后关灯到点执行成功；memory() 返回的内容与 data\memory.yaml 一致，
       文件缺失时返回空记忆且不报错
口径   advance 只接受秒数，不提供"等到条件成立"：C 粒度下状态只有六个字段，
       也没有 cron 与状态触发；"洗碗机洗完就关灯"这类目标写成轮询（advance + inspect）
       或绝对时间调度，接口不替模型做这件事
记忆   走 SMH 的简化口径（见 5.7）：记忆由实验方准备成一份文件，工具只读整段返回；
       只测"会不会用"，测不到"会不会记"这一环 → 写进 scoping
```

### 7.5 M5 验收（约 0.5 天）

```text
交付   第 10 节的验收表填满 + 动作词表覆盖率报告（8 个动作 × 2 个后端，
       每格标"已验证 / 当前无设备 / 未实现"）+ calls 表的调用统计
验收   验收表全绿；探针 6/6；HA 侧 6 个动作全部已验证，
       set_brightness 与 set_position 标"当前无设备"；
       降级与恢复（tests\test_degraded_backend.py）三例 21/21：停发布器 / 停 broker /
       重建发现，含 DEVICE_UNAVAILABLE 拦截与自愈
```

### 7.6 二期 / 三期

```text
二期 A  query_topology：需要一份 edges 配置（房间连通 + 门实体映射），或给 SimuHome 加门磁
二期 B  light / cover：把主灯亮度（LevelControl 1~254）与窗帘位置接进 HA
二期 C  沙盒后端 backend_sandbox：同一份 contract，训练侧走 Gym，离线评测走同一批任务
二期 D  资源 / 提示 / 进度 / 澄清：新增 resources\ 子包，进度与取消挂 contract\sinks.py
三期    双后端迁移实验：同一策略在沙盒与 HA 跑成对任务，报告成功率保持与适配成本
```

## 8. 模块规格

按「职责 / 输入 / 输出 / 读取 / 写入 / 不负责 / 对应文件」写，实现时逐条对照。

计数与文档规则：`src\` 22 个 `.py`（已全部落地；M4 把 `memory.py` 改成只读版）+ `tests\` 目标 9 个（当前 6 个，待补 3 个单测随 M4），
加 `pyproject.toml`、`README.md`、`config.example.yaml` 三个根文件；每个 `.py` 另配一份同名中文 `.md`
（如 `observe_home.py` → `observe_home.md`），解释输入输出与职责，改代码必须同步改文档。

### 8.1 接入层七个模块

模块规格写在各文件的同名 `.md` 里，本文不重复；这里只留一张索引：

| 模块 | 一句话职责 | 规格文档 |
| --- | --- | --- |
| `publisher\publisher.py` | 上行发布 + 下行命令分派、去重限流 | `publisher.md` |
| `publisher\discovery.py` | discovery 配置与全部主题名（契约唯一出处） | `discovery.md` |
| `publisher\mapping.py` | 设备分类、命名与取值换算（纯函数） | `mapping.md` |
| `publisher\simuhome_client.py` | SimuHome HTTP 四类调用，失败抛 SimuHomeError | `simuhome_client.md` |
| `publisher\rename_entities.py` | 强制规范 entity_id（幂等） | `rename_entities.md` |
| `publisher\reset_discovery.py` | 清空 discovery 重建实体 | `reset_discovery.md` |
| `broker\mosquitto.conf` + `health_check.py` | 带认证的 MQTT 传输与收发自检 | `health_check.md` |

跨模块约束留在本文：依赖方向见 §5.1，主题契约见 §4.2，两层命名见 §4.2 末。

### 8.2 ha_mcp_server（8 个工具，一工具一文件）

```text
职责      L1：entry.py / server.py / errors.py
          L2：contract\tools.py（契约）、conditions.py（目标判定）、clock.py（时间语义）、
              sinks.py（进度 / 取消 / 会话）
          L3：backend_ha\client.py（REST + WS）、mapping.py（映射表）、tools\*.py（实现）
输入      MCP 客户端请求（tools/list、tools/call）、config.yaml
输出      契约要求的返回结构、progress 与 logging 通知、calls 表日志
读取      HA REST 与 WebSocket；runtime 的 sqlite；data\memory.yaml
写入      经 HA 服务调用改设备状态；写 sqlite
不负责    不认识 HA 之外的平台（换后端只换 backend_ha\）、不做任务分解与自动编排
对应文件  ha_mcp_server\src\home_mcp\（逐文件清单见 3.2，工具契约见 5.2）

8 个工具文件与各自的实现阶段见 §3.2 的 `tools\` 清单（一工具一文件，每个配同名 .md）；
M4 会把 memory.py 改成只读版（返回整段记忆）。
内部分工：`contract\tools.py` 定契约，`server.py` 按契约注册，`backend_ha\tools\*.py`
只负责把契约落到 HA 的 REST / WS 调用；换沙盒后端时新增 `backend_sandbox\tools\*.py` 即可。
```

## 9. 风险与边界

```text
没有拓扑       T1 空间任务测不了；0 个门磁实体，inspect_room 的 doors 恒为 null
动作面有限      12 台可控设备 = 9 switch + 2 climate + 1 fan；没有 light / cover
advance 耗时    虚拟时钟 1:1，HA 侧 advance 就是真等；长时序任务只能放沙盒后端
掉线假成功      发布器 / broker 掉线后实体变 unavailable，HA 仍会接受服务调用、
                把命令发到主题，所以要靠 DEVICE_UNAVAILABLE 前置检查兜住。
                2026-09-18 真机验证：停发布器与停 broker 都被拦下且命令没下发，
                期间 inspect_device 的六字段是 null（不谎报 on=false），重启后自动恢复
环境太慢       空调 1.8 °C/h、风扇 0.72 °C/h，跨房间传播任务在真实时间轴上不可达，
                这类任务要么放沙盒快进，要么改 SimuHome 的效应参数（改参数要同步改本文 4.3）
命名不稳定      用户可改实体名；entity_id 靠改名脚本强制，配置只作覆盖
记忆测不全      memory 只读（同 SMH 的"记忆由题面给"）：能测"会不会用"，
                测不到"会不会记"；写进 scoping
单实例假设      一个 HA、一个令牌、一个 sqlite；并发实验要各起一份
动态依赖        entry 到后端是字符串表 + importlib，工具链看不到这条边
冷启动缺 home   SimuHome 重启后 home 是空的：设备接口全 404，HA 实体却仍在线，
                写命令会被接受但落空（回执 verified=false，不是 DEVICE_UNAVAILABLE）。
                拉起顺序与自检见 _tools\start_simuhome_stack.ps1（第 3 步载入 home_full.json）
未验证          长时间运行（内存 / 日志 / 死锁）。M5-1 与 M5-2 已于 2026-09-18 验证：
                reset 重建后 25 实体 / 16 条设备注册无重复、rename dry-run 为 0；
                broker 重启后发布器自动重连、实体恢复（tests\test_degraded_backend.py 21/21）
```

## 10. 验收清单

M5 要填的验收表：

| 工具 | 调用 | 期望 | 实测 | 通过 |
| --- | --- | --- | --- | --- |
| observe_home | 无 | 3 房间 + 4 环境量 + 虚拟时间 | | |
| inspect_room | living_room | 5 台设备 + 4 环境量 + doors=null | | |
| inspect_device | living_room_side_light | 状态 + turn_on/turn_off/toggle | | |
| inspect_device | living_room_ac | 模式三种 + 设定点 7~32 + 当前温度 | | |
| execute_action | 灯 turn_on | 回读 on=True | | |
| execute_action | 空调 set_temperature {value: 25} | 回读 target=25 | | |
| execute_action | 风扇 set_percentage {value: 60} | 回读 level=60 | | |
| execute_action | 温度 40 越界 | 返回 BAD_REQUEST | | |
| execute_action | 实体 unavailable | 返回 DEVICE_UNAVAILABLE | | |
| execute_action | 空调 set_mode {mode: cool} | 回读 mode=cool | | |
| execute_action | 空调 turn_off / fan toggle | 回读 on=False / on 取反 | | |
| inspect_device | 逐类动作数 | switch 3 / climate 5 / fan 4 | | |
| time_control(advance) | advance(5 s) 后 inspect | 返回快照，超时 30 s 记 VERIFY_TIMEOUT | | |
| time_control(schedule) | 10 秒后关灯 | 到点执行成功 | | |
| check_goal | conditions=[kitchen.temperature lt 24]、keep=[living_room.temperature lt 28] | 目标不成立、保持条件成立，两组各自标 pass | | |
| query_events（扩展） | 近 8 小时 | 非空、不含虚拟时间、实体都在本家庭前缀内 | | |
| memory（扩展） | 调 memory() | 返回 data\memory.yaml 的整段内容；文件缺失时返回空记忆 | | |
| 动作覆盖率报告 | 8 个动作 × 2 个后端 | HA 侧 6 个已验证、2 个标"当前无设备"；沙盒未建 | | |

环境侧的自检（改过接入层后跑）：

```powershell
# 三层在跑（三个端口都要有监听）
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in 8000,1883,8123 }

# 实体与命名规范：25 个 simuhome 实体；改名脚本 dry-run 应为 0
C:\ProgramData\anaconda3\python.exe _tools\ha_ws.py config/entity_registry/list --full
C:\ProgramData\anaconda3\python.exe simuhome_mqtt_publisher\publisher\rename_entities.py --dry-run

# 命令闭环：发一条 set_mode=cool，看 simuhome/v1/events 的 steps 与 ms
```

架构探针（`_架构探针\probe.py`）六项必须保持全绿：依赖单向无环、协议壳无后端词汇、
换后端零文件改动、缺工具启动即报错、契约跨后端复用、配置占位符可替换。
