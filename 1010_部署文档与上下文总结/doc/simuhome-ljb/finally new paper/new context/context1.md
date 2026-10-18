# context1：HA 接入方案与 MCP 设计（2026-09-16 ~ 09-17 全过程记录）

本文件用于新对话接续。它不是"交付清单"，而是把这一轮**怎么问的、怎么查的、怎么判断的、踩了什么、为什么这么定**完整记下来，让新对话不用重新推一遍。

```text
工作目录      D:\D_coderesource\simuhome
本轮目标      HA 里接进一套可读可控的仿真设备，供我们自建的 MCP 使用
最终选型      MQTT discovery（弃用早期 HTTP bridge 方案）
当前状态      已上线并验证：3 房间 / 15 设备 / 25 实体，读写通，断线变 unavailable

本目录另有一份 上下文总结.md（9 月 10 日）：UbiComp 三支柱讨论、oldmcp/doc7-11 旧蓝图、待拍板 Q1~Q8
仓库根 context\ 里还有 6-7 月的 上下文总结1~6.md，与本文不是同一套系列
```

## 0. 一分钟结论

```text
起点   看不懂两个名字很像的 HA 目录 → 梳理清楚是四个部分
转折   审旧桥接发现结构性问题（HA 里 0 设备 0 区域）→ 必须换接入方式
选型   A MQTT / B 集成改 config entry / C REST+模板 → 选 A（打分 31 / 28 / 19）
落地   M1 broker+HA 集成 → M2 发布器（设备与房间）→ M3 命令回程 → 换 Mosquitto → 退役旧桥接
现在   接入侧已可用；下一步是回到 MCP：按 05 文档从 M1（骨架 + observe_home）开始
```

## 1. 起点：读 UbiComp 三支柱讨论（9/16 晚）

### 1.1 触发

用户要求先读 `finally new paper\UbiComp三支柱讨论\`。我读完 7 份 md + 1 张预览海报，逐份梳理：

```text
1_UbiComp新论文讨论        三支柱总纲：中重量沙盒 + SFT/RL + 同语义 MCP 迁移；含 7 个待拍板问题
2_任务范畴详细版           六任务族 T1~T6 + 四个横切特性；逐族写 SFT/RL 结合与 HA 迁移难度
3_任务范畴简化版（主用稿） 先定义沙盒再列六族；训练四层 L1~L4；迁移四簇 11 接口、三档适配
4_沙盒轻量化设计           按 HomeFlow 附录 A.3 的 Gym 标准重写沙盒；"一个同步内核两个门"
5_Gym 接口与现状差异       Gymnasium 契约逐项对照 SimuHome 现状（六行差异表）
6_Reward 与 Return 区别    教学文档：即时 reward 与累积 return、truncated 的 bootstrap
8_统一语义接口架构         ToolSpec 为唯一语义源 + 方案 A（训练直连 Gym、部署走 MCP）
9_时间机制与推进契约矛盾   tick 长度一身三职、推进权归属、四类矛盾、Gymnasium 官方做法
_preview.png               三栏海报：评测基准 / 沙盒与训练 / 结果与应用
```

### 1.2 我当时的判断（发现了四处不一致）

```text
合理处   三支柱互相咬合：benchmark 指出缺口 → 训练补齐 → 同语义迁移验证
风险处   三支柱体量接近三篇论文；"同 MCP 接口 = 能直接用"会招来 sim-to-real 质疑
不一致一 接口清单在三份文档里有三套命名（observe_home vs get_home_state vs execute_command）
不一致二 海报写 SFT→DPO→GRPO，而主用稿的四层训练里没有 DPO
不一致三 Q1（纯连通图 vs 连通图+传播）其实已被默认成"有传播"——沙盒设计里写了沿边传播
不一致四 本文件夹的 8_/9_ 与 oldmcp\doc\8_/9_ 是同号不同文；doc1/doc2 引用的 doc7/10/11 不在本目录
```

### 1.3 用户反馈与教训

我顺手写了一份"迁移接口映射"文档，被明确制止：**"你不要自作主张，我让你分析就分析"**。

```text
处理   删掉该文档；把 README 与另两份文档里"第三支柱/论文/审稿"的推论全部清掉，只留事实
教训一 分析类任务只交事实，不要把"下一步该怎么做"擅自做成方案
教训二 用户说整理时，范围就是他点名的那一份，不要顺手多做
```

## 2. 两个 HA 目录到底是什么（9/16 晚）

### 2.1 触发

用户问："本地有两个 homeassistant 的仓库，分别是干什么的？分析他们可供外界调用的接口。"

### 2.2 我怎么查的（命令与文件）

```text
git -C "home assistant project\core" remote -v   → github.com/home-assistant/core.git
git log -1                                        → dev 分支 2008551，2026-06-21
core\homeassistant\const.py                       → 版本 2026.7.0.dev0
Get-ChildItem "Home Assistant\"                    → 只有 compose.yaml / bridge\ / 脚本 / logs，没有 HA 源码
Home Assistant\compose.yaml                        → ghcr.io/home-assistant/home-assistant:stable，8123，
                                                     挂载 D:\homeassistant\config
