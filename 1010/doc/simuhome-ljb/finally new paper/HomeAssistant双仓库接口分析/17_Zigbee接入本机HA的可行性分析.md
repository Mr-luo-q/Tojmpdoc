# 17 Zigbee 接入本机 HA 的可行性分析（本机实测）

核对日期 2026-09-28。本文回答一个问题：
Zigbee 设备能不能接进这台 Windows 机器上的 HA 容器，代价是什么。

## 0. 结论

```text
能接，但当前机器上"USB 棒直接插主机 → 容器"这条路走不通，而且现在还没有任何协调器硬件。

可行路线（按省心程度排序）：
① 厂商网关走局域网      米家多模网关2 / Aqara Hub E1 → XiaomiGateway3(HACS)   最省事；只覆盖米家/Aqara 子设备
② 网络协调器            SLZB-06 类 → ZHA 的 socket:// 或 Z2M 的 tcp://       最标准；任意 Zigbee 设备
③ USB 棒 + Windows 侧 Z2M   Sonoff ZBDongle + Z2M 官方 Windows 安装           最便宜；不碰 Docker
④ USB 棒 + usbipd 进 Docker  Docker 官方 USB/IP 用法 + 特权 helper 容器       能跑；链路最长
⑤ USB 棒 + usbipd 进 WSL2   在 Ubuntu 里跑 Z2M / ser2net                     绕开 Docker，但多一层 WSL
✗ 棒直接插主机让 HA 容器看见                                                   Docker Desktop 默认不做 USB 直通
```

## 1. 本机实测事实（2026-09-28）

```text
Docker Desktop      引擎 29.5.3，Linux 容器，WSL2 后端，overlayfs
HA 容器             homeassistant（ghcr.io/home-assistant/home-assistant:stable，HA 2026.6.4）
                    网络 homeassistant_default(bridge)，端口 8123
                    HostConfig.Devices = null（零设备映射）
                    容器内 /dev 没有 tty*、没有 serial、没有 bus/usb
主机网络            只有 WLAN（Intel AX211）在线，没有有线网口在线
WSL                 docker-desktop（运行中）+ Ubuntu（已存在、停止）
usbipd              未安装
USB 串口/Zigbee 棒   无；系统里只有蓝牙虚拟串口 COM3 / COM4
HA 集成             mqtt 已启用（broker 是 Windows 上的 mosquitto.exe，:1883）；zha 未启用
```

一句话：Zigbee 的"最后一公里"是协调器；本机现在既没有协调器，也没有
从宿主到容器的 USB 通道。

## 2. 为什么"直插"不行

```text
Zigbee 设备说 802.15.4，不说 IP；HA 必须通过协调器（USB 棒或网络协调器）接进来
HA Container 的官方做法是 docker run --device /dev/ttyUSB0，把宿主串口映射进容器
Docker Desktop 的 Linux 虚拟机默认看不到 Windows 上的 USB 设备
HA 论坛 703477 的原话："Docker Desktop does not allow USB passthrough"
本机实测：容器内没有 /dev/tty*、没有 /dev/serial
```

Docker 官方现在有 USB/IP 方案（见第 6 节），但它是在这个限制之上加一层
"USB 走网络"的桥，不属于直通。

## 3. 路线① 厂商网关（推荐先做）

```text
做法  多模网关连家里 WiFi/网线 → 米家 App 把 Zigbee / 蓝牙 Mesh 子设备配对进去
      → HA 装 HACS XiaomiGateway3 → 填网关 IP 与 token → 子设备以局域网实体出现
成本  米家多模网关2 约 160~220；Aqara Hub E1 约 130~180（单件略超 150）
优点  完全不碰 USB/WSL/容器映射；顺带把米家蓝牙 Mesh 接进来；走局域网本地控制
限制  只认米家/Aqara 生态的子设备，第三方 Zigbee 设备基本进不去；依赖 HACS 集成
MCP   网关子设备进 HA 后就是标准 switch/sensor/light/cover，走现有 claim/roles 配置
```

## 4. 路线② 网络协调器（最标准）

```text
做法 A（ZHA）  买 SLZB-06 类协调器（以太网/WiFi/USB 三模）
               HA → 添加集成 → Zigbee → 填 socket://IP:6638
做法 B（Z2M）  同一个协调器的 TCP 口，Z2M 容器配 port: tcp://IP:6638 → MQTT → HA
成本  约 200~280（超单件预算）
优点  标准 Zigbee、任意品牌设备；ZHA 是 HA 内置，不用另装服务
限制  本机只有 WiFi 在线；ZHA 官方明确不建议串口代理走 WiFi/WAN/VPN：
      "not recommended ... over Wi-Fi, WAN, or VPN"
      协调器最好接路由器网线（协调器自己有网口即可，不需要本机有线口）
```

