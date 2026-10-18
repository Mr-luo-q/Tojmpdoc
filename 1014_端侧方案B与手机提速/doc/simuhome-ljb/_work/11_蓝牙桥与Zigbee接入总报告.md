# 11：蓝牙桥 + Zigbee 接入总报告（能不能用）

> 核对时间：2026-10-14
> 依据：本机实测（Docker 状态、HA 注册表、PnP 设备、BLE 扫描、Theengs 安装实测）、
>      `D:\项目\树莓派\` 下的部署记录、仓库文档 16/17/18/20 号、
>      上游官方文档今天抓取（HA 文档版本 2026.10.1、ESPHome、Theengs、PyPI、GitHub API）
> 事实分级：【已核对】有今天或仓库里可复现的证据；【推断】由现象推得；【待确认】需要设备侧或你确认

## 1 一句话结论

```text
问题一  让这台 HA 自己做蓝牙桥，把那几个蓝牙设备接进来
        能，但"这台 HA"必须是跑在有蓝牙硬件的那台机器上。
        现在的 HA 跑在 Windows 的 Docker Desktop 里，Linux VM 拿不到 Windows 蓝牙，
        这条路从架构上就是断的，加多少配置都补不回来。
        手里现成能承担这个角色的是树莓派（HA Container 已在跑，已挂 /run/dbus + privileged）。

问题二  Zigbee 那几台设备
        现在不能接。Zigbee 设备说的是 802.15.4，不带 IP，
        它必须站在一个"协调器/网关"的无线电范围内，而 HA 还要够得到那个协调器。
        协调器在家里、HA 在学校，中间隔着两张不互通的网 —— 这一步没有软方案可绕。
        唯一例外是走云：设备挂涂鸦网关 → 官方 tuya 集成扫码导入（见第 5 节，2026-10-14 按说明书更正）。

问题三  "能不能用"的判据
        不看桥软件写得好不好，看两件事：家侧有没有一个带无线电的常驻节点；
        两台机器之间有没有一条能双向通的 IP 通道。这两条不满足，任何桥都跑不起来。
```

## 2 根因：三条路卡的是同一处

```text
                 家里（pearcat）                        学校（tjuwlan）
   +------------------------------+            +------------------------------+
   |  蓝牙温湿度计 / 氛围灯 / ...  |            |  Windows 笔记本               |
   |  Zigbee 设备 x4              |            |   +- Docker Desktop          |
   |        ^v 无线电（十几米）    |   ？       |        +- Linux VM（无蓝牙）  |
   |  需要一个"收音机"             | <--------> |             +- HA 容器        |
   |  （树莓派 / ESP32 / 网关）    |  两张网    |                              |
   +------------------------------+  不互通    +------------------------------+

三条独立的物理约束，叠在一起：
  约束 1  蓝牙/Zigbee 是短距无线电，穿不了城市，必须有个节点待在设备旁边
  约束 2  Docker Desktop 的 Linux VM 没有设备直通，容器里看不到宿主蓝牙、也看不到 USB 串口
  约束 3  Zigbee 的协调器必须在场，且 HA 官方明确不建议把协调器串口代理走在 Wi-Fi / WAN / VPN 上
```

今天的实测把这三条又钉了一遍：

```text
【已核对】本机 WLAN = tjuwlan（校园网），信号 88%；设备在家用的 pearcat
【已核对】Docker Desktop 引擎没在跑（docker ps 报 npipe 找不到），沙盒 HA 现在离线
【已核对】设备管理器里只有 4 个蓝牙虚拟串口 COM3~COM6，没有 CH340 / CP210x / FTDI，即没有任何 Zigbee 棒
【已核对】树莓派现在够不到：ping raspberrypi、ping 192.168.43.33、ping 192.168.137.2 全部超时
【已核对】本机没装 Tailscale（服务不存在，也没有安装目录）
【已核对】本机 BLE 扫描工具链正常：扫 12 秒收到一批广播，其中一台在广播小米 MiBeacon 的服务 UUID
        0000fe95，说明被动读广播这条路是通的；但"疑似温湿度计 0 台" —— 设备在家，本来就扫不到
