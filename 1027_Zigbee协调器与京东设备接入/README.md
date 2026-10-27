# 1027_Zigbee协调器与京东设备接入

主题：ZB-GW04（Silicon Labs EFR32）接入本机，Zigbee2MQTT 跑起来，HA 与 MCP 打通；京东套装三台设备只有 TH01 可用

本目录共 34 个文件，来自 simuhome-ljb。核心结论：协调器链路完全打通（TH01 温湿度计入网即用，HA 出实体、MCP 出房间环境量）；但同为京东套装的 PRZ01 人体感应与 WSZ01 无线开关"入网即静默"——能入网、能 announce，却不往标准通道上报、且拒绝建立绑定，固件把数据路径锁在已经停服的京东网关里。

## 文档（4）

| 文件 | 原路径 | 内容 |
| --- | --- | --- |
| [13_Zigbee协调器与京东设备接入记录.md](<doc/simuhome-ljb/_work/13_Zigbee协调器与京东设备接入记录.md>) | `_work/13_Zigbee协调器与京东设备接入记录.md` | 主记录：硬件、拓扑、两个坑（ember 而非 zstack、不能从 git 目录启动）、三台设备实测、MCP 改动、建议 |
| [z2m-README.md](<doc/simuhome-ljb/_work/z2m/README.md>) | `_work/z2m/README.md` | Z2M 的运行方式、启动命令、踩坑与运维脚本清单 |
| [config.md](<doc/simuhome-ljb/_work/mcp/config.md>) | `_work/mcp/config.md` | MCP 配置说明：新增的 zigbee 认领规则与实测结果 |
| [README.md](<doc/simuhome-ljb/_work/README.md>) | `_work/README.md` | `_work` 目录索引（含 13 号文档与 z2m 子目录） |

## 脚本（29，全部位于 _work/z2m 与 _work/logs）

| 分组 | 文件 | 用途 |
| --- | --- | --- |
| 配网 | `permit_join.py`、`watch_join.py` | 开 254 秒入网窗口；订阅 bridge/event 看设备入网/离网 |
| 设备档案 | `z2m_inspect.py`、`clusters.py`、`list_switch_entities.py` | 看设备型号/能力/入网状态、端点与簇、HA 注册表里的实体 |
| 读数据 | `read_state.py`、`watch_switch.py`、`watch_occupied.py`、`health.py`、`watch_switch_count.py` | 读设备主题、监听按键报文、盯 occupied 变化、看报文计数 |
| 改名字 | `rename_device.py`、`rename_pir.py`、`rename_pir_entities.py`、`rename_switch.py`、`rename_occupied.py`、`assign_pir_area.py` | 改 Z2M friendly_name、改 HA entity_id、挂房间 |
| 补 interview | `reinterview.py`、`retry_interview.py`、`longtimeout_interview.py`、`debug_interview.py`、`force_remove.py` | 重试 interview、放宽超时、开 debug、强制移除重来 |
| 绑定排查 | `bind_ias.py`、`bind_ias_retry.py`、`bind_switch_scenes.py`、`touchlink.py` | 尝试给 IAS/场景簇做绑定、Touchlink 强制复位 |
| 诊断 | `set_debug.py`、`watch_pir.py` | 调日志级别；确认 PIR 有没有上行报文 |
| 反面教材 | `logs/znp_probe.py` | 最初按 TI ZNP 协议探测这块 Silicon Labs 板子，一个字都收不到——ember 才是对的 |

## 配置（1）

| 文件 | 内容 |
| --- | --- |
| [config.yaml](<doc/simuhome-ljb/_work/mcp/config.yaml>) | MCP 配置：zigbee 认领规则（platforms=mqtt、unique_id_prefix="0x"、domains=sensor） |

## 现场数字

```text
协调器   ZB-GW04 V1.2（EFR32，EmberZNet 7.4.5），COM7，信道 11
设备     th01 0xa4c138f72c66960c   可用，23~24 °C / 32~39 %
         prz01 0x00158d000128396d  入网，interview 失败，零上报
         wsz01 0x00158d000126f39e  入网且定义命中，按键零上报
HA       sensor.th01_temperature / _humidity / _battery / _voltage
MCP      observe_home → wo_shi / 卧室 env{temperature, humidity}
```

## 未入库说明

Z2M 的 `node_modules`、`data/database.db`、`data/log` 与 HA 的 `prz01.yaml`
不随本文档归档：前三个是运行时依赖与运行日志，最后一个是 HA 容器里的配置，
内容已在 13 号文档里原文摘录。
