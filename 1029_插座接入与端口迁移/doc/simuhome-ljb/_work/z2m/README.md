# _work\z2m

Zigbee2MQTT 的本机运行目录。协调器是 **ZB-GW04 V1.2**（Silicon Labs EFR32，EmberZNet 7.4.5），
通过 CH340 串口桥接在 **COM7** 上。

## 为什么不用 Docker 镜像

Docker Desktop 拿不到 Windows 的 USB 串口；而 Docker Hub 在这台机器上不可达
（`docker pull koenkk/zigbee2mqtt` 直接超时），所以改用 Node 原生跑，
直接吃 COM7，链路反而更短：

```text
ZB-GW04 ──USB(CH340)──> COM7 ──> Z2M(Node) ──MQTT──> amqtt:2883 ──> HA 的 MQTT 集成

端口为什么是 2883：Windows 的 Hyper-V/WSL 会把一段端口划成保留区，
2026-10-29 开机后 1883 落在 "1815-1914" 里，绑不上（WinError 10013）。
broker 用 MQTT_PORT 环境变量改端口，Z2M / HA 配置里同步改了。
```

## 怎么启动

```powershell
cd D:\项目            # 必须是 git 仓库之外！见下面"踩过的坑"
$env:ZIGBEE2MQTT_DATA='D:\项目\simuhome-ljb\_work\z2m\data'
node 'D:\项目\simuhome-ljb\_work\z2m\node_modules\zigbee2mqtt\index.js'
```

前端：<http://127.0.0.1:8082>

## 踩过的坑

```text
① 不要从 _work\z2m 里启动
   Z2M 用 git rev-parse --short=8 HEAD 算源码哈希，_work 在 simuhome-ljb 这个 git 仓库里，
   算出来的是仓库的 HEAD，和包里 dist\.hash 不一致 → 它以为源码变了 →
   跑 pnpm run prepack 重新编译 → 失败退出。
   从任何非 git 目录（比如 D:\项目）启动，git 命令报错、哈希记为 unknown，就跳过编译。

② 适配器要写 ember，不是 zstack
   ZB-GW04 是 Silicon Labs 方案（EZSP/ASH），TI 的 ZNP 帧它一概不理。
   用错的协议去问，表现就是"串口能开、一个字都不回"。

③ amqtt 的 retained 已知问题
   _work\broker 的 amqtt 在 retained 投递上有过问题（见 _work\broker\probe_filter.py），
   Z2M 的 discovery 依赖 retained；目前实测正常，若发现实体不刷新，先怀疑这里。
```

## 目录内容

```text
data\configuration.yaml   Z2M 配置：mqtt 127.0.0.1:2883 / serial COM7 / adapter ember /
                          前端 8082 / homeassistant discovery 开启
data\database.db          Z2M 自己的设备库（入网设备、网络参数都记在这里）
data\coordinator_backup.json  协调器备份（EmberZNet 支持，换棒时不用重新配对）
permit_join.py            打开入网窗口 254 秒，并读回 bridge 的响应
watch_join.py             订阅 bridge/event，有设备入网/离网就打印（调试用）
inspect.py                打印当前所有设备的型号、厂商、能力、入网状态
read_state.py             读某台设备在 MQTT 上的最新状态
rename_device.py          改 Z2M 里的 friendly_name
```

## 脚本的端口约定

```text
目录下的 .py 全部读环境变量 MQTT_PORT（默认 1883）：
  $env:MQTT_PORT='2883'; python _work\z2m\permit_join.py
不设就按 1883，与 broker 的默认值一致。
```

## 另一类坑：Docker Desktop 起不来

```text
现象   docker info 报 "Docker Desktop is unable to start"，HA 自然也不在
排查   WSL 正常：wsl -d docker-desktop -e echo ok → ok；hns / vmcompute 都在跑
根因   %LOCALAPPDATA%\Docker 下残留 backend.lock / frontend.lock / launcher.lock
修法   杀掉 Docker 进程 → 删这三个锁文件 → 重启 Docker Desktop
```

## 当前接进来的设备

```text
th01   Zbeacon TH01 温湿度计   ieee 0xa4c138f72c66960c   EndDevice
       HA 实体：sensor.th01_temperature / humidity / battery / voltage
       房间：wo_shi（卧室，HA 里的 area 是小米集成建的，名字就叫"卧室"）
       MCP：被 zigbee 认领规则收下，作为该房间的环境量出现在 observe_home

spz01  BEESMART 智能插座        ieee 0x00158d000129e0c4   Router
       model 00090bdc，定义命中 J.XUAN SPZ01 / plug
       HA 实体：switch.spz01、switch.spz01_power_outage_memory、sensor.spz01_power
       控制：HA 的 turn_on/turn_off 与 MQTT 的 zigbee2mqtt/spz01/set 都实测通过
       MCP：devices 列表里出现，inspect_device 给出 turn_on / turn_off / toggle

prz01  Beesmart 人体感应        ieee 0x00158d000128396d   EndDevice
       interview 失败、零上报，只有 HA 里的自动生成实体，不可用
wsz01  J.XUAN 无线开关          ieee 0x00158d000126f39e   EndDevice
       定义命中但按键零上报、拒绝绑定，不可用
```

## 对应文件

```text
_work\z2m\data\configuration.yaml      Z2M 配置本体
_work\mcp\config.yaml                  MCP 的 zigbee 认领规则（unique_id_prefix: "0x"）
_work\mcp\config.md                    那条规则与实测结果的说明
_work\broker\run_broker.py             Z2M 连的那个 MQTT broker
```

## PRZ01 人体感应：把"只报有人"包成"会回落"

这台 PRZ01 走 IAS Zone，触发时只把 `alarm_1` 置 on，之后不会主动报 off，
直接拿它当"有没有人"会永远是 on。处理方式是**不改设备、不写自动化**，
在 HA 里加一个模板传感器：

```text
文件      D:\homeassistant-sandbox\packages\prz01.yaml
挂载方式  configuration.yaml 里加了 homeassistant.packages: !include_dir_named packages
实体      binary_sensor.prz01_occupied（device_class: occupancy）
判据      alarm_1 为 on，且距离它最后一次上报不超过 120 秒
为什么用 last_updated 而不是 last_changed
          设备重复上报同一个 on 时，HA 的 last_changed 不变、last_updated 会推进；
          用后者，连续走动才能持续续期
刷新节奏  模板里用了 now()，HA 每分钟重算一次，所以实际回落是"超过 120 秒后的下一个整分钟"
```

实测记录（2026-10-27）：

```text
13:42:27  挥手 → alarm_1 on、occupied on
13:45:00  occupied 自动 off（2 分 33 秒后），alarm_1 仍为 on
```

注意两点：

```text
① HA 重启后 alarm_1 会变 unknown（Z2M 的自动生成定义不发 retained 状态），
   occupied 因此是 off，直到设备下一次上报——这是预期行为，不是坏掉
② 摘掉这套只需要删 packages\prz01.yaml 并重启，configuration.yaml 里的
   packages 一行留着不影响其他实体
```