```

结论落到修改层级：**要动的是部署拓扑（谁待在设备旁边），不是桥软件的参数。**

## 3 我核到的设备清单（今天，从 HA 注册表直接读）

沙盒 HA 的 `.storage\core.device_registry` 里，非 SimuHome 的"真设备"一共 3 台：

| 设备 | 集成 / 通道 | 型号字段 | 协议 | 状态 |
| --- | --- | --- | --- | --- |
| 米家对开门冰箱 | `xiaomi_home`（云） | `midjd6.fridge.6101` | Wi-Fi | 已接入，实体正常 |
| 蓝牙音箱 | `mqtt`，本地桥 `bt_speaker` | ERAZER SAB6 | 蓝牙经典（A2DP） | 桥进程没跑时 unavailable |
| 温湿度计 | `midea_auto_cloud`（条目已停用） | Midea `MHS-AC-02` | 蓝牙 / 需网关 | 接不进来，卡在数据源 |

再加上一直没接进来的第 4 台：**氛围灯 `hzsj-light-wyra02_mibtF3E6`**（第三方接米家，Wi-Fi，无本地接口，见 `06_氛围灯接入.md`）。
这 4 台就是仓库里出现过的全部真设备。

### 3.1 今天由你提供的说明书确认的：涂鸦 Zigbee 温湿度传感器

```text
来源      你贴的产品说明书（涂鸦系白牌，经销商"黄石惠乐网络科技有限公司"）
协议      Zigbee 3.0
供电      2 节 7 号电池（LR03/AAA），工作电压直流 3V
量程      -10~55℃，0~99%RH
配网      装电池后长按配置键 5~10 秒，指示灯闪烁 → 在"涂鸦 / 智能生活"App 里配
说明书原话 "此款式需要涂鸦 zigbee 网关协作使用"

这一条把 Zigbee 侧的路线整个改掉了：它不是米家/Aqara 设备，
所以 XiaomiGateway3 和官方 xiaomi_home 两条路对它无效（详见第 5 节）。

【待确认】一共几台、是否都是这一款、机身上有没有印型号（涂鸦这类常见型号是 TS0201）
```

```text
【待确认】还缺两件事
  1  这 4 台涂鸦传感器是不是同一款（配好网后在 HA 里看 manufacturer / model 最准，不用拆机）
  2  "那几个蓝牙设备"到底是哪几台 —— 涂鸦这 4 台是 Zigbee，不在蓝牙那条线上；
     蓝牙侧现在在册的候选只有美的温湿度计，而它已经判定没有现成译码
```

## 4 蓝牙侧：四条路，逐条给结论

### 4.1 A 路：把 HA 放到树莓派上，HA 自己就是蓝牙桥（推荐）

```text
原理    HA 的 bluetooth 集成在 Linux 上通过 BlueZ + D-Bus 用本机适配器。
        树莓派 4B 板载 CYW43455 在官方文档里列为 known working 适配器，
        所以 HA 跑在树莓派上时，"HA 自己做蓝牙桥"这句话就成立了，不需要第三方程序。
成本    0（硬件已有）
现状    【已核对 2026-10-14，SSH 上树莓派实测】这个角色它已经担起来了，不用新建任何东西：
        bluetooth 集成 state=loaded，条目标题就是板载适配器
        （Raspberry Pi Trading Ltd bcm43438-bt / DC:A6:32:F1:4E:CA）；
        适配器以 hci0 进了 HA 的设备注册表；
        bluetoothctl show 显示 Discovering: yes —— 扫描正在跑（不是我起的，是 HA）；
        另跑一次 15 秒扫描听到周围 85 台 BLE 设备，说明无线电本身好用。
        容器参数：--privileged + --network=host + /run/dbus:ro；主机 BlueZ 5.82。
待做    只剩"设备在射程内"这一条：设备在家，树莓派在宿舍，扫得到邻居、扫不到自己家。