## 5. 路线③ USB 棒 + Windows 侧 Z2M（最便宜的标准化路线）

```text
做法  买 USB 协调器（Sonoff ZBDongle-P/E 约 80~130）
      Windows 装虚拟串口驱动（CP210x 或 FTDI，看芯片）
      装 Node.js 22 LTS → corepack enable → 拉 zigbee2mqtt → pnpm install → pnpm start
      Z2M 连本机 mosquitto(localhost:1883)，HA 的 mqtt 集成已在跑
      → Zigbee 设备通过 MQTT discovery 自动出现在 HA 里
优点  不碰 Docker 设备映射；成本最低；Z2M 官方有 Windows 安装页，步骤明确
限制  Z2M 服务化要自己做（开机自启、崩溃重启）；USB 口别休眠；资料比 Linux 部署少
```

## 6. 路线④/⑤ USB 棒 + usbipd（Docker 官方 USB/IP 或 WSL）

Docker 官方 "Using USB/IP with Docker Desktop" 页面给出的做法：

```text
1 Windows 侧跑一个 USB/IP server（用 usbipd-win；官方示例用 jiegec/usbip）
2 起一个特权 helper 容器：--privileged --pid=host，nsenter -t 1 -m
3 容器里执行 usbip attach -r host.docker.internal -d <busid>
4 helper 容器必须一直运行；其他容器再用 --device /dev/ttyUSB0 使用这个设备
官方提醒："Docker can't guarantee every possible USB device works with this setup"
```

HA 论坛实测（703477 / 837382 / 435181）：

```text
- 有人把棒 attach 到 docker-desktop 发行版后直接成功
- 也有人只在 lsusb 里看到设备、没有 /dev/ttyUSB；换成独立 Ubuntu 发行版
  + 调整 Docker Desktop 的 WSL integration 设置后才成功
- 每次 Windows 重启都要重新 attach（论坛有人用批处理 + 启动文件夹解决）
```

变体 ⑤：把棒 attach 到 WSL2 Ubuntu（usbipd attach --wsl Ubuntu），
在 Ubuntu 里跑 Z2M，或者用 ser2net 转成 TCP 给 ZHA 的 `socket://`。
这条完全绕开容器设备映射，但多一层 WSL 要维护。

结论：能跑通，但环节多、回归性差，适合"手里已经有棒"的情况，
不作为首选方案。

## 7. ZHA 与 Z2M 怎么选

```text
ZHA   HA 内置，零额外服务；协调器要么 USB（受本机限制），要么 socket:// 网络协调器；
      官方不建议串口代理走 WiFi
Z2M   Node 服务 + MQTT；设备支持更新快，Windows 与容器两种部署都成熟；
      代价是多一个常驻服务要维护
```

两者进 HA 之后都变成标准实体，v2 MCP 的 claim / roles / actions
不需要改代码。差异只在"协调器怎么连上 HA"，不在 MCP 这一层。

## 8. 建议

```text
只想尽快让 Zigbee 设备进我们 HA        → 路线①，米家多模网关2（已有 xiaomi_home 经验，本地 LAN 控制）
想要标准 Zigbee、任意品牌设备           → 路线②，SLZB-06 + ZHA socket://
预算优先、能接受多维护一个服务          → 路线③，Sonoff USB 棒 + Z2M on Windows
已经有 USB 棒、愿意折腾                 → 路线④/⑤，usbipd
```

如果愿意换一台树莓派跑 HA OS，这些 USB/网关限制会大幅简化，
见 20 号文档《树莓派部署 HA 的方案与本项目用法》。

## 9. 买回来怎么验收（与 16 号文档同一套）

```text
1 HA → 设置 → 设备与服务：出现 zha 或 mqtt 的 Zigbee 设备
2 触发一次状态变化（按按钮/开插座），30 秒内 HA 状态更新
3 v2 MCP inspect_device 能找到它，六字段有值
4 可写设备 execute_action 一次，verified=true
```

## 10. 来源

```text
官方文档   HA ZHA（socket:// 支持与 WiFi 串口代理警告）
           HA Bluetooth / Xiaomi BLE（BLE 与 Mesh 的边界）
           Zigbee2MQTT：Windows 安装页、adapter settings（tcp://）、remote adapter（ser2net）
           Docker Desktop："Using USB/IP with Docker Desktop"（docs.docker.com/desktop/features/usbip/）
社区实测   HA 论坛主题 703477、837382、435181；usbipd-win issue #669
本机实测   docker version / info / inspect、容器 /dev、wsl -l -v、
           Get-PnpDevice、Get-NetAdapter、HA /api/config
```
