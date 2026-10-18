# 自建 MCP：接口清单与 HA 实现

## 0. 决定

```text
决定    自建一个独立的 MCP server，只依赖 HA 的对外接口（REST 与 WebSocket），不改 HA 内部
不用    集成进官方 mcp_server（写自定义集成 + llm.async_register_api + llm_hass_api 勾选）

理由
  一  发布形态清楚：自建 server 是一个能 pip 安装或 docker 起的独立包，
      用户填 HA 地址加令牌即可接入；走集成方案要用户装自定义集成、改配置项，还得跟 HA 版本走
  二  工作量可见：协议层、鉴权、会话、适配层、HA 缺失能力的补齐都在我们这边，
      论文里能逐项写清做了什么
  三  语义可控：官方 MCP 的工具集受 Assist 的可见性过滤与 intent 设计约束，
      拓扑、时间、目标断言、记忆这四类它表达不了，自建 server 不受限
  四  不锁死在官方实现上：HA 升级主要动内部，REST 与 WebSocket 是稳定接口

保留    官方 MCP 作为对照组（baseline），实验里两套都跑，比较工具面与成功率差异
```

## 1. 最终 9 个接口

| # | 接口 | 参数 | 返回 | 定位 |
| --- | --- | --- | --- | --- |
| 1 | `observe_home` | 无 | 房间清单 + 每房间环境量摘要 + 当前时间 | 全局观察 |
| 2 | `inspect_room` | `room_id` | 该房间环境量、设备清单、连通与门状态 | 空间查询 |
| 3 | `inspect_device` | `device_id` | 状态 + 能力（可用动作、参数范围） | 设备查询 |
| 4 | `query_topology` | 无 | 房间节点 + 边（门开 / 关） | 空间连通（核心） |
| 5 | `execute_action` | `device_id`、`action`、参数 | 执行结果 | 控制 |
| 6 | `time_control` | `op`（advance / schedule / list / cancel）+ 对应参数 | 状态摘要或预约 id | 时间 |
| 7 | `check_goal` | 条件列表 | 每条是否满足 | 目标验证 |
| 8 | `query_events` | 时间窗、可选实体 | 事件序列 | 历史与审计 |
| 9 | `memory` | `op`（read 或 write）、`key`、可选 `value` | 记忆内容 | 长期记忆 |

设计取舍：

```text
观察类 4 个（1~4）  全屋 / 房间 / 设备 / 拓扑 四种粒度分开，避免一个工具返回全量
执行类 1 个（5）    只负责“立刻执行”
时间类 1 个（6）    四个 op：advance（推进或等待到某时刻 / 条件）、schedule（登记未来动作）、
                    list 与 cancel（管理预约）
验证类 2 个（7~8）  目标断言与事件查询分开：一个问“结果对不对”，一个问“过程发生了什么”
记忆类 1 个（9）    读写合成一个工具，用 op 参数区分

为什么时间只留一个
  原来的 schedule_action 与 wait_until 在底层是同一件事：把世界（或模型自己）的时间推到 T。
  沙盒侧两者都要靠 fast_forward_to，HA 侧两者都是“等条件或等真实时间”。
  对外合成一个工具、用 op 区分意图，评测时照样能分别统计“预约”与“等待”两类行为。

砍掉的
  write_attribute        与 execute_action 语义重叠，合并
  get_attribute、get_all_attributes、get_device_structure   合并进 inspect_device
  get_rooms、get_room_devices、get_room_states              合并进 observe_home 与 inspect_room
  get_workflow_status、get_workflow_list、cancel_workflow   并进 time_control 与 query_events
  get_cluster_doc、get_environment_control_rules            知识检索，不进工具面，改由系统提示词提供
  add_device、remove_device、set_tick_interval、finish      仿真运维与 agent 循环，不属于环境接口
```

## 2. 每个接口依托 HA 怎么实现

前提：我们的 MCP server 是独立进程，只用 HA 的 REST 与 WebSocket，带用户给的长期令牌。

### 2.1 架构

```text
模型客户端 ──MCP──► 我们的 MCP server ──REST /api/* ──► HA
（Claude、自研 agent…）      │         ──WS /api/websocket ──►
                            ├── 适配层：实体发现、区域关联、寻址映射
                            ├── 补齐层：拓扑、房间聚合、目标断言、等待、记忆
                            └── 本地状态：sqlite / json（记忆、预约、拓扑配置）
```

### 2.2 逐个接口的 HA 落点