岔路    树莓派这台 HA 与 MCP 现在用的沙盒 HA（Windows 上那台）不是同一个实例。
        蓝牙设备进的是树莓派这台；要让 MCP 看见它们，得把 MCP 的 base_url 与令牌切到树莓派
        （20 号文档的方案 A），或者让树莓派把数据经 MQTT 转回沙盒那台。
        这件事定下来之前，蓝牙设备只会出现在树莓派的界面上。
限制    板载适配器走 UART 总线，官方注明"连接数多时性能有限"；
        想更稳就插个 USB 蓝牙适配器（官方 high performance 列表里是 CSR8510A10 那一类），
        并且只用 USB 2.0 口或加一条延长线，避开 USB 3.0 的 2.4G 干扰
```

树莓派上的核查与启用命令（等它上线后照跑）：

```bash
# 1 适配器与 BlueZ 是否就绪
bluetoothctl show              # 期望看到 Controller 与 Powered: yes
systemctl status bluetooth --no-pager
bluetoothctl power on

# 2 bluez 不在就装（Raspberry Pi OS 一般自带 pi-bluetooth/bluez）
sudo apt-get install -y bluez

# 3 容器参数已经够（--privileged 覆盖 NET_ADMIN/NET_RAW，/run/dbus 已挂）
#   只需在 HA 界面：设置 → 设备与服务 → 添加集成 → Bluetooth
```

### 4.2 B 路：ESP32 + ESPHome 蓝牙代理（官方支持，20~40 元）

```text
适合    HA 留在 Windows 沙盒（或树莓派）但蓝牙覆盖不够时，往家里补一个"收音机"
官方能力（今天抓自 HA Bluetooth 文档）
        ESPHome ESP32：听广播 能 / 广播打包 能 / 单条主动连接 能（固件 >= 2022.9.3）
                       / 多条主动连接 能（固件 >= 2022.11.0）
        Shelly Gen2+、SMLIGHT SLZB-U：只能听广播，不能主动连接
成本    20~40 元一块板子，一块覆盖一片区域，不需要每台设备配一个
代价    需要家侧有 WiFi/网线给它，且 HA 要能主动连上它的 IP
        （跨网时靠 Tailscale 子网路由之类打通，见第 6 节）
```

### 4.3 C 路：家侧小主机跑 Theengs Gateway（BLE 转 MQTT，只读）

这条路是"HA 不在家"时的标准做法，但今天在本机实测**装不上**：

```text
【已核对】PyPI 上 TheengsGateway 1.8.0，依赖 theengsdecoder>=2.5.0
【已核对】theengsdecoder 2.5.0 只发布了源码包（sdist），没有任何 wheel
【已核对】本机 pip 尝试现场编译，CMake 构建失败：
          ERROR: Failed building wheel for theengsdecoder
          也就是说这台 Windows 上要装，得先装 MSVC C++ 生成工具
【已核对】即使装成功也读不到美的：Theengs 官方设备清单里 LYWSD* / CGDK* 都有，
          搜 "Midea" 命中 0 条
```

它是"只读"通道（只解广播，不写 GATT），进 HA 后是 MQTT sensor，只能给观察 / 判目标用。
在 Linux（比如那台树莓派）上装要容易些，但仍要先 `apt install cmake g++` 让它编译。

### 4.4 D 路：自己写 bleak 桥（`bt_speaker\bridge.py` 同款）

```text
先例    _work\bt_speaker\bridge.py：本机 Windows 侧读蓝牙 → MQTT discovery → HA
适用    只对"协议已知"的个别设备合算
不合算  美的这台温湿度计：官方和社区都没有它的译码。
        【已核对】GitHub 搜 "midea ble home assistant" 只有两个 0 star 的美的 BLE 风扇集成，
        没有温湿度计的；"midea bluetooth thermometer" 搜不到任何仓库。
        走这条路等于自己逆向一个私有协议，成本比"换个传感器"高一个量级。
