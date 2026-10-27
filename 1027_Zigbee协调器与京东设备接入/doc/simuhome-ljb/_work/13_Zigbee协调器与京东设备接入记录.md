# 13：Zigbee 协调器与京东设备接入记录

> 核对时间：2026-10-27
> 依据：本机实测（ZB-GW04 + Zigbee2MQTT 2.14.2 + HA 沙盒）、`_work\z2m` 下的脚本与日志、
> `zigbee2mqtt.io/devices/` 官方设备库、`zigbee-herdsman-converters` 的 dist 源码
> 结论分级：【已验证】有现场证据；【推断】由现象推得；【未验证】需要后续确认

## 1 结论先行

```text
TH01（Zbeacon 温湿度计）    【已验证】入网、interview、上报全通，HA 与 MCP 都能用
PRZ01（京东人体感应）        【已验证】能入网，但 interview 失败、绑定被拒、零上报
WSZ01（京东无线开关）        【已验证】入网且定义命中，但按了不发帧、绑定被拒
京东 GWZ01 网关（老）        【已验证】AM335x Linux，只开 telnet，默认口令全错，无本地接口
```

一句话：**协调器这条链路是通的，问题出在京东那套子设备的固件——它们不在标准通道上发数据。**

## 2 现场拓扑

```text
ZB-GW04 V1.2（Silicon Labs EFR32，EmberZNet 7.4.5）
  └─ CH340 ──> COM7 ──> Zigbee2MQTT 2.14.2（Node 24 原生跑在 Windows）
        └─ MQTT ──> amqtt 127.0.0.1:1883
              ├─> HA 的 MQTT 集成（容器内 host.docker.internal:1883）
              └─> MCP server（stdio，只在调用时起）

网络参数：信道 11，PAN/密钥/扩展 PAN 由 Z2M 首次启动生成
协调器 IEEE：0x6083dafffed10d91
设备：
  th01   0xa4c138f72c66960c   Zbeacon TH01            温湿度
  prz01  0x00158d000128396d   Beesmart（京东贴牌）    人体感应
  wsz01  0x00158d000126f39e   Beesmart（京东贴牌）    无线开关
```

## 3 两个必须知道的踩坑

### 3.1 适配器是 ember，不是 zstack

```text
现象   串口能打开，发什么都无回音
原因   ZB-GW04 是 Silicon Labs 方案（EZSP/ASH），我只按 TI 的 ZNP 帧去问
修法   配置里写 serial.adapter: ember
判定   官方工具一条命令就能确认：
       universal-silabs-flasher --device COM7 probe
       → Detected ApplicationType.EZSP, version '7.4.5.0 build 0'
```

### 3.2 Z2M 不能从 git 仓库目录里启动

```text
现象   "Building Zigbee2MQTT... (hash changed), failed"，随后 pnpm run prepack 失败
原因   Z2M 用 git rev-parse --short=8 HEAD 算源码哈希；
       _work 在 simuhome-ljb 这个仓库里，算出来的是仓库 HEAD，
       和包内 dist/\.hash 不一致 → 它以为源码变了，去重新编译
修法   从任何非 git 目录启动（例如 cd D:\项目），用 ZIGBEE2MQTT_DATA 指到 _work\z2m\data
```

顺带一条：包里的 `dist/` 是编译好的，不需要自己 build；Docker 镜像在本机拉不到
（registry-1.docker.io 不可达），所以走 Node 原生是唯一可行路径。

## 4 三台设备的实测

### 4.1 TH01：完全可用

```text
manufacturer  Zbeacon      model  TH01         definition 命中
exposes       battery / temperature / humidity / voltage / linkquality
HA 实体       sensor.th01_temperature / _humidity / _battery / _voltage
房间          wo_shi（卧室）
MCP           走 zigbee 认领规则，作为该房间的环境量出现在 observe_home
```

### 4.2 PRZ01：入网但不出数据

