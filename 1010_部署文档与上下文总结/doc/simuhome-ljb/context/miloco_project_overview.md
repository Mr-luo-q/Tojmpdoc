# Xiaomi Miloco 2.0 项目梳理

## 一、项目概述

**Xiaomi Miloco** 是小米面向未来的全屋智能 AI 开源方案，运行在家庭本地设备（NUC、树莓派、Mac Mini 等）上。它通过 MiOT 协议管理米家设备、持续感知家庭环境、驱动自动化规则，并通过 OpenClaw 插件将 AI Agent 接入整套能力闭环。

核心设计理念：用户只需用自然语言与 Agent 交流，如"把书房台灯调暗，爷爷在看书"——Miloco 自动识别谁在哪里、联动灯光、并将信息沉淀为家庭记忆。

> **项目位置**：[`milocoproject/xiaomi-miloco-main/`](file:///d:/D_coderesource/simuhome/milocoproject/xiaomi-miloco-main)
> **开源地址**：https://github.com/XiaoMi/xiaomi-miloco
> **许可**：非商业用途（需小米书面授权方可商用）

---

## 二、整体架构

### 2.1 四大工程模块

```
miloco/
├── backend/          # Python FastAPI 后端服务（核心）
│   ├── miloco/       # 主应用：感知引擎、规则、MIoT 网关
│   └── miot/         # MIoT SDK（小米 IoT 独立子包）
├── cli/              # Python Click 命令行工具（miloco-cli）
├── plugins/
│   ├── openclaw/     # TypeScript OpenClaw 插件
│   └── skills/       # 16 个 Agent Skill 定义文档
├── web/              # React 家庭面板前端（SPA）
├── knowledge/        # 项目知识库（架构/特性/开发指南）
└── scripts/          # 安装/构建/同步脚本
```

### 2.2 后端五层架构

后端遵循 **Router → Service → Runner → Repo → 外部代理** 的分层设计：

| 层级 | 职责 | 典型模块 |
|------|------|---------|
| **Router** | 接收 HTTP 请求、参数校验、鉴权前置 | `miot/router.py`, `perception/router.py`, `rule/router.py` 等 |
| **Service** | 业务编排，跨域协调 | `MiotService`, `PerceptionService`, `RuleService`, `PersonService` 等 |
| **Runner** | 异步后台循环，驱动持续任务 | `PerceptionRunner`, `RuleRunner`, `TerminateEvaluator` |
| **Repo** | 数据持久化，隔离 SQLite 细节 | `KVRepo`, `RuleRepo`, `PersonRepo`, `TaskRepo` 等 |
| **外部代理** | 封装第三方 API | `MiotProxy`, `PerceptionEngineProxy` |

`Manager`（`manager.py`）是进程内依赖注入中心单例，各 Router 通过统一入口获取服务实例。

### 2.3 四大主链路数据流

下面四条链路覆盖了 Miloco 从用户输入到设备输出、从环境感知到智能决策的完整闭环。理解这四条链路，就理解了 Miloco 的核心运转方式。

---

#### 链路 1：设备控制链路

这是最简单、最直接的链路——用户想控制某个设备，指令经过层层校验后最终到达硬件。

```
┌─────────────────────────────────────────┐
│ 1. 发起端：用户自然语言意图              │
│    "把客厅灯调暗一点"                    │
│    ↓                                    │
│    Agent 通过 OpenClaw Skill 路由        │
│    选择 miloco-devices Skill             │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 2. CLI 调用                              │
│    miloco-cli 向后端发起 HTTP POST       │
│    Authorization: Bearer <token>         │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 3. Router 层                             │
│    POST /api/miot/devices/{did}/control  │
│    参数解析 + 鉴权前置检查                │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 4. Service 层 — MiotService              │
│    · Scope 校验：设备所属家庭是否在白名单 │
│    · 类型分发：转 MiOT 协议参数格式       │
│      (set_property / call_action 等)     │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 5. Proxy 层 — MiotProxy                  │
│    · Token 生命周期管理（自动刷新）        │
│    · 设备/摄像头/场景列表内存缓存          │
│    · 摄像头 manager 管理                 │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 6. SDK 层 — MIoTClient                   │
│    ├─ Cloud 路径：小米云 HTTP API         │
│    │              （支持远程访问）         │
│    └─ LAN 路径：局域网 UDP 直连            │
│                  （延迟更低）             │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 7. 硬件层 — 米家设备                      │
│    执行动作（灯调暗）                     │
│    状态变化经 Cloud/LAN 回传              │
└─────────────────────────────────────────┘
```

**链路讲解**：

1. **发起端**：用户用自然语言对 Agent 说出意图，如"把客厅灯调暗一点"。Agent 通过 OpenClaw 的 Skill 路由机制，选择 `miloco-devices` Skill 来处理这个请求。

2. **CLI 调用**：Skill 内部通过 `miloco-cli` 命令行工具向后端发起 HTTP 请求。CLI 会自动在请求头中带上 `Authorization: Bearer <token>` 进行鉴权。

3. **Router 层**：请求到达 `miot/router.py` 的 `/api/miot/devices/{did}/control` 端点。Router 负责参数解析和鉴权前置检查。

4. **Service 层 — MiotService**：这是业务编排的核心。它做两件事：
   - **Scope 校验**：检查该设备 `did` 所属的家庭是否在用户启用的家庭白名单内。如果用户同时绑定了"自己的公寓"和"父母家"，但只启用了前者，那么对父母家的设备操作会被拒绝。
   - **类型分发**：将请求转换为 MiOT 协议所需的参数格式（`set_property`、`set_properties`、`call_action` 等）。

5. **Proxy 层 — MiotProxy**：负责 token 生命周期管理（自动刷新、失效时清空缓存）、设备/摄像头/场景列表的内存缓存、以及摄像头 manager 的管理。

6. **SDK 层 — MIoTClient**：小米 IoT SDK 的顶层客户端，内部协调 Cloud（小米云 HTTP API）和 LAN（局域网 UDP 直连）两条路径。Cloud 路径支持远程访问但依赖外网；LAN 路径延迟更低但仅限同子网。上层调用无需感知走的是哪条路径。

7. **设备响应**：设备收到指令后执行动作（如调暗灯光），状态变化通过小米云或 LAN 回传，但控制链路本身到此结束。

**为什么 Scope 校验在 Service 层而非 Proxy 层**：Service 层掌握业务语义（知道用户在操作哪个家庭），而 Proxy 层只负责协议转发。把安全边界放在 Service 层，即使未来新增其他入口（如 Webhook 直接调 Proxy），也不会绕过 scope 校验。

---

#### 链路 2：感知→规则→设备完整链路

这是 Miloco 最核心的自动化链路——摄像头"看到"什么，系统自动判断要不要做动作。整条链路从摄像头码流开始，到设备执行或 Agent 介入结束，全程无需用户参与。

```
阶段 A：数据采集
┌─────────────────────────────────────────┐
│ 1. 摄像头码流接入                        │
│    H.264 视频流 + AAC 音频流             │
│    CameraDeviceAdapter 硬解码            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 2. 时间窗口对齐                          │
│    MultiTrackSyncBuffer 按时间戳对齐     │
│    生成固定长度感知窗口（如 3 秒）        │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 3. 调度触发                              │
│    PerceptionRunner 双触发机制           │
│    · 窗口就绪 → 立即触发                 │
│    · 超时 → 强制触发                     │
│    推理在独立线程执行，不阻塞主循环        │
└─────────────────────────────────────────┘
                    │
                    ▼
阶段 B：感知推理（四层流水线）
┌─────────────────────────────────────────┐
│ 4. Gate 层 — 变化门控                    │
│    ├─ 视觉 Gate：帧差分判断移动          │
│    ├─ 音频 Gate：音频能量峰值            │
│    └─ VAD 子门控：Silero 模型真人声过滤   │
│    无变化 → 跳过下游全部处理              │
└─────────────────────────────────────────┘
                    │ 通过
                    ▼
┌─────────────────────────────────────────┐
│ 5. Identity 层 — 身份识别                │
│    ├─ DeepSortTrackingService            │
│    │   ONNX 人体检测 + ReID 特征向量      │
│    │   DeepSORT 跨帧关联                 │
│    └─ IdentityEngine（四态状态机）        │
│        Fused 识别：VLM 场景理解+识别一次完成│
│    输出：{track_id → person_id}          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 6. Omni 层 — VLM 场景推理                │
│    输入：视频帧 + 音频 + 身份映射         │
│          + home_profile + 规则列表        │
│    模型：VLM（MiMo-v2.5）                │
│    输出：                                │
│    ├─ caption（场景描述）                │
│    ├─ speeches（语音指令）               │
│    ├─ env_sounds（环境声）               │
│    ├─ matched_rules（规则命中）          │
│    └─ suggestions（主动建议）            │
└─────────────────────────────────────────┘
                    │
                    ▼
阶段 C：结果分发
┌─────────────────────────────────────────┐
│ 7. PerceptionEngineProxy 后处理          │
│    ① 写感知日志 → perception_log 表      │
│    ② 规则结果 → RuleRunner               │
│    ③ speeches/suggestions → AgentDispatcher│
│    ④ 有意义事件 → meaningful_events + 视频片段│
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 8. RuleRunner 状态机                     │
│    · 帧级抗抖                            │
│    · 多 source OR 聚合                   │
│    · duration 滑动窗口                   │
│    · 状态机 diff（ENTERED/EXITED/...）    │
└─────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐      ┌──────────────────┐
│ STATIC 规则   │      │ DYNAMIC 规则      │
│ 直接执行      │      │ 自主决策          │
│ MiotProxy →   │      │ RuleTriggerCallback│
│ 设备          │      │ AgentDispatcher   │
│ · 幂等检查    │      │ OpenClaw Webhook  │
│ · 冷却检查    │      │ Agent 决定动作    │
└───────────────┘      └──────────────────┘
```

**链路讲解**：

**阶段 A：数据采集**

1. **摄像头码流接入**：家庭摄像头通过 RTSP/ONVIF 等协议推送 H.264 视频流和 AAC 音频流。`CameraDeviceAdapter`（`miot/camera_handler.py`）通过 MiOT SDK 的 C 库进行硬解码，输出原始帧数据。

2. **时间窗口对齐**：`MultiTrackSyncBuffer`（`perception/collect/stream_buffer.py`）将音视频帧按时间戳对齐，形成固定长度的"感知窗口"（如 3 秒）。这是"多模态"的基础——视觉和音频必须对应同一时间区间。

3. **调度触发**：`PerceptionRunner`（`perception/runner.py`）是后台调度器，采用双触发机制：窗口就绪时立即触发，或采集间隔超时时强制触发。推理在专用单线程 `ThreadPoolExecutor`（`perception-infer`）中执行，不阻塞主事件循环。

**阶段 B：感知推理（四层流水线）**

4. **Gate 层 — 变化门控**：这是整条链路的"省钱开关"。家庭场景大多数时间是静止的（没人走动、没声音），如果每一帧都送 VLM，API 费用会非常高。
   - **视觉 Gate**：计算相邻帧的像素差分，判断是否有人/物体移动。
   - **音频 Gate**：计算音频能量峰值，判断是否有声音。
   - **VAD 子门控**：音频过能量门后，再跑 Silero VAD 模型判断是否为真人声（过滤空调声、冰箱声等背景噪音）。无人声则从输出中剥掉 `speeches` 字段。
   - 如果视觉和音频都判定为"无变化"，整个窗口被丢弃，下游全部跳过。这是核心降本设计。

5. **Identity 层 — 身份识别**：Gate 通过后，进入"这是谁"的识别阶段。
   - `DeepSortTrackingService` 先用 ONNX 人体检测模型找到画面中所有人，再用 ReID 模型提取每个人的外观特征向量，最后用 DeepSORT 算法跨帧关联（卡尔曼滤波预测 + ReID 特征匹配）。
   - `IdentityEngine` 维护每个 track 的四态识别状态机（none/pending/confirmed/unknown），决定何时派发识别请求。
   - 识别采用"Fused 模式"：将待识别人物的 gallery 图像直接注入 Omni 的主调用 prompt 中，让 VLM 一次性完成"场景理解 + 身份识别"，省掉额外的识别请求。
   - 输出是 `{track_id → person_id}` 映射，确认的 person_id 会在 Omni prompt 中以成员名渲染（"爷爷"而非"unknown_1"）。

6. **Omni 层 — VLM 场景推理**：这是感知的"大脑"。
   - 输入：当前窗口的视频帧 + 音频 + 身份映射 + 家庭档案（home_profile）+ 规则列表。
   - 模型：调用 VLM（默认 MiMo-v2.5，OpenAI 兼容协议）。
   - 输出：结构化的 `OmniOutput`，包含：
     - `caption`：场景自然语言描述（"爷爷坐在书房看书"）
     - `speeches`：识别到的语音指令（"Miloco，把灯调暗"）
     - `env_sounds`：环境声音标注
     - `matched_rules`：命中规则列表（每条规则评估为 True/False）
     - `suggestions`：主动建议（"爷爷长时间未移动，建议关注"）
   - 两类调用入口：实时感知（流式）和主动查询（on-demand，跳过 Gate 直接推理）。

**阶段 C：结果分发**

7. **PerceptionEngineProxy 后处理**：推理结果回到代理层，进行四类处理：
   - ① 写感知日志到 `perception_log` 表，供后续摘要和追溯。
   - ② 把所有 enabled 规则的 True/False 评估结果上报给 `RuleRunner`。
   - ③ `speeches` 和 `suggestions` 经 `AgentDispatcher` 投递给 Agent，驱动主动响应。
   - ④ 如果规则命中/语音指令/建议至少一项为真，写入 `meaningful_events` 表并异步保存视频片段（视频字节从编码现场旁路保存，无需重新编码）。

8. **RuleRunner 状态机**：`RuleRunner`（`rule/runner.py`）是规则的核心执行引擎。
   - 接收每帧的规则 True/False 状态。
   - **帧级抗抖**：单帧翻转不立即生效，需连续若干帧确认。
   - **多 source OR 聚合**：同一规则可能关联多个摄像头，任一摄像头命中即算命中。
   - **duration 滑窗**：如果配置了 `duration_seconds`，维护滑动窗口记录 True/False 比例，达标才触发。
   - **状态机 diff**：根据事件模式（event/state）输出 ENTERED / EXITED / STILL_IN / STILL_OUT 状态变化。

9. **规则触发后的两条分支**：
   - **STATIC 规则**：延迟极低，直接调 `MiotProxy` 执行预设设备动作（如开灯）。执行前做幂等检查（属性已达目标则跳过）和冷却检查（冷却期内跳过）。
   - **DYNAMIC 规则**：触发时交给 Agent 在 **isolated 会话** 中自主决策。构造 `RuleTriggerCallback`（含 rule_id / event / prompt_text / room_name），经 `AgentDispatcher` → OpenClaw Webhook 投递。Agent 读取上下文后决定具体动作，文字输出不进主对话流，必须通过 `miloco-notify` Skill 才能让用户感知。

**关键设计决策**：
- **per-device Omni**：每个摄像头独立调一次 VLM，而非多摄像头合并。合并时 prompt 只携带首个摄像头的视频，其他摄像头的 track 无对应视觉信息，识别准确率低。
- **STATIC 绕过 MiotService**：规则在创建时已绑定 scope 内设备，Service 层的 scope 校验冗余。STATIC 路径追求极低延迟，省掉 service 层开销。
- **Suggestion 去重**：同类建议短期内只报一次，用句向量语义相似度（bge-small-zh）去重，而非精确文本匹配——措辞略有差异的同类建议也能识别为重复。

---

#### 链路 3：Agent 主动指令链路

这是用户通过对话主动控制 Miloco 的链路。与链路 1 的区别在于：链路 1 是"用户说一句话→Agent 翻译→调 API"的 Skill 调用；链路 3 更强调整个 Agent 与 Miloco 的双向集成架构。

```
┌─────────────────────────────────────────┐
│ 1. 用户表达意图                          │
│    "帮我设置一个规则，当爷爷长时间没动静   │
│     时提醒我"                            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 2. OpenClaw Agent 理解意图               │
│    大模型解析 → 确定需要创建持久任务      │
│    装配 rule + cron                      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 3. Skill 选择                            │
│    miloco-create-task                    │
│    职责：把模糊意图翻译为内部可执行结构    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 4. CLI 调用                              │
│    miloco-cli task create ...            │
│    HTTP POST /api/tasks                  │
│    Authorization: Bearer <token>         │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 5. Miloco 后端 — TaskService             │
│    · 创建 task 主体（task_id + 描述）     │
│    · 装配 rule（触发条件）               │
│    · 装配 cron（提醒机制）               │
│    · 写入 task_link 关联表               │
│    · 规则进入 RuleRunner 状态机          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 6. 持久化                                │
│    SQLite miloco.db                      │
│    task / task_link / rule 表            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 7. 回调 / 响应                           │
│    {"task_id": "xxx"}                    │
│    → Agent 翻译为友好回复                │
│    "已为您创建监控规则，当爷爷超过 30     │
│     分钟没有动静时提醒"                   │
└─────────────────────────────────────────┘
```

**链路讲解**：

1. **用户表达意图**：用户用自然语言描述需求，如"帮我设置一个规则，当爷爷长时间没动静时提醒我"。

2. **Agent 理解意图**：OpenClaw Agent（底层是大模型）解析用户意图，确定需要创建的任务类型。这里不是简单的设备控制，而是需要创建持久任务：装配一个 rule（"长时间没动静"的条件）+ 一个 cron（提醒机制）。

3. **Skill 选择**：Agent 选择 `miloco-create-task` Skill。这个 Skill 的职责不是"直接执行"，而是"装配任务"——把用户的模糊意图翻译为 Miloco 内部可执行的结构（rule + cron + record + lifecycle）。

4. **CLI 调用**：Skill 内部通过 `miloco-cli` 发起 HTTP POST 请求到 `/api/tasks`。CLI 自动处理鉴权（Bearer token）和参数序列化。

5. **后端处理 — TaskService**：`TaskService`（`task/service.py`）是业务编排核心：
   - 创建 `task` 主体（task_id + 描述 + 状态）。
   - 装配 rule：创建规则"当感知到爷爷长时间未移动时触发"。
   - 装配 cron：创建定时提醒任务。
   - 将 task↔rule/cron 关联记入 `task_link` 表。
   - 规则进入 `RuleRunner` 状态机，开始持续监听。

6. **持久化**：任务和关联写入 SQLite（`miloco.db`），重启后自动恢复。

7. **Agent 回复**：后端返回 `{"task_id":"xxx"}`，Agent 将其翻译为用户友好的回复："已为您创建监控规则，当爷爷超过 30 分钟没有动静时，我会通过音箱提醒您。"

**Skill 与 CLI 的分工**：Skill 负责"语义理解 + 意图翻译"（知道用户要做什么），CLI 负责"协议调用 + 错误处理"（知道怎么调 API）。两者解耦，Skill 可以复用 CLI 的所有能力（鉴权、重试、超时），CLI 也可以独立使用（用户在终端直接敲命令）。

---

#### 链路 4：家庭记忆注入链路

这是 Miloco 的"长期学习"链路——系统从感知和对话中沉淀知识，让 Agent 越来越了解这个家庭。

```
阶段 A：知识来源（两条并行流入）
┌─────────────────────────────────────────┐
│ ① 感知日志（被动来源）                   │
│    Omni caption 每次推理输出             │
│    "爷爷下午在客厅看了 2 小时电视"       │
│    量大、噪声高、被动观察                │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ ② 用户对话（主动来源）                   │
│    用户直接告知 Agent                    │
│    "我爸有高血压，饮食偏淡"              │
│    权重最高，不过期                      │
└─────────────────────────────────────────┘
                    │
                    ▼
阶段 B：知识处理（三层 Cron 流水线）
┌─────────────────────────────────────────┐
│ 第一层：perception-digest                │
│    高频（分钟级）                        │
│    原始 caption → 结构化感知记忆事件      │
│    去冗余、保留变化                      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 第二层：home-patrol                      │
│    中频（数十分钟级）                    │
│    扫描新知识 → 写入候选区               │
│    candidates.json                       │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ 第三层：home-dreaming（每日深夜）        │
│    ├─ Observe：提取知识 → 候选区         │
│    ├─ Promote：候选晋升 → 正式档案       │
│    └─ Prune：  统一 subject + 清理过期   │
│    user_told 可跳过候选区，直进档案       │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ HomeProfileService.commit()              │
│    · 权重排序（时间衰减 + 来源加成）      │
│    · Token 截断（上限内保高权重）         │
│    · 归档/激活区分                       │
│    · 渲染为 profile.md 写盘              │
└─────────────────────────────────────────┘
                    │
                    ▼
阶段 C：知识消费（双路注入）
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐      ┌──────────────────┐
│ Agent 侧注入   │      │ 感知侧注入        │
│               │      │                  │
│ before_prompt │      │ home_profile_    │
│ _build Hook   │      │ loader.py        │
│               │      │                  │
│ 读取 profile  │      │ 注入 Omni prompt │
│ .md           │      │ 动态层           │
│               │      │                  │
│ → 拼档案块    │      │ VLM 识别时具备   │
│ → 追加 system │      │ 家庭背景         │
│   prompt      │      │                  │
│               │      │                  │
│ Agent 每次    │      │                  │
│ 开口都带着    │      │                  │
│ 家庭背景      │      │                  │
└───────────────┘      └──────────────────┘
```

**链路讲解**：

**阶段 A：知识来源（两条并流入）**

1. **感知日志（被动来源）**：每次 Omni 推理输出的 `caption`（如"爷爷下午在客厅看了 2 小时电视"）被批量积累。这是系统"被动观察"到的家庭信息，量大但噪声也高。

2. **用户对话（主动来源）**：用户直接告诉 Agent 的信息（如"我爸有高血压，饮食偏淡"）。这是最高质量的知识来源，权重最高且**不过期**（`source=user_told`）。

**阶段 B：知识处理（三层 Cron 流水线）**

3. **第一层：perception-digest（高频，分钟级）**：
   - 将原始感知日志（大量原始 caption）压缩提炼为结构化的"感知记忆事件"。
   - 去掉冗余（同一人在同一位置连续多帧的描述），保留变化（从客厅到卧室）。
   - 输出进入"交互记忆"池，供后续步骤消费。

4. **第二层：home-patrol（中频，数十分钟级）**：
   - 结合感知记忆和家庭档案，扫描是否有值得记录的新知识。
   - 例如：连续多天观察到"晚上 22:00 后客厅无人、卧室有人"，提取候选知识"家庭通常 22:00 入睡"。
   - 新知识先进入**候选区**（`candidates.json`），不直接进入正式档案。

5. **第三层：home-dreaming（每日深夜）**：
   - 这是一个三阶段的"知识整理夜班"：
     - **Observe 步**：从感知记忆和交互记忆中提取可沉淀知识，写入候选区。
     - **Promote 步**：候选区中积累足够证据（多次独立观察证实）的知识晋升为**正式档案**。
     - **Prune 步**：统一 subject 绑定（成员改名后档案随之更新）、清理过期数据、触发 commit。
   - 用户直接告知的知识（`user_told`）可跳过候选区，直接进入正式档案。

6. **HomeProfileService.commit()**：正式档案变更后的统一提交动作：
   - **权重排序**：综合时间衰减（不同条目衰减速率不同）、来源加成（`user_told` 最高）、证据数量。
   - **token 截断**：档案注入受 token 上限约束，超出时按权重截断，确保最相关的知识排在前面。
   - **归档/激活**：低权重知识移入归档区，高权重知识保持激活。
   - **渲染写盘**：最终渲染为 Markdown 格式的 `profile.md`，写入 `$MILOCO_HOME/home-profile/`。

**阶段 C：知识消费（双路注入）**

7. **Agent 侧注入**：每次 Agent turn 前，OpenClaw 插件的 `before_prompt_build` Hook（`plugins/openclaw/src/hooks/prompt.ts`）读取 `profile.md`，将家庭档案块追加到 system prompt 末尾。这意味着 Agent 每次开口都带着家庭背景知识——不需要用户每次重复"我爸有高血压"。

8. **感知侧注入**：每次 Omni 推理时，`home_profile_loader.py`（`perception/engine/omni/home_profile_loader.py`）将档案内容注入 Omni prompt 的动态层。这让 VLM 在识别和描述时也具备家庭背景——知道"书房里的人是爷爷"而非"一个老人"。

**为什么设计候选区/正式档案两层**：防止单次偶然观察直接污染 Agent 的长期记忆。例如摄像头某次误判"家里有人在跳舞"，如果直接写入档案，Agent 可能会在以后回复中提及这条错误信息。候选区机制要求多次独立观察证实后才晋升，显著降低了噪声污染。

**正反馈闭环**：档案越丰富 → VLM 识别描述越精准 → 感知日志质量越高 → 提取的知识越可靠 → 档案越丰富。这是一个自我增强的循环。

---

---

## 三、技术栈

| 组件 | 技术 |
|------|------|
| **Web 框架** | FastAPI + Uvicorn（单进程） |
| **持久化** | SQLite（`miloco.db` 业务数据 + `observability.db` 性能追踪） |
| **配置** | pydantic-settings（优先级：环境变量 > `config.json` > `settings.yaml` > 代码默认值） |
| **设备协议** | MiOT（OAuth2 + 小米云 API + LAN OT 协议 + 摄像头 C 库） |
| **感知** | OpenCV + ONNX Runtime（人体检测 + ReID）+ VLM（MiMo，可配置） |
| **CLI** | Click + httpx |
| **插件** | TypeScript + OpenClaw Plugin SDK |
| **前端** | React 19 + Vite + Tailwind CSS（中英双语 i18n） |
| **包管理** | uv workspace（Python）/ pnpm（TypeScript） |
| **音视频** | jMuxer（实时视频流 muxing）/ Silero VAD（语音活动检测） |

---

## 四、九大能力域详解

### 4.1 设备控制（Device Control）

通过 MiOT 协议操控米家设备，是系统最基础的能力。

**能力**：属性控制（亮度/色温/温度/开关/模式）、动作调用（TTS 播报/清扫/自动清洁）、属性查询、场景执行（回家模式/睡眠模式）、Scope 管理。

**架构**：
```
CLI / Agent → /api/miot/devices/{did}/control → MiotService（scope 校验）
  → MiotProxy → MIoTClient → Cloud HTTP / LAN UDP → 设备
```

**Scope 机制**：
- **Home Scope**：管控哪个家庭的设备（用户可能有多个家庭）
- **Camera Scope**：在启用家庭内，选择性禁用某些摄像头
- Scope 变更后热同步感知层 adapter，无需重启服务

**关键文件**：
- `backend/miloco/src/miloco/miot/service.py` — 业务编排层
- `backend/miloco/src/miloco/miot/client.py` — MiotProxy 代理层
- `backend/miloco/src/miloco/miot/router.py` — API 路由

---

### 4.2 环境感知（Perception Pipeline）

从家庭摄像头持续采集音视频，自动分析场景变化，将结果驱动规则自动化和 Agent 主动介入。

**四层流水线架构**：

```
CameraDeviceAdapter
  → MultiTrackSyncBuffer（音视频时间窗口对齐）
  → PerceptionRunner 触发
    ↓
MultimodalCollector（perception/collect/collector.py）
  ↓
PipelineProcessor（perception/processor.py）
  ↓
PerceptionEngineProxy（perception/client.py）
  ↓  per-device 串行
  Gate → 过滤静止窗口（None 则跳过后续，核心降本设计）
    ↓ 通过
  Identity → {track_id → person_id} 映射
    ↓
  Omni（VLM）→ OmniOutput
    ├─ caption / speeches / env_sounds
    ├─ matched_rules（命中规则列表）
    └─ suggestions
```

**核心输出**：
- **caption**：自然语言场景描述（"爷爷坐在书房看书"）
- **person_id**：识别家庭成员身份，陌生人分配 `unknown_<n>` 编号
- **speeches**：识别家人对 Miloco 发出的语音指令
- **matched_rules**：规则命中列表驱动自动化
- **suggestions**：主动建议（如老人长时间未移动）

**关键设计**：
- **Gate 层**：帧差分 + 音频能量过滤静止窗口，是核心降本设计
- **DeepSORT 跟踪**：引入 ReID 特征关联，跨帧关联更鲁棒
- **per-device Omni**：每个摄像头独立调一次 VLM，而非多摄像头合并
- **Suggestion 去重**：用句向量语义相似度（bge-small-zh）而非精确文本匹配

**关键文件**：
- `backend/miloco/src/miloco/perception/engine/api.py` — PerceptionEngine 顶层入口
- `backend/miloco/src/miloco/perception/engine/pipeline.py` — 流水线编排
- `backend/miloco/src/miloco/perception/engine/gate/gate.py` — Gate 层
- `backend/miloco/src/miloco/perception/engine/identity/` — 身份识别
- `backend/miloco/src/miloco/perception/engine/omni/omni.py` — VLM 场景推理

---

### 4.3 身份识别（Person Identity）

通过 face / body_appearance 两类视觉特征，把摄像头看到的人与家庭成员档案对应起来。

**三层样本设计**：
- **tier_a**（用户主动登记）：永久保留，最可靠的参照样本
- **tier_c**（系统自动沉淀）：FIFO 滚动更新，跟上人物外观自然变化
- **tier_u**（陌生人池）：全内存、重启即清，供主动注册抽样

**实时识别链路**：
```
TrackingService（DeepSORT 跟踪）→ active tracks
  → IdentityEngine（四态状态机：none/pending/confirmed/unknown）
    ├─ 未识别 → Fused 路径调用 Omni → identity_assignments
    ├─ confirmed → 周期性重审
    └─ unknown → 累积 crop 到 TierUPool
  → {track_id → person_id} 映射
  → Omni prompt 中成员名渲染
```

**关键文件**：
- `backend/miloco/src/miloco/perception/engine/identity/engine.py` — IdentityEngine
- `backend/miloco/src/miloco/perception/engine/identity/library.py` — IdentityLibrary
- `backend/miloco/src/miloco/perception/engine/identity/tier_u.py` — TierUPool
- `backend/miloco/src/miloco/perception/engine/identity/registration_session.py` — 注册会话
- `backend/miloco/src/miloco/person/` — 成员 CRUD API

---

### 4.4 自动化规则（Rule Automation）

用自然语言描述"当 X 时，做 Y"，VLM 负责语义判断。

**四象限规则矩阵**：

| | event 模式 | state 模式 |
|---|---|---|
| **STATIC** | 单次触发，直接执行预设设备指令 | 进入/退出状态时，各自执行预设设备指令 |
| **DYNAMIC** | 单次触发，交给 Agent 自主决策 | 进入/退出状态时，各自交给 Agent 决策 |

**模式说明**：
- **event**：条件 False→True 触发一次，不关注持续时长
- **state**：监听 ENTERED/EXITED 两个边界，适合"持续存在时保持 Y"
- **STATIC**：低延迟、高确定性，直接执行设备指令
- **DYNAMIC**：规则只写意图描述，触发时交给 Agent 结合上下文决定具体操作
- **duration 扩展**：滑动窗口累计触发，防止单帧误判

**关键设计**：
- **帧级抗抖**：连续若干帧确认才翻转状态
- **state 退出防抖**：应对 LLM 短暂漏识
- **DYNAMIC isolated 会话**：文字输出不进主对话流，不自动发声
- **query 措辞校验**：拒绝以"检测到/识别到"等断言性词汇开头的 query

**关键文件**：
- `backend/miloco/src/miloco/rule/service.py` — RuleService（CRUD + 校验）
- `backend/miloco/src/miloco/rule/runner.py` — RuleRunner（状态机 + 触发分发）
- `backend/miloco/src/miloco/rule/terminate_evaluator.py` — temporary 规则到期评估

---

### 4.5 家庭记忆（Home Profile）

从感知与对话中沉淀长期知识，注入每次 Agent 对话的 system prompt。

**知识来源**：
1. **感知日志**：caption 被周期性摘要（`miloco-perception-digest`）
2. **对话主动告知**：用户直接告知 Agent（`source=user_told`，权重最高且不过期）
3. **家庭巡检**：`miloco-home-patrol` 周期扫描提取候选知识

**知识写入路径**：
```
感知日志 / 用户对话
  → Cron: miloco-perception-digest（高频，分钟级）
  → Cron: miloco-home-patrol（中频，数十分钟级）
  → Cron: miloco-home-dreaming（每日深夜）
      Observe → 提取知识 → 候选区
      Promote → 达标候选晋升 → 正式档案
      Prune → 统一主体 + 清理过期
        → HomeProfileService.commit()
            权重排序 + token 截断 + 归档/激活
            → profile.md 写盘
```

**档案消费双路**：
1. **Agent 侧**：`before_prompt_build` Hook 读取 `profile.md` 追加到 system prompt
2. **感知侧**：`home_profile_loader.py` 注入 Omni prompt 动态层

**关键文件**：
- `backend/miloco/src/miloco/home_profile/service.py` — HomeProfileService
- `backend/miloco/src/miloco/home_profile/store.py` — 存储层
- `plugins/openclaw/src/hooks/prompt.ts` — Agent 注入 Hook
- `plugins/openclaw/src/home-profile/` — TS 侧档案调度

---

### 4.6 任务管理（Task Management）

把"持续运转的家庭任务"从一次性自动化升级为带累积统计与生命周期的可追踪任务。

**两模块协作**：`task/`（任务生命周期主体）+ `task_record/`（行为统计载体）

**三种统计形态**：
- **progress（进度型）**：有明确目标值与单位的累积，如"每天喝 8 杯水"
- **duration（时长型）**：累积时长，支持开始/结束计时段，如"练琴 60 分钟"
- **event（事件型）**：只记发生次数与时间线，无目标，如"记录老人每次起夜"

**周期归档**：周期型任务跨周期时自动归档上一期成绩、开启新一期。

**关键文件**：
- `backend/miloco/src/miloco/task/service.py` — TaskService
- `backend/miloco/src/miloco/task_record/service.py` — TaskRecordService
- `backend/miloco/src/miloco/task_record/rollover.py` — 周期归档调度

---

### 4.7 AI Agent 集成（OpenClaw Integration）

通过 OpenClaw 插件与 AI Agent 深度集成，形成双向通信闭环。

**Agent → Miloco（主动控制）**：用户自然语言请求 → Agent 选 Skill → miloco-cli 调 HTTP API

**Miloco → Agent（主动回调）**：感知/规则触发 → AgentDispatcher → OpenClaw Webhook → Agent 自主执行

**16 个 Skill 分组**：

| 功能域 | Skill 名称 | 核心职责 |
|--------|-----------|---------|
| **任务管理** | `miloco-create-task` | 任务装配（rule/cron/record/lifecycle） |
| | `miloco-terminate-task` | 任务终止 |
| **家庭记忆** | `miloco-home-profile` | 档案直写 |
| | `miloco-home-observe` | 提取知识写入候选区 |
| | `miloco-home-promote` | 候选知识晋升 |
| | `miloco-home-prune` | 统一主体 + 清理过期 |
| | `miloco-home-patrol` | 家庭巡检 |
| | `miloco-perception-digest` | 感知日志压缩 |
| | `miloco-habit-suggest` | 习惯洞察推荐 |
| **MiOT 操作** | `miloco-devices` | 设备控制与查询 |
| | `miloco-miot-scope` | 感知范围控制 |
| | `miloco-perception` | 感知统一入口 |
| | `miloco-miot-admin` | 系统运维 |
| **身份管理** | `miloco-miot-identity` | 家庭成员档案 CRUD |
| | `miloco-miot-identity-register` | 身份注册主流程 |
| **通知** | `miloco-notify` | 通知分发（TTS/IM/米家推送） |

**关键文件**：
- `plugins/openclaw/src/index.ts` — 插件入口
- `plugins/openclaw/src/hooks/prompt.ts` — before_prompt_build Hook
- `plugins/openclaw/src/webhooks/agent.ts` — Agent Webhook 接收
- `backend/miloco/src/miloco/dispatch/dispatcher.py` — AgentDispatcher

---

### 4.8 实时摄像头观看（Live Camera View）

浏览器无插件直播，与感知流水线共享解码。

**架构**：`CameraDeviceAdapter` 通过 MiOT SDK 解码层订阅摄像头帧，与感知流水线共享同一次解码，避免重复推流。

**前端**：web 面板"概览"标签提供实时摄像头直播入口，使用 jMuxer 进行实时视频流 muxing。

---

### 4.9 设备欢迎（Device Welcome）

新设备绑定后主动通知用户，建立"Miloco 已接管该设备"的信任感。

用户在米家 App 绑定新设备后，几秒内音箱播报欢迎语，提示可以直接语音控制。

---

## 五、家庭面板（Web Dashboard）

React SPA，构建产物由 backend `spa_handler` 伺服，无需独立前端服务器。

**五个主标签页**：

| 标签 | 内容 | 独有操作 |
|------|------|---------|
| **概览（now）** | 当前在家成员、摄像头状态、感知启停 | 实时摄像头直播、感知引擎启停 |
| **设备（devices）** | 按房间展示设备列表、属性查询、开关控制 | 直接点击控制设备 |
| **家庭（family）** | 成员档案、正式家庭记忆、待审候选知识 | 人脸注册、成员管理 |
| **日志（activity）** | 今日有价值事件流，可回放视频片段 | — |
| **模型（usage）** | LLM Token 用量统计（今日/近7天/近30天） | — |

**部署**：单端口模型，backend 永远 HTTP，访问 `http://<host>:1810/` 直接拿到 SPA。

**关键文件**：
- `web/src/App.tsx` — 主应用
- `web/src/api/` — API 客户端
- `web/src/components/` — React 组件
- `web/src/i18n/` — 中英双语国际化

---

## 六、命令行工具（miloco-cli）

基于 Click 的 Python CLI，随 Miloco 一起安装。

**核心命令**：

| 命令 | 说明 |
|------|------|
| `miloco-cli service start/stop/status/logs` | 管理后端服务 |
| `miloco-cli device list/control` | 交互 IoT 设备 |
| `miloco-cli config show/get/set` | 查看和修改配置 |
| `miloco-cli account bind` | 绑定小米账号（OAuth） |
| `miloco-cli dashboard` | 打开家庭面板 |
| `miloco-cli scope camera enable/disable <did>` | 启停摄像头感知 |

**配置文件**：`$MILOCO_HOME/config.json`（默认 `~/.openclaw/miloco/config.json`）

**环境变量覆盖**：`MILOCO_MODEL__OMNI__API_KEY`、`MILOCO_SERVER__URL` 等

**关键文件**：
- `cli/src/miloco_cli/main.py` — CLI 入口
- `cli/src/miloco_cli/commands/` — 各命令实现

---

## 七、数据持久化

### 7.1 SQLite 数据库

**`miloco.db`** — 业务数据（18 张表）
- `person` — 家庭成员
- `rule` / `rule_log` — 规则及日志
- `task` / `task_link` — 任务及关联
- `task_record_progress` / `task_record_duration` / `task_record_event` — 任务记录
- `task_terminate_log` — 终止审计
- `kv` — 键值存储（scope、token、UUID 等）
- `meaningful_events` — 有价值事件沉淀
- `perception_log` — 感知日志
- `token_usage` — Token 用量统计

**`observability.db`** — 性能追踪
- `traces` / `traces_device` — 追踪记录
- `events` — 事件统计
- `agent_runs` — Agent 运行记录

### 7.2 文件系统存储

- `$MILOCO_HOME/home-profile/` — 家庭档案（`candidates.json` / `profile.json` / `profile.md`）
- `$MILOCO_HOME/data/identity_lib/persons/` — 身份样本库（tier_a / tier_c）
- `$MILOCO_HOME/trace/agent/` — Agent trace JSONL（debug 模式）
- `$MILOCO_HOME/trace/omni/` — Omni log

---

## 八、配置体系

三端共享配置，优先级从高到低：

1. **环境变量**：`MILOCO_MODEL__OMNI__API_KEY`（`__` 表示嵌套）
2. **`$MILOCO_HOME/config.json`**：用户级配置，通过 CLI 管理
3. **`settings.yaml`**：后端默认值（`backend/miloco/src/miloco/config/settings.yaml`）
4. **代码默认值**

**主要配置段**：
- `model.omni` — VLM API Key、Base URL、模型名
- `server` — host、port、token
- `perception` — 感知参数（采集间隔、Gate 阈值、Omni 配置）
- `rule` — 规则参数（抗抖帧数、duration 默认值）
- `miot` — 小米云服务器、OAuth 配置
- `directories` — 工作目录

---

## 九、可观测性

### 9.1 节点监控（Node Monitor）

注册监控节点：CAMERA、COLLECTOR、PROCESSOR、ENGINE、RULE、MIOT_PROXY 等。

- **健康检查**：`/health` — 503 表示至少一个节点 FAILED 或 STALLED
- **资源监控**：内存（smaps/vmmap）、Python 堆、性能指标
- **Watchdog**：节点超时自动标记 STALLED

### 9.2 性能追踪

每个感知 cycle 完成后，`MetricsClient` 将 cycle 级汇总和 per-device 细节异步写入 `observability.db`。

追踪内容：各阶段耗时、Gate 通过率、Omni 调用次数和错误类型。

web 面板 URL hash `#perf` 可查看时序图和分布。

### 9.3 日志清理

后台定时任务清理：
- 感知日志（perception.log_ttl）
- 规则日志（rule.log_ttl）
- Trace JSONL（trace_jsonl_days）
- 可观测性表（traces/events/agent_runs）
- Omni log（omni_log_days）
- 有意义事件（event_ttl_days）
- 事件截图（TTL + LRU）

---

## 十、安装与启动

### 10.1 环境要求

- **硬件**：≥ 4GB RAM，≥ 256GB 存储，推荐 Mac mini
- **操作系统**：macOS / Linux（WSL on Windows）
- **前置**：小米账号 + 米家设备 + 多模态大模型 API Key（推荐 MiMo）

### 10.2 安装方式

**方式一：Agent 安装（推荐）**
```text
请帮我安装 Miloco 插件：https://raw.githubusercontent.com/XiaoMi/xiaomi-miloco/main/scripts/install-guide.md
```

**方式二：命令行安装**
```bash
curl -LsSf https://github.com/XiaoMi/xiaomi-miloco/releases/latest/download/install.sh | bash
```

**方式三：源码构建**
```bash
bash scripts/install.sh --dev
```

### 10.3 启动

```bash
# CLI 后台 daemon（推荐）
miloco-cli service start

# 或直接前台跑
uv run miloco-backend

# 打开家庭面板
miloco-cli dashboard   # http://<host>:1810/
```

### 10.4 初始配置

1. **配置模型**：web 面板"Models"页输入 MiMo `api_key`
2. **绑定小米账号**：自动拉取米家设备
3. **启用摄像头感知**：web 面板"概览"页开启摄像头开关

---

## 十一、代码关键文件索引

### 11.1 后端核心

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **入口** | `backend/miloco/src/miloco/main.py` | FastAPI 应用入口、lifespan、路由注册 |
| **管理器** | `backend/miloco/src/miloco/manager.py` | 依赖注入单例 Manager |
| **配置** | `backend/miloco/src/miloco/config/settings.py` | pydantic-settings 配置定义 |
| **数据库** | `backend/miloco/src/miloco/database/connector.py` | SQLite 连接与建表 |

### 11.2 设备控制

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **业务层** | `backend/miloco/src/miloco/miot/service.py` | MiotService |
| **代理层** | `backend/miloco/src/miloco/miot/client.py` | MiotProxy |
| **API** | `backend/miloco/src/miloco/miot/router.py` | 设备控制路由 |
| **SDK** | `backend/miot/src/miot/client.py` | MIoTClient 顶层客户端 |

### 11.3 感知流水线

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **顶层入口** | `backend/miloco/src/miloco/perception/engine/api.py` | PerceptionEngine |
| **流水线** | `backend/miloco/src/miloco/perception/engine/pipeline.py` | PipelineProcessor |
| **Gate** | `backend/miloco/src/miloco/perception/engine/gate/gate.py` | 变化门控 |
| **身份** | `backend/miloco/src/miloco/perception/engine/identity/engine.py` | IdentityEngine |
| **跟踪** | `backend/miloco/src/miloco/perception/engine/identity/tracking_service.py` | DeepSORT 跟踪 |
| **Omni** | `backend/miloco/src/miloco/perception/engine/omni/omni.py` | VLM 场景推理 |
| **结果处理** | `backend/miloco/src/miloco/perception/client.py` | PerceptionEngineProxy |
| **调度** | `backend/miloco/src/miloco/perception/runner.py` | PerceptionRunner |

### 11.4 规则引擎

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **CRUD** | `backend/miloco/src/miloco/rule/service.py` | RuleService |
| **状态机** | `backend/miloco/src/miloco/rule/runner.py` | RuleRunner |
| **到期评估** | `backend/miloco/src/miloco/rule/terminate_evaluator.py` | TerminateEvaluator |
| **API** | `backend/miloco/src/miloco/rule/router.py` | 规则路由 |

### 11.5 任务管理

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **任务** | `backend/miloco/src/miloco/task/service.py` | TaskService |
| **记录** | `backend/miloco/src/miloco/task_record/service.py` | TaskRecordService |
| **归档** | `backend/miloco/src/miloco/task_record/rollover.py` | 周期归档 |

### 11.6 家庭记忆

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **业务层** | `backend/miloco/src/miloco/home_profile/service.py` | HomeProfileService |
| **存储** | `backend/miloco/src/miloco/home_profile/store.py` | 文件存储 |
| **Agent 注入** | `plugins/openclaw/src/hooks/prompt.ts` | before_prompt_build Hook |
| **Omni 注入** | `backend/miloco/src/miloco/perception/engine/omni/home_profile_loader.py` | 感知侧注入 |

### 11.7 Agent 集成

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **插件入口** | `plugins/openclaw/src/index.ts` | register 所有扩展点 |
| **调度器** | `backend/miloco/src/miloco/dispatch/dispatcher.py` | AgentDispatcher |
| **Webhook** | `plugins/openclaw/src/webhooks/agent.ts` | 接收后端回调 |
| **设备目录** | `plugins/openclaw/src/services/catalog.ts` | 构建设备目录 |

### 11.8 前端

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **主应用** | `web/src/App.tsx` | React SPA 入口 |
| **API** | `web/src/api/real.ts` | 后端 API 调用 |
| **组件** | `web/src/components/` | React 组件集 |
| **国际化** | `web/src/i18n/` | 中英双语 |

### 11.9 CLI

| 模块 | 关键文件 | 说明 |
|------|---------|------|
| **入口** | `cli/src/miloco_cli/main.py` | Click CLI 入口 |
| **命令** | `cli/src/miloco_cli/commands/` | 各命令实现 |
| **客户端** | `cli/src/miloco_cli/client.py` | HTTP 客户端 |

---

## 十二、与 SimuHome 的关系

Miloco 与 SimuHome 是两个不同定位的项目，但在智能家居 Agent 领域有互补性：

| 维度 | **Miloco** | **SimuHome** |
|------|-----------|-------------|
| **定位** | 真实家庭环境的 AI Agent 运行时 | 智能家居 Agent 的仿真评估基准 |
| **运行环境** | 真实家庭本地设备（NUC/Mac Mini） | 纯软件仿真环境 |
| **设备** | 真实米家设备（通过 MiOT 协议） | 虚拟设备（Matter 协议仿真） |
| **感知** | 真实摄像头音视频（VLM 理解） | 无真实感知，环境变量由仿真器生成 |
| **时间** | 真实时间（1:1） | 离散 Tick + 时间跳跃加速 |
| **用途** | 实际部署运行的智能家居系统 | 研究/评估 Agent 能力的测试平台 |

Miloco 解决的是"在真实家庭里怎么跑起来"的工程问题；SimuHome 解决的是"怎么评估 Agent 好不好"的研究问题。两者可以结合使用：在 SimuHome 中验证 Agent 策略，再将成熟策略部署到 Miloco 真实环境。

---

## 十三、总结

Miloco 是一个工程复杂度极高的项目，核心挑战在于将多模态感知（视觉+音频）、大模型推理（VLM）、IoT 设备控制、规则引擎、身份识别、家庭记忆、Agent 集成等多个异构系统整合为一个协调运转的智能家居平台。

其架构设计体现了几个关键思想：

1. **分层解耦**：Router/Service/Runner/Repo/代理五层分离，各域独立演进
2. **事件驱动**：感知→规则→设备的异步事件流，Agent 双向回调
3. **降本设计**：Gate 层过滤静止窗口，避免无意义的 VLM 调用
4. **记忆闭环**：感知→档案→感知的正反馈，档案越丰富识别越精准
5. **用户可控**：Scope 机制让用户决定管控边界，家庭记忆有候选区审核