```

所以美的这台温湿度计的现实结论：**别把蓝牙桥当成它的主线**。
要么按美居 App 的提示加一个美的网关（让设备上云，`midea_auto_cloud` 条目一启用就能读），
要么直接换一台 HA 自带译码的 BLE 温湿度计（米家蓝牙温湿度计2 / 青萍 CGDK2 这类，
广播里是标准或已知格式，任何蓝牙扫描器都能读，不需要懂协议）。

### 4.5 美的温湿度计的实测（2026-10-13，树莓派旁边 2 米内）

```text
实测方法  树莓派上跑 watch.py，180 秒；期间用户把设备唤醒（进蓝牙配对状态）
抓到的身份
  地址    50:5E:3A:E9:93:2C      rssi 全程 -38（贴得很近）
  名字    name = 'midea'
  服务    0000fd25-0000-1000-8000-00805f9b34fb（厂商自定义 16 位 UUID）
  厂商数据 company id = 0x06a8

载荷只有两种，而且字节不变（180 秒共 936 包，去重后只剩这 2 条）
  887 次  02 cc 80 49 2c 93 e9 3a 5e 50 00 00 01   ← 后 6 字节是它自己 MAC 的反序
   49 次  02 34 30 32 4d 30 30 30 31 35 34 39 30 30 34  ← ASCII 即 "402M0001549004"
                                                          与云上记录的 sn8 = 402M0001 对得上

结论（已核对）
  广播里只带"我是谁"，不带温湿度读数；没有 0x181a 环境感知服务，也没有随时间变化的字节。
  所以"被动读广播就能拿到温湿度"这条路，对这台设备不成立。

主动连接的实测（同一天，工具 `_work\ble\midea_probe.py`）

```text
连得上，而且不用配对、不用密钥，直接就能读
身份（Device Information 服务读出来的，不是猜的）
  厂商名    2a29 = "midea"
  型号      2a24 = "MHS-AC-02"          ← 与 HA 设备注册表里的 model 字段一致
  硬件版本  2a27 = "ST249CA1"
  固件版本  2a28 = "V1.0.9"
  设备名    2a00 = "midea"

GATT 表（6 个服务）
  00001800 GAP          2a00 / 2a01 / 2a04 都是 read
  00001801 GATT         2a05 indicate
  0000180a Device Info  2a29 / 2a24 / 2a27 / 2a28 都是 read（就是上面那几行）
  0000ff80 厂商自定义   ff81 read,write     ff82 read,indicate
  0000ff90 厂商自定义   ff91 read,write     ff92 read,indicate
  0000ffc0 厂商自定义   ffc1 read,write     ffc2 read,indicate

直接读的结果
  三个厂商服务的 6 个特征读出来全是 0x00（64 字节零），说明数据不是摆在可读字段里的，
  而是要走它自己的协议：往 ff81/ff91/ffc1 写命令，从 ff82/ff92/ffc2 收通知。
  没有 0x181a 环境感知服务，也没有任何标准温湿度特征。
```

所以这台设备的准确画像是：

```text
广播      只报身份（MAC + 序列号），不带读数
连接      能连、能读身份，不需要配对密钥
数据      走厂商私有 GATT（写命令 + 收通知），没有现成的公开格式
含义      "标准集成 + 蓝牙代理"这条现成路对它无效；
          要接必须自己实现它的私有协议 —— 等于逆向，或者抓 App 的蓝牙包反推
```

订阅通知的实测（同一天，工具 `_work\ble\midea_listen.py`）

```text
订阅结果   4 个可通知特征全部订阅成功：2a05、ff82、ff92、ffc2
听的结果   90 秒内一条通知都没收到；
           订阅之后每 15 秒重读一次，6 个厂商特征连续四轮全部 BleakError（连接已经断了）
判断       设备只肯让我们"连上、看身份、订阅"，随后就断开；
           它期待的是自家 App 的那套握手，我们不按它的规矩说话，它就不给数据
```

公开资料检索（同一天）