```text
manufacturer  Beesmart     model  读不到（interview 失败）
簇            input: genBasic / genIdentify / genPowerCfg / ssIasZone / 65024 / 65025 / 4111
失败的环节    active endpoints 请求连续超时（15s × 2）→ interview 判失败
              日志里还有 TC_REQUESTER_VERIFY_KEY_TIMEOUT（密钥交换没完成）
绑定          genScenes / ssIasZone 都试过，设备回 "Failed to bind"
上报          零。Z2M 退化成自动生成定义，靠猜簇建了 alarm_1 等实体
HA 里现状    binary_sensor.prz01_alarm_1 停在入网那一下，此后不再变化
```

曾经给它在 HA 里补过一个"会回落"的模板（`prz01_occupied`，120 秒窗口），
但因为底层不上报，这个模板实际上没有输入源，保留只是为了以后换设备时复用写法。

### 4.3 WSZ01：定义命中了，但设备不说话

```text
manufacturer  Beesmart     model  JD-SWITCH\x0202（Z2M 匹配到 J.XUAN WSZ01 定义）
簇            input: genBasic / genIdentify / closuresDoorLock / 65024 / 65025
              output: genGroups / genIdentify / genScenes / closuresDoorLock / 65024 / 65025 / 65535
转换器实现    zigbee-herdsman-converters/dist/devices/jxuan.js
              WSZ01 的 action 来自 簇 65029（0xFE05）的 attributeReport
关键矛盾      设备自报的 input 簇里没有 65029，只有 65024/65025
实测          连按三次，debug 日志里关于这台设备 0 行；绑定 genScenes 十次全部失败
```

### 4.4 共同的判断

```text
TH01（Zbeacon）  正常
两台 Beesmart    都是"入网即静默"：能拿网络密钥、能 announce、能应答部分请求，
                 但不向标准通道上报，且拒绝建立绑定
结论【推断】     京东这批贴牌设备的固件把上报路径锁在京东网关那套实现里，
                 型号字符串能被 Z2M 认出来，但数据通道对不上
```

## 5 MCP 侧的改动

```text
_work\mcp\config.yaml 新增 zigbee 认领规则
  platforms: [mqtt]
  unique_id_prefix: "0x"        Z2M 的 unique_id 形如 0xa4c138..._temperature_zigbee2mqtt
  domains: [sensor]
  id_source: device_name

效果：TH01 被认领，但它是纯传感器（没有可控实体），按 mapping 的规则归入
      "房间环境量"而不是 devices 列表 —— observe_home 里表现为
      wo_shi / 卧室  env{temperature, humidity}，inspect_device 查不到它（预期）
```

HA 侧的模板实体：

```text
文件    D:\homeassistant-sandbox\packages\prz01.yaml
挂载    configuration.yaml 里加 homeassistant.packages: !include_dir_named packages
实体    binary_sensor.prz01_occupied（occupancy，120 秒窗口，用 last_updated 续期）
状态    设计可用，但 PRZ01 不上报，实际没有意义
```

## 6 建议

```text
保留    TH01（可用）+ ZB-GW04 + Z2M 这套骨架
搁置    PRZ01 / WSZ01：不值得继续逆向，固件不在标准通道上发数据
替换    要开关/人体，买标准 Zigbee 3.0 的（Aqara、小米、涂鸦 TS0xxx），
        Z2M 原生支持，不需要绑定也不需要写转换器
可复用  _work\z2m 下的脚本（发窗口、看事件、改名字、读簇、抓报文）通用，
        换任何 Zigbee 设备都用得上
```

## 7 对应文件

```text
_work\z2m\README.md                  Z2M 的运行方式、启动命令、全部踩坑
_work\z2m\*.py                       这次写的运维脚本（发窗口/看事件/改名/读簇/抓报文）
_work\mcp\config.yaml                 MCP 的 zigbee 认领规则
_work\mcp\config.md                  那条规则与实测结果
_work\logs\znp_probe.py              最初按 ZNP 探测的脚本（留作反面教材）
D:\homeassistant-sandbox\packages\prz01.yaml   HA 的 occupied 模板
```
