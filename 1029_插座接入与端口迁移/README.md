# 1029_插座接入与端口迁移

主题：京东 SPZ01 智能插座接入成功（HA 可控、MCP 可见）；顺带解决 1883 端口被 Windows 保留段占用、Docker Desktop 锁文件残留两个环境问题

本目录共 12 个文件，来自 simuhome-ljb。核心结论：**京东套装不是整体被锁**——同厂的插电设备 SPZ01 走标准 Zigbee 通道，入网即用，HA 能开关、MCP 能控制；只有电池类设备（PRZ01 人体、WSZ01 开关）才"入网即静默"。这一条推翻了 1027 归档里"整批设备固件被锁"的推断。

## 文档（3）

| 文件 | 原路径 | 内容 |
| --- | --- | --- |
| [13_Zigbee协调器与京东设备接入记录.md](<doc/simuhome-ljb/_work/13_Zigbee协调器与京东设备接入记录.md>) | `_work/13_Zigbee协调器与京东设备接入记录.md` | 主记录的更新版：结论表加入 SPZ01、新增 3.3（端口保留段）与 3.4（Docker 锁文件）、新增 4.4（SPZ01 实测）、改写 4.5 的共同判断 |
| [z2m-README.md](<doc/simuhome-ljb/_work/z2m/README.md>) | `_work/z2m/README.md` | Z2M 运行说明：端口改成 2883、脚本读 MQTT_PORT、设备清单加入 spz01/prz01/wsz01 的判定 |
| [config.md](<doc/simuhome-ljb/_work/mcp/config.md>) | `_work/mcp/config.md` | MCP 配置说明：zigbee 规则的 domains 补上 switch，以及 SPZ01 的 MCP 投影结果 |

## 脚本与配置（9）

| 文件 | 用途 |
| --- | --- |
| [run_broker.py](<doc/simuhome-ljb/_work/broker/run_broker.py>) / [run_broker.md](<doc/simuhome-ljb/_work/broker/run_broker.md>) | broker 支持 `MQTT_PORT` 环境变量；文档补了保留端口段的成因 |
| [publish.py](<doc/simuhome-ljb/_work/broker/publish.py>) / [peek.py](<doc/simuhome-ljb/_work/broker/peek.py>) | 探针脚本同样读 `MQTT_PORT` |
| [config.yaml](<doc/simuhome-ljb/_work/mcp/config.yaml>) | MCP 认领规则：`domains: [sensor, switch]` |
| [rename_test_plug.py](<doc/simuhome-ljb/_work/z2m/rename_test_plug.py>) | 插座改名 spz01 + 连发 ON/OFF/ON 验证控制链路 |
| [assign_plug_area.py](<doc/simuhome-ljb/_work/z2m/assign_plug_area.py>) | 把插座设备挂到 wo_shi（卧室） |
| [fix_ha_mqtt_port.py](<doc/simuhome-ljb/_work/logs/fix_ha_mqtt_port.py>) | 停容器 → 改 `.storage/core.config_entries` 的 mqtt 端口（自动备份）→ 起容器 |
| [port_bind_test.py](<doc/simuhome-ljb/_work/logs/port_bind_test.py>) | 快速判断哪些端口能绑定，用于确认保留端口段 |

## 现场数字

```text
插座      spz01  0x00158d000129e0c4  BEESMART 00090bdc  Router
          MQTT  zigbee2mqtt/spz01/set {"state":"ON"} → 回读 ON/OFF 正常
          HA    switch.spz01 turn_on / turn_off → 状态同步（on→off→on）
          MCP   observe_home wo_shi/卧室 devices:["spz01"]；inspect_device 给出三个动作
端口      broker 2883（原 1883 落入 Windows 保留段 1815-1914）
Docker    删 backend.lock / frontend.lock / launcher.lock 后引擎恢复，HA 容器随之启动
```

## 与 1027 的关系

1027 目录是当天的原始记录，保持不动。本目录的 13 号文档是**更新版**，其中"共同判断"一节已经改写：从"京东这批贴牌设备被锁"改成"只有电池类设备被锁，插电设备正常"。以后看这条线，以本目录的版本为准。