```text
GitHub 搜 MHS-AC-02        → 0 个仓库
GitHub 搜 ST249CA1         → 0 个仓库
GitHub 搜 midea bluetooth ff80 → 0 个仓库
结论：没有任何已公开的协议实现可以借用
```

### 4.6 对这台设备的最终判定

```text
能把数据取出来的唯一剩余路径：逆向它的私有协议
  做法   抓手机 App 的蓝牙链路日志（安卓 HCI snoop log，或用 nRF Sniffer 之类硬件嗅探），
         拿到"握手 + 读命令 + 应答格式"，再自己写一个带重连的状态机桥
  成本   数天量级的工作，而且设备固件一改就可能失效

相比之下两条便宜的出路
  ① 美的网关    按 App 的提示加一个网关，让设备上云，`midea_auto_cloud` 条目一启用就能读
  ② 换设备     米家蓝牙温湿度计2 / 青萍 CGDK2 这类 HA 自带译码的 BLE 传感器，
                几十元，树莓派的蓝牙已经就绪，零开发，当天就能进 HA

建议：除非"把这台设备做出来"本身是研究目标，否则不要走逆向。
```

一个现场发现的干扰：树莓派上 HA 的蓝牙集成一直在扫（Discovering: yes），
手动用 bleak 连的时候会撞 `BleakDBusError`（D-Bus 里已有扫描在跑），所以脚本要带重试。
```

## 5 Zigbee 侧：这 4 台是涂鸦的，路线收敛成两条

```text
说明书那句话的准确含义：
  "需要涂鸦 zigbee 网关"——只对"用涂鸦 App"那条路成立。
  涂鸦的 Zigbee 传感器本身是标准 Zigbee 3.0 设备，用我们自己的协调器能直接配对，
  涂鸦网关不是必需品。代价是它不会再出现在涂鸦 App 里，数据也不再上涂鸦云。
```

于是原来的四条路收敛成两条，米家那两条直接作废：

```text
路线                                前提                        成本       能不能用
A 自建协调器 + ZHA（或 Z2M）         棒插在家里那台跑 HA 的机器上  80~200 元  能，推荐：本地、无云
  棒：ZBDongle-E / CC2652 / ZBT-2 / SLZB-06
B 涂鸦 Zigbee 网关 + 官方 tuya 集成   网关在家，HA 在哪儿都行       40~70 元   能，但走云、要网关

作废的两条（说明书确认是涂鸦设备之后）
  米家多模网关 + XiaomiGateway3   只认米家/Aqara 子设备，涂鸦设备配不进去
  米家多模网关 + 官方 xiaomi_home  只在米家云里找设备，看不见涂鸦云的东西
```

两条路各自的关键事实（2026-10-14 核到）：

```text
A 路  【已核对】ZHA 的官方 quirk 库里有一份专门给 TS0201 的补丁
             zha-device-handlers\zhaquirks\tuya\ts0201.py
             覆盖 _TZ3000_qaaysllp 与 _TZ3000_lfa05ajd 两个厂商号
      【已核对】Zigbee2MQTT 有 TS0201 的设备页：温度、湿度、电量、电池电压，
             另带温度/湿度偏移校准参数
      【已知的坑】涂鸦同型号常有多个厂商号变体。配对后在 HA 里看它的
             manufacturer / model 就知道命中没有；没命中时 Z2M 有
             "Support new Tuya devices" 流程补转换器
B 路  【已核对】官方 tuya 集成现在的流程是"手机 App 扫码登录"：
             先在涂鸦/智能生活 App 里加好设备，HA 这边扫码授权
             （页面里仍提到 iot.tuya.com 的 API 与条款，账号细节【待确认】）
      【推断】传感器经网关进涂鸦云后，会作为子设备出现在 HA 里，只读 current
      代价：多一个网关、全套走云、断网就不更新