Home Assistant\bridge\app.py                       → FastAPI，监听 8010，上游 127.0.0.1:8000/api
D:\homeassistant\config\custom_components\simuhome  → 真正在跑的集成：api.py / coordinator.py /
                                                     sensor.py / switch.py / manifest.json
```

### 2.3 结论：四个部分

```text
A 官方源码      ha_core_official\core（只读参考，不参与运行）
B 桥接工程      simuhome_bridge_project（compose + bridge + 启动脚本）
C 仿真本体      simuprocject\Simuhome_experiment（:8000，被控端）
D HA 配置目录   D:\homeassistant\config（容器挂载成 /config，集成/账号/历史都在里面）
```

### 2.4 用户追问"官方源码有什么用"时的分析与证据

```text
疑问一  源码是不是没用？  运行上不用（官方已把源码打包成镜像），查证上必须用：
        core\Dockerfile 里有 COPY rootfs /、WORKDIR /usr/src、LABEL io.hass.type="core"
        实证：docker exec homeassistant ls /usr/src/homeassistant → 就是这份源码
疑问二  容器里跑的是哪个版本？ 容器 2026.6.4；本地 clone 是 dev 2026.7.0.dev0（差一个月）
疑问三  HA 是不是有自己的操作系统？ 有：HAOS 独立仓库 home-assistant/operating-system，
        另有 supervisor / frontend；本机是 Container 形态，所以 /api/hassio/* 用不了
```

### 2.5 改名（两次）与连带影响

```text
第一次  用户要求改名帮助区分 → 中文名（HA官方源码_core / SimuHome桥接工程）
第二次  用户担心中文路径解析问题 → 英文名：ha_core_official / simuhome_bridge_project
连带     bridge\app.py 的 LOG_DIR、start_simuhome_bridge.ps1 的 5 处路径、simuhome.Dockerfile 的 COPY、
        README 目录树、Home Assistant官方仓库梳理.md 33 处、oldmcp\doc\9 的 7 处、上下文总结 1 处、
        本目录 4 份文档共 17 处
插曲     批量替换误伤 bridge\__pycache__ 里的 .pyc（二进制被改写）→ 直接删掉，运行时会重建
方法     长路径优先、按文件枚举、保留 BOM 状态，替换后重新扫描确认零残留
```

## 3. 把服务跑起来（9/16 晚）

### 3.1 第一次理解偏了

用户说"拉起一个 SimuHome 的服务"，我起了**裸 SimuHome API（:8000）**，灌入 `home_full.json`（3 房间 15 设备），并做了开灯测试（`living_room_side_light` → `On` → 属性变 true）。

### 3.2 用户纠正

"我要的是 SimuHome 在 HA 里的服务呀" → 目标其实是 **HA 里能看到并控制 SimuHome 设备**。

```text
我做的     启动 Docker Desktop → start_simuhome_bridge.ps1（:8010）→ docker compose up -d（HA :8123）
注意       HA 容器是 restart: unless-stopped，Docker 一启动它自己就回来了
验证方式   不看 UI，而是查 HA 的 recorder 数据库与配置项：
           25 个实体在启动后 2 秒内建立（13 传感器 + 12 开关），实测 26/27/28 °C、45%、on/off
发现缺陷   sensor.virtual_time = unknown ——
           集成读 current_time/time/base_time，而 /api/time 返回的键是 now
```

## 4. "本地源码能对接容器实例吗"的验证（9/17 凌晨）

用户担心"看本地源码推断运行行为"是否成立，我做了哈希级对比：

```text
完全一致   mcp_server\http.py、mcp_server\server.py、components\intent\__init__.py
有差异     helpers\llm.py、websocket_api\commands.py、const.py（版本号本身）
数字差异   WebSocket 命令数：本地 dev 295 条 vs 容器 2026.6.4 293 条
另核实     容器里存在 /api/mcp（Streamable HTTP）与 /mcp_server/sse（旧 SSE）
结论       同一仓库的两份不同版本：核心一致、个别文件漂移；涉及具体数字时要核对
方法       需要时 docker exec 直接读容器内那份，或 git fetch 对应 tag
```

## 5. 接口清单的三次重写（9/17 凌晨）

```text
第一版  两份：HA 官方接口 + SimuHome 桥接侧接口（含 bridge 9 个端点、上游 22 条 API）
反馈一  "之前那个对外接口清单太乱了，我只想看 HA 官方暴露了哪些接口"
第二版  只写 HA：七类通道（REST / WebSocket / 鉴权 OAuth / 对话助手 / MCP Server /
        MCP Client / 集成自有通道）+ 免鉴权清单 + 官方没有的六类能力
反馈二  "2 文档就说清楚了，你用 3 个干什么？完全重写，不要管之前的东西"
第三版  收敛成两份：01 目录与作用、02 HA 官方对外接口；旧 README 与重复文档删除
```

## 6. MCP 架构的思考（9/17 凌晨）

### 6.1 五个核心模块

```text
① Host 模型宿主（应用）→ ② Client 连接器 → ③ 传输层 → ④ 协议层 → ⑤ Server
② 由 SDK 提供；③④ 是标准；只有 ⑤ 是我们写的
```

### 6.2 服务端能力清单（用容器里的 mcp 1.26.0 实测，不凭记忆）

```text
tools        list / call                          模型控制  → 我们用（9 个工具）
resources    list / templates / read / subscribe   应用控制  → 留作升级
prompts      list / get                            用户控制  → 留作升级
logging      设级别 + 日志通知                      服务端    → 计划用
progress     进度通知 + 取消                                  → 计划用
completion   参数补全                                        → 不用
sampling     让宿主模型生成一次（服务端主动请求）      → 明确不用：会污染调用统计
roots        向客户端要工作根目录                            → 不用
elicitation  反过来向用户提问                                → 二期（对应"该澄清就澄清"）
tasks        task/get/list/cancel（长任务句柄）               → 二期（对应预约类）
```

### 6.3 通用与专用的分界

```text
换任何后端都不改   传输、会话、工具注册、schema 校验、错误码、日志、契约测试方法
换后端要重写       ha\rest.py、ha\ws.py、ha\registry.py、ha\actions.py
与领域绑定         conditions.py 的断言语言、time_control 的时间语义、房间与连通的概念
```

### 6.4 第五模块内部不是一层（用户提出的洞察）

用户指出"第五个模块本身复杂、要深度融合进那个软件" → 我把 Server 拆成三层并给出三种集成深度：

```text
L1 协议壳（薄）   工具注册、schema 校验、错误码、日志与进度 —— 与后端无关
L2 语义层（中）   device_id ↔ entity_id、动作映射、房间聚合、条件求值、时间语义
L3 融合层（厚）   HA 的 REST/WS、注册表缓存、事件订阅；再深就是写自定义集成

三种深度  外挂（独立进程调 REST/WS）→ 外挂 + 薄集成 → 进程内集成
         官方 HA MCP 走第三种，所以几乎零适配，代价是绑死版本
```

### 6.5 架构图的四次迭代（svg + png，用 headless Chrome 渲染核对）

```text
第一版  五模块 + 能力层/业务层细节            → 反馈："细节太多，精简"
第二版  五模块 + 一次"开灯"请求的例子          → 反馈："精简是模块内部，不是关系"
第三版  五模块 + 扇出/反向请求/通知/三方分工    → 反馈："Server B/C 放边缘，Server A 占大头"
第四版  A/B/C 三层分组 + ③④ 横切成两条 + ⑤ 内部 a/b/c 三层  ← 现状
```

## 7. MCP 接口的收敛（9/17 凌晨）

### 7.1 先搞清"现在暴露了什么"

读 `simuprocject\Simuhome_experiment\src\agents\tools.py` 的 `TOOL_REGISTRY`：

```text
共 20 个（不是 10 个）：仿真运维 3 + 观察读取 7 + 执行动作 2 + 时间调度 5 + 领域知识 2 + 收尾 1
关键发现：没有任何"推进时间"的工具——模型只能读时间与预约，推不动世界
```

### 7.2 收敛路径

```text
20 → 14   去掉运维 3（加/删设备、改 tick）、知识 2、finish 1
14 → 10   三个读属性合成 inspect_device；三个 workflow 管理合成 manage_tasks
10 → 9    schedule_action 与 wait_until 合成 time_control（op = advance/schedule/list/cancel）
9  → 8    初稿跳过 query_topology
```

### 7.3 两个关键判断

```text
时间两件套为什么能合  底层是同一件事：把世界（或模型自己）的时间推到 T；
                      沙盒侧都靠 fast_forward_to，HA 侧都是"等条件或等真实时间"；
                      合并后仍能按 op 区分"预约"与"等待"，不影响 T4 时序任务的度量
拓扑为什么跳过        HA 只有 area/floor 归属，没有"房间之间的边"；
                      SimuHome 的 home_full.json 里也没有门/窗/连通字段（只有窗帘这类设备）
```

## 8. MCP 初稿设计（9/17 上午到中午）

### 8.1 第一版目录树与自审出的五个结构问题

第一版按"工具名"平铺 `tools\` 与 `ha\`，随后自审出：

```text
1  tools\ 把"协议入口"与"后端实现"混在一个文件里 → 换后端要重写 8 个文件
2  ha\ 混了"怎么连"（rest/ws）与"怎么翻译"（registry/actions），两者变更频率不同
3  ToolSpec 是整个设计的关键（同一份契约两个后端），树里却没有它的落点
4  调度器（后台任务 + 持久化）被塞进 time_control 一个文件里
5  errors 与 tests 归属不清：错误码被协议层和所有后端共用
```

### 8.2 简化版与依赖规则（用户要求"再合并、更解耦"）

```text
目录    contract\（契约与判定）+ backend_ha\（连接与映射）+ server.py + entry.py
        + errors.py + runtime.py（配置 / sqlite / 调度器）
依赖    entry → server → contract
        entry → backend_ha → contract, runtime
        contract 只依赖标准库；backend 不许 import server
硬规则  server.py 里不许出现 entity / domain / service / rest / ws / sqlite 这类后端词汇
例外    entry 到后端是动态导入（importlib + BACKENDS 表），静态扫描看不到这条边
```

### 8.3 解耦探针：用实测代替断言

在 `_架构探针\` 里搭了最小骨架（8 个 py + README），跑六个探针：

```text
P1 依赖方向与环检测     通过：entry → server；server → contract, errors；其余只依赖标准库
P2 协议壳无后端词汇     通过：三个文件命中 entity/domain/rest/ws 全为"无"
P3 换后端零文件改动     通过：只改环境变量，工具表不变、数据真的换了（ha vs fake）
P4 契约强制             通过：后端少实现工具，启动即报错并列出全部缺失项
P5 契约检查跨后端复用   通过：两个后端跑同一套用例
P6 配置占位符 ${VAR}    通过：避开 PyYAML 不认 !env 的坑（实测 safe_load 抛 ConstructorError）
结论之外 5 处语义耦合需显式接口：进度回调、会话隔离、错误码映射、参数语义、动态导入
```

### 8.4 分期还是一口气做完

```text
结论  结构一次定死（目录、依赖、契约、错误码、配置格式），实现分期
台阶 0  SDK 冒烟（不碰 HA）：hello 工具，stdio 与 HTTP 两种传输各连一次
台阶 1  只读：observe_home + inspect_device —— 真 HA 发现 → 录 fixtures → 假 HA 回归
台阶 2  写与判定：execute_action + check_goal —— 真 HA 验时序，假 HA 验请求构造
台阶 3  时间与记忆：time_control + memory —— 假 HA 为主，真 HA 收尾一次
台阶 4  补齐只读三件 + 契约测试 + e2e 验收
理由  外部行为未验证（只跑过读与开关灯）、SDK 行为未验证（只读过方法清单）、
      最确定的 sqlite 与条件求值应该最后做
```

## 9. 接入方案选型（9/17 白天）

### 9.1 为什么要审旧桥接

用户问"那套桥接未必靠谱，审阅一下有没有更好的接法"。我顺着"能不能支撑实验平台"这条判据审，而不是只看它跑不跑得起来。

### 9.2 审出的结构性问题（附源码证据）

```text
最硬的一条：集成走 YAML 平台（async_setup_platform），没有 config entry
  源码证据  homeassistant\helpers\entity_platform.py：
            device: dr.DeviceEntry | None
            if self.config_entry:                     ← 只有 config entry 的实体才注册设备
                if device_info := entity.device_info: ... async_get_or_create(...)
  实测      core.device_registry 设备总数 5（Sun/Backup/TTS/Forecast/HACS），0 个 simuhome 设备
            core.entity_registry 25 个 simuhome 实体，device_id 与 area_id 全为 null
  后果      HA 设备页看不到设备；区域里没有设备；MCP 想按 area 做 list_rooms / inspect_room 直接落空

其他问题
  只识别 1.OnOff.OnOff → 15 台设备只进来 12 个开关，灯亮度/空调温度/窗帘全无
  环境量缺 state_class → recorder 长期统计用不了
  虚拟时间键名不匹配（读 current_time，接口返回 now）
  entity_id 由中文名 slug 派生 → 顺序一变就串
  没有 config_flow → 改地址要改 YAML、不能 UI 重载、不能多实例
bridge 侧 7 个问题：无鉴权 + 0.0.0.0 + 通配反代 22 条接口、上游与日志路径硬编码、
  async 端点里用同步 requests、日志只覆盖三类事件、before/after 在异步下抓不准、
  重启截断 stdout 日志（实测 3 MB → 9 行）、没有契约版本
```

### 9.3 三条路线与打分

```text
A MQTT discovery      发布器轮询 SimuHome → 按 discovery 模板发；HA 用官方 MQTT 集成自动认领
B 集成 config entry 化 把现有集成改成 config_flow + coordinator；自建 area 与设备
C REST + Template     纯 YAML；不写代码

打分（实体覆盖 / 设备与区域 / 推送 / 运维 / 代码量 / 可维护 / 可复现，满分 35）
  A 31   B 28   C 19
决定性差异
  A 的开发循环是秒级（改脚本重启），B 每次要重启 HA 容器（约 40 秒）
  A 的状态流可以同时喂 HA、未来的沙盒后端、实验录制器；B 的数据锁在 HA 里
  本机 Docker Hub 不通 → A 的 broker 要另找来源（PyPI 的 amqtt 或 Mosquitto 官方安装包）
```

### 9.4 速度与"常见性"的实测（用户问了这两个问题）

```text
MQTT 一跳延迟    平均 1.10 ms、p95 1.30 ms（amqtt 探针，qos 0，n=50）
broker 内存增量  5.7 MB（整进程 38 MB，其中 32 MB 是 Python 解释器本身）
吞吐            约 2900 条/秒（我们的负载约 25 条/秒）
真正的瓶颈       SimuHome 自己的 API：50 次 GET /api/time 平均 99.63 ms
                 —— 请求要排进 tick 队列，而 tick 是 0.1 秒
现状的浪费       全屋快照 11.6 KB × 每 10 秒 ≈ 98 MB/天，3 秒内实际变化 0 条（99.9% 是重复搬运）
常见性           MQTT 是 OASIS 标准、IoT 事实标准；HA 有官方集成与 discovery
                 官方 core 里有 13 个集成把 mqtt 列为依赖；生态含 Zigbee2MQTT/Tasmota/ESPHome 等
```

## 10. A 方案落地全过程（9/17 20:00 ~ 21:15）

### 10.1 准备（先把"能不能拿到东西"验证掉）

```text
下载    mosquitto-2.0.20-install-windows-x64.exe（27 MB，mosquitto.org 返回 200）
        amqtt + paho-mqtt + 依赖的离线 wheels（23 个包，约 2.9 MB）
安装    从本地 wheels 离线装进 anaconda：amqtt 0.12.1、paho-mqtt 2.1.0、websockets 15.0.1
探针    _tools\mqtt\probe_mqtt.py：临时起 broker，量延迟与吞吐（上面那组数字）
背景    Docker Hub（registry-1.docker.io）本机不通 → eclipse-mosquitto 镜像拉不下来；
        ghcr.io 可用但 HA 的 mosquitto add-on 镜像返回 denied
```

### 10.2 M1：broker + HA 集成

```text
做法    先起 amqtt（127.0.0.1:1883），再用长期令牌走 REST 配置流自动添加 HA 的 MQTT 集成：
        POST /api/config/config_entries/flow {"handler":"mqtt"} → 拿到 broker/port/protocol/
        username/password/advanced_options 六个字段 → 提交 {"broker":"host.docker.internal",
        "port":1883,"protocol":"3.1.1",...}
结果    entry 创建成功（state loaded），broker 日志看到 HA 连上并进入 connected
读者疑问 令牌要不要手动点？ 要——长期令牌必须从已登录会话签发，
        所以要么用户在 UI 点两下创建，要么给账号密码走登录流程（我们选了前者）
```

### 10.3 M2：发布器（含两个大坑）

```text
文件    publisher.py（主循环 + 命令回程）、discovery.py（payload 生成）、
        simuhome_client.py（只用标准库）、mapping.py（房间/指标/动作映射）、config.yaml
策略    变化驱动 + 死区（温度 0.1 / 湿度 1 / 照度 10 / PM10 1）+ 单实体最快 1 条/秒 +
        活跃 1 秒 / 空闲 10 秒轮询 + retained 状态与 discovery + LWT 离线
坑 1    discovery 的 device.identifiers 我写成 ["simuhome", device_id] —— 那是两个独立标识，
        结果 24 个实体全塌缩到同一台设备、area 也只建出一个。
        修法：identifiers 必须是单元素列表 ["simuhome_<device_id>"]，并把这条写进代码注释
坑 2    SimuHome 的温湿度是放大 100 倍的整数（2600 = 26.00 °C），忘了换算 → HA 显示 2600 °C
        修法：mapping 里给 Metric 加 scale，温度湿度 0.01
附带    中文 name 会被 HA slug 成拼音（sensor.living_room_ke_ting_...）→
        统一改成 object_id + 英文 id，并用 WS config/entity_registry/update 批量改名 24 个实体
验收    3 个 area、15 台设备（全部有 area）、24 个实体，数值与 SimuHome 一致
```

### 10.4 M3：命令回程（写 M2 时一起实现，本轮验证）

```text
成功路径  switch.simuhome_living_room_tv：off → HA turn_on → 200 → HA on ｜ SimuHome True
失败路径  往 simuhome/v1/does_not_exist/set 发 ON → events 主题收到
          {"device_id":"does_not_exist","command":"On","ok":false,
           "error":"POST /devices/does_not_exist/commands 失败：HTTP Error 404","ms":98}
非法输入  payload 写成 MAYBE → 被 to_command 丢弃，不产生命令
```

### 10.5 发现 amqtt 缺陷 → 换 Mosquitto

```text
测试    新客户端只订阅 zzz/none（从没人发布过的主题），等 3 秒
结果    收到 49 条消息，全是别人的 retained（homeassistant/... 的 discovery 与 simuhome/... 的状态）
判断    amqtt 0.12.1 的 retained 投递不按订阅过滤器走；最新版就是 0.12.1，没有修复版
决策    换 Mosquitto（参考实现）。用户装好 2.0.20，我用自带配置起独立实例：
        仅 127.0.0.1、allow_anonymous false、password_file、日志与持久化都在仓库 logs\
踩坑    PowerShell 的 Set-Content -Encoding UTF8 会写 BOM → Python 读出的用户名带 \ufeff，
        认证一直失败（HA 与发布器都报 not authorised）；改 UTF-8 无 BOM 后正常
切换    删除旧 MQTT 条目 → 用带账号密码的方式重建 → HA 与发布器都以 u'simuhome' 连上
复测    隔离测试 0 条（amqtt 时 49 条）；24 个实体全部恢复、0 个不可用
```

### 10.6 退役旧桥接

```text
配置     configuration.yaml 里两段 "platform: simuhome" 删除（先备份 configuration.yaml.bak-20260917）
重启     docker restart homeassistant
清理     注册表里 25 个旧实体（platform=simuhome）全部移除；虚拟时间实体改名为 sensor.simuhome_virtual_time
仪表盘   dashboards\simuhome-dashboard.yaml 全部改用新实体 id；模拟时间卡片指向新的虚拟时间传感器
停进程   bridge（0.0.0.0:8010，PID 49416）停止；8010 不再监听
验收     实体总数 44；旧实体残留：无；新实体 25 个；控制链路仍通；虚拟时间有值（旧集成这一项一直是 unknown）
新增     发布器补了虚拟时间上报（simuhome/v1/time + discovery），顺带修掉老 bug
```

### 10.7 目录改名与 compose 项目名

```text
改名    simuhome_bridge_project → old_simuhome_bridge_project
隐患    目录名会决定 docker compose 的项目名，改名后可能与正在运行的 homeassistant 容器冲突
修法    compose.yaml 顶部显式写 name: simuhome_bridge_project，项目身份固定，容器不受影响
连带    目录内 4 处绝对路径（bridge\app.py、start_simuhome_bridge.ps1、Dockerfile、README）+
        全局 17 处引用（README、.gitignore、update_source.py、01/08/09 文档）
保留    compose.yaml（起 HA 容器）与两个 SimuHome 启动脚本仍在用，暂时和退役代码放在一起
```

## 11. 仓库重建（9/17 下午，穿插进行）

```text
起因    旧 .git 有 4 个提交、733.7 MB、没有远端；工作区有 32 个删除、14 个修改、18 个未跟踪
做法    旧 .git 改名 .git_old_20260917（可恢复）→ git init -b main → 白名单 .gitignore
白名单  finally new paper / ha_mcp_server / simuhome_mqtt_publisher / old_simuhome_bridge_project /
        mcp / _tools / context + 三个根文件；其余大目录一律不入库
登记    _tools\update_source.py 自动生成 source.md：跟踪目录、外部目录（含远端与版本）、被忽略的大文件
        实测能读出 ha_core_official\core → home-assistant/core dev @ 2008551、
        simuprocject\Simuhome_experiment → Mr-luo-q/Simuhome_experiment main @ f8a813f
机密    _secrets\（HA 令牌）与 broker\mosquitto.credentials.txt、mosquitto.passwd 全部 gitignore
踩坑    白名单漏了 simuhome_mqtt_publisher → 30 个文件一度不在版本控制里；已补并提交
现状    255+ 文件、对象库约 4 MB
```

## 12. 当前状态与验证清单

### 12.1 运行时

```text
SimuHome API :8000   PID 31076
发布器               PID 54416（simuhome_mqtt_publisher\publisher\publisher.py）
Mosquitto    :1883   PID 13860（仅 127.0.0.1，账号 simuhome）
HA 容器      :8123   PID 49252（2026.6.4）
旧 bridge    :8010   未监听
默认服务     mosquitto 服务已停、StartType=Manual
数据源唯一：SimuHome → 发布器 → Mosquitto → HA；3 area / 15 设备 / 25 实体
```

### 12.2 "不草率"六条核对

| 标准 | 结果 | 证据 |
| --- | --- | --- |
| 唯一性 | 通过 | 15 设备 25 实体无重复；25 个旧实体已从注册表移除 |
| 完整性 | 通过 | unique_id、area、device_class、state_class 齐全；recorder 生成 12 项统计（has_mean=True） |
| 可回执 | 通过 | 成功与失败命令都进 `simuhome/v1/events`（404 实测） |
| 可观测 | 通过 | LWT 实测：停发布器 8 秒 → 实体 `unavailable`；重启 12 秒 → 恢复 `on` |
| 可重建 | 部分通过 | 重建 MQTT 条目后实体由 retained discovery 自动恢复；reset 场景未测 |
| 可核对 | 通过 | HA 与 SimuHome 数值逐项一致（26/27/28 °C、45/55/40 %、开关 on/off） |

### 12.3 本轮做过的全部验证

```text
broker 往返与延迟（1.10 ms、2900 条/秒）
HA MQTT 集成自动创建（REST 配置流）；HA 以 u'simuhome' 连接
发布器上报 24 实体；HA 侧逐条核对数值
设备与 area 自动创建（3 area / 15 设备，全部有 area）
命令回程成功与失败（404）两条路径
话题隔离测试（Mosquitto 0 条 vs amqtt 49 条）
虚拟时间上报（2025-08-24 06:41:11）
旧链路退役（配置删除、25 个旧实体清除、bridge 停止、仪表盘改新 id）
LWT 断线（unavailable → 恢复）
recorder 统计（12 项 has_mean=True）
本地源码 vs 容器源码哈希对比（6 个文件）
架构探针六项（6/6）
```

## 13. 还没做的与风险

```text
M5-1  reset 之后是否产生重复设备（约 10 分钟）
M5-2  broker 重启后发布器能否自动恢复（约 10 分钟）
M5-3  长时间运行观察（内存、日志滚动、死锁）
M4    录制器（论文要回放时再做）
守护  发布器与 broker 崩溃后没有自动拉起；失败是安全的（实体变 unavailable，不会假数据）
权限  HA 长期令牌曾在对话里明文出现过，建议项目结束后轮换
并发  单实例假设；要并发实验时加 SessionScope（每会话一个 store）
拓扑  query_topology 仍缺，需要手写 edges（二期）
```

## 14. 下一步

```text
1  补 M5-1 / M5-2 两项验证（各 10 分钟）
2  给 broker 与发布器加守护（计划任务或 PID 文件 + 看门狗）
3  回到 MCP：按 05 文档做 M1（骨架 + observe_home），现在有真实实体可读
4  需要长程任务或实验回放时再做 M4 录制器与拓扑 edges

新对话开场建议：先读本文件，再读 05_MCP初稿设计文档.md，然后从 MCP 的台阶 0（SDK 冒烟）开始
```

## 15. 文件地图与常用命令

### 15.1 文档（都在 finally new paper\HomeAssistant双仓库接口分析\）

```text
01 目录与作用              四个部分各是什么、官方源码有什么用、起停、已知缺口
02 HA官方对外接口          七类通道 + 官方 MCP 详解
03 模型接口梳理            20 个工具 → 9 个核心；时间两件套合并的理由
04 自建MCP接口与HA实现      9 个工具怎么用 HA 接口实现
05 MCP初稿设计文档          架构、32 个文件的目录树、依赖规则、模块规格、里程碑（下一步依据）
06 MCP架构通用性说明        五模块与三层关系、通用性判断、SDK 能力清单
08 接入方案综合分析与选型    A/B/C 三方案与打分、速度实测
09 A方案实施细节            主题契约、discovery 模板、发布策略、断线恢复、M5 验收、16 节全过程
10 接入方案总梳理与审查      总梳理 + 反馈 + 审查（含六条核对）
_架构探针                   MCP 分层解耦的六项实测报告
```

### 15.2 常用命令

```powershell
# SimuHome（注意脚本现在在 old_ 目录里）
powershell -File "D:\D_coderesource\simuhome\old_simuhome_bridge_project\start_simuhome_server.ps1"
powershell -File "D:\D_coderesource\simuhome\old_simuhome_bridge_project\reset_simuhome_home.ps1"

# broker 与发布器
powershell -File "D:\D_coderesource\simuhome\simuhome_mqtt_publisher\broker\start_mosquitto.ps1"
powershell -File "D:\D_coderesource\simuhome\simuhome_mqtt_publisher\publisher\start_publisher.ps1"
# 停止：同目录 stop_*.ps1

# HA 容器
docker compose -f "D:\D_coderesource\simuhome\old_simuhome_bridge_project\compose.yaml" up -d

# 读 HA 的注册表（设备/区域/实体只有 WS 能读）
C:\ProgramData\anaconda3\python.exe "D:\D_coderesource\simuhome\_tools\ha_ws.py" config/device_registry/list

# 仓库登记表刷新
C:\ProgramData\anaconda3\python.exe "D:\D_coderesource\simuhome\_tools\update_source.py"
```

## 16. 方法论总结（这一轮真正学到的）

```text
1  先实测再下结论：延迟、内存、retained 泄漏、实体清单、LWT、统计项，全部拿数字说话；
   "应该没问题"在这轮里被证伪过至少三次（amqtt、identifiers、BOM）
2  外部行为只能问外部系统：device_id 命名规则、服务返回字段、异步生效时机，
   都来自真机；假 HA 只能在事实确认后用来做回归
3  结构一次定死、实现分期：目录/依赖/契约改一次动全身，工具实现可以一个个来
4  失败要安全：数据源断了就让实体变 unavailable，绝不停止更新却保留旧值
5  契约要可检查：架构探针与契约测试把"约定"变成"能跑出来的断言"
6  过程要留痕：每一步都记命令与结果（09/10 两份文档），新对话才接得上
7  不要自作主张：分析就只给事实；方案要等对方点头（第 1 节的教训）
```
