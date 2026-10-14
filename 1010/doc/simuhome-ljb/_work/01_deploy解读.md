# 01：deploy 通读整理与核对

> 对象：`deploy\` 下的 5 份文档 + `compose.yaml`（加上根目录 `README.md`、`source.md` 作为背景）
> 核对时间：2026-10-10
> 性质：工作稿，不是仓库行为的证据。结论分两级标注——【已核对】是对着仓库里的实际文件确认过的；【未验证】只是文档里的说法，本次没有实跑。

## 1. deploy 是什么

面向"拿到本仓库、想在自己机器上跑起来"的部署文档组。把整个系统拆成三层，按需组合，互相不强制依赖。

| 层 | 内容 | 前置条件 | 文档 |
| --- | --- | --- | --- |
| 层1 | MCP server ↔ 你的 HA：`ha_mcp_universal\` 暴露 8 个统一语义工具 | 一个能访问的 HA + 长期令牌 | `02` |
| 层2 | 模拟家庭沙盒：SimuHome :8000 → 发布器 → MQTT :1883 → HA 自动发现 25 个实体 | Docker + Python + Mosquitto | `03` |
| 层3 | 米家真机接入：HACS + `XiaoMi/ha_xiaomi_home` → 真机进 HA → MCP 认领 | 米家账号 + 上游集成 | `04` |
| 排错 | 症状对照表、网络、PowerShell、测试、不入库清单 | — | `05` |

阅读路径：只接真机 `02 → 04`；复刻沙盒 `02 → 03`；出问题看 `05`。

## 2. 端口与沙盒数据流

端口约定：

```text
8123   HA Web 与 API
8000   SimuHome 仿真 API
1883   MQTT broker（Mosquitto）
—      MCP 走 stdio 不占端口；可选 HTTP 默认 127.0.0.1:8765
```

层2 的数据流：

```text
SimuHome :8000 ◄─► 发布器（宿主机 Python，轮询 /api/home/state）
                        │  发 MQTT discovery + 状态
                        ▼
                   MQTT broker :1883
                        │  HA 的 MQTT 集成（host.docker.internal:1883）
                        ▼
                   HA :8123   自动出现 25 个实体（switch.simuhome_* 等）
                        ▲
                        └── 命令主题回写 SimuHome
```

## 3. 五份文档各讲什么

- `01_部署总览.md`：三层关系、仓库里有什么 / 没有什么、环境要求、端口约定、阅读顺序。
- `02_快速开始-MCP连接自己的HA.md`：装 `ha_mcp_universal`（`pip install -e .`）→ 复制
  `config.example.yaml` 成 `config.yaml` → 离线/真机冒烟 → 接 MCP 客户端（stdio 的 JSON 片段）
  → 可选 DeepSeek 实测。
- `03_沙盒全链路部署.md`：克隆 SimuHome（`Mr-luo-q/Simuhome_experiment`，实测 commit `f8a813f`）
  → 起 HA 容器 → Mosquitto 建号 → HA 加 MQTT 集成 → 起发布器 → 一键拉起脚本 → 验证 → 停止与重置。
- `04_米家真机接入.md`：HACS 装 `XiaoMi/ha_xiaomi_home` → 登录米家导入设备 → MCP 的 `claim`
  认领规则 → 验证 → 注意事项（云端写入慢、`verified` 语义、掉线、登录风控）。
- `05_常见问题与排错.md`：端口/进程检查命令、症状对照表、容器连宿主 broker（Windows / Linux 差别）、
  PowerShell 坑、测试坑、不入库清单。

## 4. 文档里的关键约定

- **8 个工具**（`tools.expose` 的顺序就是 `tools/list` 的顺序）：
  `observe_home`、`inspect_room`、`inspect_device`、`execute_action`、`finish`、
  `inspect_time`、`time_control`、`memory`。
- **认领规则 `claim`**：`sandbox` 段认 MQTT discovery 的 simuhome 实体；`xiaomi` 段按
  `platforms: [xiaomi_home]` 认米家实体。整段留空 = 退回 v1 行为。
- **验证语义**：`verify_after_action`；本地 MQTT 一次命令加回读约 236~388 ms，云设备可到数秒。
  `verified=false` 表示"命令被收下了、但窗口内没确认落地"——既不算成功也不算调用失败；
  `DEVICE_UNAVAILABLE` 时六字段为 `null`（不是 `false`）。
- **环境要求**：Python 3.13；Docker Desktop；Mosquitto；一键脚本是 Windows PowerShell 版。
- **不在仓库里、需要自备**：SimuHome 上游源码（官方 `holi-lab/SimuHome` 不含 `home_full.json`，
  本链路以 `Mr-luo-q/Simuhome_experiment` 为准）、HA 配置目录、HA 长期令牌 `_secrets\ha_token.txt`、
  MQTT 账号密码。

## 5. 核对结果（对着仓库里的实际文件）

【已核对】`02` / `04` 引用的路径和名字，逐条在仓库里存在：

- 脚本：`simuhome_mqtt_publisher\broker\make_credentials.ps1`、`broker\start_mosquitto.ps1`、
  `publisher\start_publisher.ps1`、`publisher\rename_entities.py`、`_tools\start_simuhome_stack.ps1`
- 测试：`ha_mcp_universal\tests\` 下的 `test_contract_tools.py`、`test_memory.py`、
  `test_time_control.py`、`test_inspect_time.py`、`test_claim.py`、`test_roles.py`、
  `test_e2e_real_ha.py`、`test_llm_surface.py`、`test_llm_fridge.py`
- 入口：`ha_mcp_universal\src\home_mcp\entry.py`

【已核对】`ha_mcp_universal\config.example.yaml` 里的 `claim.xiaomi` 段与 `04` 引用的完全一致
（platforms / domains / id_source / exclude_category / exclude_entities 都对得上），
`tools.expose` 的 8 个名字也和文档一致。

【已核对】`deploy\compose.yaml`：`name: simuhome_bridge_project`，端口 `8123:8123`，
镜像 `ghcr.io/home-assistant/home-assistant:stable`，挂载
`${HA_CONFIG_DIR:?…}:/config`——没设 `HA_CONFIG_DIR` 时 compose 直接报错，避免误建空配置。

【已核对】`README.md` 写明 2026-09-17 重建过仓库，旧 `.git` 改名成 `.git_old_20260917` 留在原地。

## 6. 缺口与待确认

- 【未验证】层2、层3 都需要真机或容器，本次只做了文档与路径核对，没有实际拉起。
- 【未验证】文档里的实测数字（发布器约 10 秒后 HA 出现实体、一键脚本末尾汇总应为
  `3 房间 / 25 实体 / 0 unavailable`）都是本机实测值，换环境要重测。
- 本工作副本里**没有** `simuprocject\`、`_secrets\`、`.git_old_20260917\`、
  `_tools\mqtt\*.exe` 这些"不入库"的内容。也就是说 `source.md` 是在一台带这些目录的机器上
  生成的，而当前副本只有仓库跟踪的部分：层2 的 SimuHome 源码、HA 令牌、Mosquitto 安装包
  都需要按 `03` 重新准备。
- `03` 的一键脚本依赖 PATH 里的 `python`，文档也提示用 uv 的人要先激活 `.venv`；
  这是环境假设，未验证。
- `01` 说"层2 需要 Mosquitto"，而 `_tools\mqtt\` 在本副本里只剩 `README.md` 和
  `probe_mqtt.py`，没有安装包，与 `01` 的说法一致（安装包被 `.gitignore` 排除）。