```

关键引用（今天抓的官方 ZHA 文档原文口径）：协调器通过 Serial-Proxy-Server（串口转 IP）走
Wi-Fi、WAN 或 VPN 是 **not recommended** —— 串口协议扛不住丢包和延迟。
这条直接否掉了"把 Zigbee 棒插在笔记本电脑上、让家里的设备通过校园网连它"的设想。
**A 路因此绑一个前提：跑 HA 的那台机器（树莓派）必须待在家里。**

A 路在这台树莓派上的操作（棒到了照抄）：

```text
1  把棒插进树莓派的 USB 2.0 口，或加一条带屏蔽的延长线（避开 USB 3.0 的 2.4G 干扰）
2  sudo apt-get purge -y modemmanager        # 官方点名的坑：它会抢走 USB 串口，ZHA 起不来
3  ls /dev/serial/by-id/                      # 记下棒的稳定路径，别用会变的 /dev/ttyUSB0
4  HA → 设置 → 设备与服务 → 添加集成 → Zigbee Home Automation → 选那条 by-id 路径
5  逐台传感器：按住配置键 5~10 秒松手，等它入网；
   HA 里应出现 temperature / humidity / battery 三个实体
6  验收：静置 10~30 分钟后再读（说明书明确写了初次上电读数不准），
   MCP inspect_device 能读到 current
```

B 路今天的操作（不想买协调器、只想先看到数据）：

```text
1  买一个涂鸦 Zigbee 网关（沿用说明书那条路）
2  涂鸦/智能生活 App 里配对好 4 台传感器
3  HA → 添加集成 → Tuya → 用手机 App 扫 HA 给出的二维码授权
4  之后在 App 里加设备，要回 HA 里 Reload 一次 tuya 集成才会出现新实体
```

树莓派上跑 A 路时，除了 modemmanager 还有两件顺手要做的：

```text
坑 1  棒离 2.4G 干扰源远一点（USB 3.0 口、路由器天线、金属机箱）
坑 2  这 4 台是电池设备（Zigbee 里的 sleepy end device）：
      入网时贴着协调器配，配好再贴回墙上；
      真正的覆盖要靠屋内其他常供电的 Zigbee 设备做路由，单靠 4 台电池传感器组不成网
```

验收口径沿用 16/17 号文档那一套：HA 里出现实体 → 触发一次状态变化 30 秒内更新 →
MCP `inspect_device` 能读到六字段 → 可写设备 `execute_action` 一次 `verified=true`。

## 6 落地顺序（按"你人在学校、设备在家"排）

```text
阶段 0  打通两边的 IP（这是所有方案的前置，不是可选项）
        树莓派 + 笔记本各装一套双向可通的通道（Tailscale / ZeroTier / 自建 WireGuard 都行）
        一个容易踩的坑：_work\broker\run_broker.py 现在绑的是 127.0.0.1:1883，
        家侧节点即使连通了也发不进来，需要改成绑隧道地址或 0.0.0.0
【待确认】树莓派那台机器上 Tailscale 到底装没装 —— 09 号清单里列了这一步，但没有装完的记录

阶段 1  蓝牙（先做，收益最确定）
        树莓派通电 → 按 4.1 的命令核查适配器 → HA 加 Bluetooth 集成
        把 BLE 设备（美的这台除外）放到树莓派旁边，看 HA 是否自动发现
        如果树莓派离设备太远或要覆盖多个房间 → 再补 4.2 的 ESP32 代理

阶段 2  Zigbee（这 4 台涂鸦传感器）
        要云、要省事 → 涂鸦 Zigbee 网关（40~70 元）+ 官方 tuya 集成扫码，今天就能下单调货
        要本地 → 协调器（80~200 元）插树莓派 + ZHA 配 TS0201，顺带把以后所有 Zigbee 都收进来
        两条不冲突，也可以先走 B 路看上数、以后再把设备迁到自建协调器（要重新配对一次）