| # | 接口 | HA 侧调什么 | 我们自己补什么 |
| --- | --- | --- | --- |
| 1 | `observe_home` | WS `config/area_registry/list` 取房间；REST `GET /api/states` 或 WS `get_states` 取状态；WS `render_template` 取时间 | 按 area 聚合传感器读数；统一时间字段（沙盒是虚拟时间，HA 是真实时间） |
| 2 | `inspect_room` | WS `config/entity_registry/list` 按 `area_id` 找实体，再按状态过滤 | 环境量聚合；连通与门状态从拓扑配置或门磁实体取 |
| 3 | `inspect_device` | REST `GET /api/states/{entity_id}` 取状态；WS `get_services_for_target` 取该实体支持的服务与字段；`supported_features` 取能力位 | 把“服务 + 字段”翻译成统一动作模型（动作名、参数、取值范围） |
| 4 | `query_topology` | 无（HA 只有 area / floor 归属，没有房间之间的边） | 一份 edges 配置（房间连通 + 门实体映射），或从门类实体实时读开闭 |
| 5 | `execute_action` | REST `POST /api/services/{domain}/{service}`，或 WS `call_service` | `device_id` → `entity_id` → `domain/service` 的映射表 |
| 6 | `time_control` | 无等价物（HA 既不能推进时间，也没有“预约一串动作”的接口） | 两件东西：advance 用事件订阅等条件（WS `subscribe_events`、`subscribe_entities`，或 REST `/api/stream`）；schedule 用本地调度器到点调服务，并持久化 |
| 7 | `check_goal` | 无断言接口 | 本地条件求值器（拉状态后自己判断），不要靠模板字符串硬拼 |
| 8 | `query_events` | REST `/api/logbook[/{datetime}]`、`/api/history/period`；WS `logbook/get_events`、`history/history_during_period` | 统一事件格式（时间、实体、动作、前后状态） |
| 9 | `memory` | 无原生记忆 | 本地 sqlite / json 持久化，也可映射到 HA 的 `todo`、`input_text` 作为可见载体 |

汇总：

```text
HA 直接给的      1 的骨架、2 的实体发现、3 的状态与能力、5 的执行、6 里 advance 的事件订阅、8 的历史
要我们自己补的   2 的房间聚合、4 的拓扑、6 的调度与时间语义、7 的断言、9 的记忆
```

### 2.3 三个必须显式处理的差异

```text
寻址    HA 执行用 entity_id、语音定位用 name/area；我们的工具对外统一用 device_id 与 room_id，
        内部查表转 entity_id。表在启动时从 WS config/entity_registry/list +
        config/device_registry/list 生成
可见性  HA 侧只有被 expose 的实体对语音助手可见；我们的 server 用令牌直接读 REST，
        不受 expose 限制，所以“给模型看什么”要自己定，并把这份可见集合记录下来
时间    沙盒可以 fast_forward_to 跳到未来，HA 只能真实等待或等事件触发；
        time_control 的 advance 在两个后端返回同一结构，但必须带字段说明这次等待消耗的是哪种时间
```

## 3. 同一份 ToolSpec，两个后端

```text
              ToolSpec（工具名 / 参数 / 返回结构）
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
 沙盒后端                HA 后端
 SimuHome HTTP API       HA REST + WebSocket
 可快进虚拟时间           真实时间，无快进
```

| 接口 | 沙盒后端 | HA 后端 |
| --- | --- | --- |
| `observe_home` | `GET /api/home/state` | WS 注册表 + `GET /api/states` |
| `inspect_room` | `GET /api/rooms/{id}/states` 加 `/devices` | area 关联实体 + 状态过滤 |
| `inspect_device` | `GET /api/devices/{id}/structure` 加 `/attributes` | `GET /api/states/{entity_id}` + `get_services_for_target` |
| `query_topology` | `layout.edges` | 本地 edges 配置 |
| `execute_action` | `POST /api/devices/{id}/commands` | `POST /api/services/{domain}/{service}` |
| `time_control`（advance） | `POST /api/simulation/fast_forward_to` | 事件订阅 + 超时 |
| `time_control`（schedule / list / cancel） | `POST /api/schedule/workflow` + 状态查询 | MCP server 自带调度器 |
| `check_goal` | 沙盒状态判定 | 本地条件求值 |
| `query_events` | `GET /api/schedule/workflows` 等 | `/api/logbook`、`/api/history/period` |
| `memory` | 沙盒侧存储 | 本地 sqlite / json |

## 4. 论文里能写出来的工作量

```text
MCP 协议层   独立进程、Streamable HTTP 与 stdio 两种传输、工具 schema、错误码
鉴权         HA 长期令牌与 OAuth 两种接入方式，令牌只存服务端
适配层       实体发现、区域关联、device_id 与 entity_id 的映射、动作模型翻译
补齐层       房间聚合、拓扑配置、调度器、目标断言、等待与条件订阅、记忆持久化
一致性       同一份 ToolSpec 在两个后端的契约测试与回放测试
对照实验     官方 MCP（Assist 工具面）作为 baseline，与我们的 9 工具对照
```

## 5. 与官方 MCP 的关系

```text
官方 MCP    现成，可做 baseline；工具面是 Assist 那套，偏控制，
            缺拓扑、时间、断言、记忆
我们的 MCP  独立发布，9 个工具覆盖观察、控制、时间、验证、记忆
两者并存     实验里同时跑，对比工具调用次数、任务成功率、失败类型
```
