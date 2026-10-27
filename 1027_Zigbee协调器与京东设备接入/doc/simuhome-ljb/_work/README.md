# _work

放我们自己的改动。目的只有一个：和仓库原有的源文件彻底隔开，方便对照、审查和回滚。

- 原目录一律不动，改动全部写在这里。
- 命名与写法见上一层的 [AGENTS.md](../AGENTS.md)。
- 本目录已用 `.gitignore` 里的 `!/_work/` 单独放行。

## 内容

| 文件 | 说明 |
| --- | --- |
| [01_deploy解读.md](01_deploy解读.md) | 通读 `deploy\` 五份文档 + `compose.yaml` 的整理与核对结果 |
| [02_本机部署记录.md](02_本机部署记录.md) | 本机沙盒实际怎么跑起来的、和文档的差异、验证结果 |
| [03_层三米家接入.md](03_层三米家接入.md) | 层三（米家真机）的准备情况、卡点与登录步骤（进行中） |
| [04_蓝牙音箱MQTT桥.md](04_蓝牙音箱MQTT桥.md) | 蓝牙音箱（ERAZER SAB6）经 MQTT discovery 接进 HA 的设计与实测 |
| [05_Zigbee接入判断.md](05_Zigbee接入判断.md) | Zigbee 在当前网络部署下的可行性（对 17 号文档的补充） |
| [06_氛围灯接入.md](06_氛围灯接入.md) | 第三方接米家的氛围灯：两轮探测判定"不通过米家控制"走不通 |
| [07_大模型接入与E路线实测.md](07_大模型接入与E路线实测.md) | DeepSeek 经我们的 MCP（E 路线）实测 12/12；A 路线装过又按文档口径撤除 |
| [08_美的温湿度计接入情况.md](08_美的温湿度计接入情况.md) | 这台蓝牙/网关型温湿度计为什么进不了 HA、试过什么、以后三条路 |
| [09_当前问题与待办.md](09_当前问题与待办.md) | 所有未决问题的清单：温湿度计主线、树莓派今晚的准备、音箱只差两步等 |
| [13_Zigbee协调器与京东设备接入记录.md](13_Zigbee协调器与京东设备接入记录.md) | ZB-GW04 + Z2M 的落地记录：ember 适配、非 git 目录启动、TH01 可用、PRZ01/WSZ01 入网即静默的实测判据 |
| [z2m\README.md](z2m/README.md) | Zigbee2MQTT 的运行方式、启动命令、踩过的坑与运维脚本清单 |
| [start_sandbox.ps1](start_sandbox.ps1) / [stop_sandbox.ps1](stop_sandbox.ps1) | 一键启停（本机路径版，不动仓库原有脚本） |
| `ha_login.cmd` / `ha_login.ps1` | 用带 DNS 映射的 Edge/Chrome 专用窗口打开 HA，解决小米登录回跳（免管理员） |
| `fix_hosts.cmd` / `fix_hosts.ps1` | 往 hosts 加 `homeassistant.local`，全局永久解决回跳（需点一次 UAC） |
| `broker\run_broker.py` | amqtt 常驻 broker（本机拉不到 Mosquitto 镜像，用仓库推荐的替代路线） |
| `broker\peek.py` | 只读探针：看 broker 上有哪些话题 |
| `broker\publish.py` | 往 broker 发一条消息（排查与测试用） |
| `broker\probe_filter.py` | 验证 broker 的订阅过滤（靠它抓到 amqtt 的 retained 投递问题） |
| `ha\compose.yaml` | 沙盒专用 HA 容器（用本机已有镜像 + 独立配置目录） |
| `ha\onboard.py` | 用 API 完成 HA 初始化并签发长期令牌，不用开浏览器 |
| `ha\add_mqtt.py` | 用 API 添加 MQTT 集成 |
| `ha\inspect_entities.py` | 盘 HA 的集成条目与实体分布（按 platform 分组，走 WebSocket API） |
| `ha\rename_entity.py` | 改 HA 的 entity_id / 友好名（中文名被拼音化时用） |
| `mcp\config.yaml` | MCP server 配置（等价于 `config.example.yaml`，但不写进源目录） |
| `mcp\smoke.py` | MCP stdio 只读冒烟：列工具 + observe_home + inspect_device |
| `mcp\chat.py` | 交互式对话：在终端里跟 DeepSeek 说话，让它经 MCP 读/控 HA 里的设备 |
| `llm\test_llm_surface_local.py` / [同名说明](llm/test_llm_surface_local.md) | 仓库 12 项测试的可运行副本（临时配置改写进临时目录，不落源目录） |
| `llm\` 其余 | 第三方集成包与下载产物（extended_openai_conversation 的 zip 与解压目录） |
| `bt_speaker\bridge.py` | 蓝牙音箱 MQTT 桥：开关 + 音量（量级）+ 播放/TTS |
| `bt_speaker\probe_volume.py` | 探 pycaw 的 API 形状（版本间差异大） |
| `bt_speaker\diag_audio.py` | 音频链路诊断：默认设备、音量、静音、试放 |
| `bt_speaker\probe_devices.py` | 找 sounddevice 里真正能打开的输出设备（WDM-KS 那组打不开） |
| `bt_speaker\probe_sessions.py` | 查 Windows 音频会话状态，客观判断"还有没有在出声" |
| `xiaomi\probe_lan.py` | 局域网 miIO 发现：判断小米设备能不能本地直连 |
| `xiaomi\ap_profile.xml` | 设备配网热点的 Wi-Fi 配置文件（探本地接口时用） |
| `xiaomi\probe_ap_deep.py` | 连上设备热点后的深度探测（端口扫描 / miIO / 涂鸦 / SSDP / mDNS / ARP） |
| `xiaomi\switch_and_probe.ps1` | 一键切换网络并跑深度探测，末尾自动恢复 |
| `llm\` | 大模型接入：12 项测试的可运行副本、下载的第三方集成、撤下来的留档（见 [llm\README.md](llm/README.md)） |
| `ble\scan.py` / [说明](ble/scan.md) | BLE 全量扫描：设备地址、名字、rssi、服务 UUID、厂商数据，并标出疑似温湿度计 |
| `ble\watch.py` / [说明](ble/watch.md) | 两阶段扫描：先建基线，之后只报新出现的设备（按设备按钮时抓它用） |
| `ble\probe_api.py` / [说明](ble/probe_api.md) | 量 bleak 的 `discover()` 在当前机器上返回什么形状（跨版本差异靠它定位） |
| [11_蓝牙桥与Zigbee接入总报告.md](11_蓝牙桥与Zigbee接入总报告.md) | 蓝牙桥与 Zigbee 能不能用的总判定：四条蓝牙路、四条 Zigbee 路、落地顺序与今日实测 |
| `pi\ssh_run.py` / [说明](pi/ssh_run.md) | 在树莓派上跑命令、传文件；支持 sudo（密码走 stdin，不落命令行） |
| `pi\ha_api.py` / [说明](pi/ha_api.md) | 树莓派那台 HA 的接口入口：账号密码换 token，REST 与 WebSocket 都能打 |
| `logs\` | 各进程的日志，不入库（见本目录的 `.gitignore`） |

## 文档约定

本目录里我们自己的每个代码与配置文件，旁边都有一份同名 `.md`：`.py` 写职责、输入、输出、读取、写入、不负责与失败行为；`.yaml` 写数据内容与每个字段的含义；`.ps1` 同样用这套模板。成对的 `.cmd`（三行包装）并进同名 `.ps1` 的那份文档，不单开。命名跟随仓库习惯：`entry.py` 配 `entry.md`。