```

```text
装电池之后的分工（2026-10-15 用）
  你做   给传感器装 2 节 7 号电池（指示灯亮一下即灭）→ 长按配置键 5~10 秒，指示灯开始闪
  我做   它一旦能进配网模式，我这边负责把协调器开成允许入网、看它有没有加进来、命名与验收
  别指望 装电池不等于接进 HA：电池只让它能开机、能进配网模式；
         真正"接进来"必须有一个协调器（棒）或涂鸦网关在它旁边。
         另外 Zigbee 不走蓝牙广播，所以树莓派的 BLE 扫描永远看不到它 —— 别用 scan.py 找它
  硬前提 协调器与传感器必须在同一间屋子里：传感器在宿舍，今天就能配；
         传感器已经在家，就只能等树莓派搬回去 —— 这一步没法用网络绕
```

## 7 今天的核对结论与未验证项

```text
已核对（可复现）
  校园网 tjuwlan；Docker 引擎未启动；Tailscale 未安装
  只有 4 个蓝牙虚拟串口，无任何 Zigbee USB 桥
  BLE 扫描工具链正常，能收到含 MiBeacon(0000fe95) 在内的真实广播
  Theengs Gateway 在本机 Windows 装不上（theengsdecoder 无 wheel，CMake 构建失败）
  Theengs 设备库无 Midea 条目；GitHub 无美的 BLE 温湿度计译码项目
  树莓派 HA Container 已挂 /run/dbus + --privileged + host 网络
  树莓派 HA 的 bluetooth 集成已 loaded、适配器进注册表、Discovering: yes，15 秒听到 85 台 BLE 设备
  树莓派 SSH 偶发超时（同一条命令重试即通），疑似 HA 启动期负载高，不是配置问题
  树莓派预检：modemmanager 未安装（官方那个坑不存在）；bleak 0.11.0 已装；
  /home/pi/scan.py 可跑（12 秒扫到 mobike 等设备，疑似温湿度计 0 台）；HA 容器里 zha 组件在；仍无串口设备
  HA 官方对 Container 蓝牙的要求、远程适配器支持矩阵、ZHA 对串口代理走 WAN/VPN 的否定态度
  涂鸦 TS0201 在 ZHA 官方 quirk 库里有专门文件、在 Z2M 有设备页（温湿度 + 电量 + 电压）
  米家两条 Zigbee 路线（XiaomiGateway3 / xiaomi_home）对涂鸦设备无效
  官方 tuya 集成现在的配置流程是手机 App 扫码授权

推断
  米家云里的 Zigbee 子设备能被官方 xiaomi_home 一起导入（要配好后才算数）
  ESP32 代理配合 Tailscale 子网路由，可以让校园网的 HA 用上家里的蓝牙代理

待确认
  这 4 台涂鸦传感器的具体厂商号/型号，以及是不是都是同一款
  "那几个蓝牙设备"具体是哪几台（涂鸦这 4 台是 Zigbee，不在这条线上）
  树莓派的 bluez 版本与板载适配器能否点亮（它现在断电/不在线）
  美的温湿度计的蓝牙载荷是"广播里直接带数据"还是"必须连接 + 私有协议"
```

## 8 相关文件

```text
_work\05_Zigbee接入判断.md                Zigbee 在现有部署下的可行性（本文第 5 节的底稿）
_work\08_美的温湿度计接入情况.md             这台温湿度计的三条路线与试过什么
_work\09_当前问题与待办.md                  总待办清单
_work\04_蓝牙音箱MQTT桥.md                   本地 MQTT 桥的设计先例
_work\ble\scan.py / watch.py                BLE 扫描工具（今天重跑过 scan.py）
_work\ha\xiaomi_options.py                  刷新米家设备清单（路线②要用的工具）
_work\broker\run_broker.py                  broker（注意绑的是 127.0.0.1:1883）
D:\项目\树莓派\HomeAssistant容器部署记录.md      树莓派 HA Container 的启动参数与验证结果
D:\项目\树莓派\树莓派配置记录.md                树莓派网络（有线 192.168.137.2）与踩坑
finally new paper\HomeAssistant双仓库接口分析\16/17/18/20 号文档  选型、BLE、Zigbee、树莓派
```
