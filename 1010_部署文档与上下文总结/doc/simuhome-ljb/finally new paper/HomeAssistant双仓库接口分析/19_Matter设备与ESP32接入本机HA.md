# 19 Matter 设备与 ESP32 接入本机 HA（补充实测）

核对日期 2026-09-28。回答两个问题：Matter 设备 HA 有没有支持、ESP32 能不能接这台笔记本。

## 0. 结论

```text
Matter   HA 有官方集成，但控制端要另跑 Matter Server。HA OS 上的 Matter app 是官方
         唯一支持形态；Container 只能自己跑 matterjs-server，官方原文是
         "as-is and without official support ... at your own risk"。
         本机实测：Docker IPv6 关闭、HA 在 NAT 的 Linux VM 里，不满足 Matter 要求的
         "同 LAN + IPv6 链路本地多播" → 现在不适合买 Matter 设备。

ESP32    能接笔记本。USB 只用来烧固件；烧完跑 WiFi，HA 通过 <ip>:6053 连它，
         不用一直插在笔记本上，供电随便找个 USB 充电器即可。
```

## 1. Matter：HA 端有支持，我们这台机器不适合

```text
HA 官方 matter 集成：有（core 集成）
它自己不直接管设备，要先有一个 Matter Server，HA 通过 WebSocket 连过去
官方支持形态：HA OS + Matter app，"This is currently the only supported option"
Container 形态：自己跑 Matter server 的 Docker 镜像，官方说明 requirements 见仓库
```

Matter Server 的新仓库（matterjs-server）原文：

```text
"The Docker image is provided as-is and without official support
 (due to all the complex requirements to the underlying host/OS)."
"If you still prefer a self-managed container installation, you might experience
 communication issues with Matter devices, especially Thread-based devices."
"Matter is based on IPv6 link-local multicast protocols ... the machine running
 Matter Server is on the same (v)LAN as the devices ... The host network interface
 needs IPv6 support enabled."
"Running it on ... another operating system (even WSL) is not supported."
```

本机实测：

```text
Docker IPv6                      关闭（docker info ipv6 为空，默认网络 IPv6=false）
HA 容器                          跑在 Docker Desktop 的 NAT Linux VM 里
matter / thread config entries   均为 []（没配置，也没有 matter server 容器）
结论                             缺 IPv6、缺同 LAN 链路本地多播，正是 Matter 的硬前提
```

补充事实：Matter 设备配网用手机 App（HA Companion）通过蓝牙下发网络凭证，
配完走 IPv6（WiFi 或 Thread）。Thread 设备还需要一个 Thread 边界路由器。
也就是说配网那一步不依赖笔记本蓝牙，但运行那一步依赖 IPv6 网络可达。

什么时候能上 Matter：把 HA 换成 HA OS（虚拟机桥接网络或独立小主机）之后，
Matter app 是官方一等公民，那时再买 Matter 设备才有意义。
树莓派跑 HA OS 的具体方案见 20 号文档。

## 2. ESP32：怎么和这台笔记本配合

```text
烧录阶段   ESP32 用 USB 线插笔记本
           最简单：Chrome/Edge 打开 https://web.esphome.io/，走 WebSerial 直接刷
           或装 ESPHome CLI / 跑 ESPHome Device Builder 容器来编译和 OTA
           老款板子（CH340 / CP2102 芯片）Windows 可能要装驱动；C3/S3 原生 USB 免驱

运行阶段   ESP32 连 2.4GHz WiFi（只支持 2.4G），HA 从局域网连它的 6053 端口
           ESPHome 集成支持手动填 host + port，所以 Docker Desktop 里
           mDNS 发现不好用也能接上（填 IP 即可）；这一点等板子到了实测确认

供电       USB 充电器即可，不需要一直插在笔记本上
位置       放家里 WiFi 覆盖中间位置，蓝牙覆盖半径最大
```

## 3. 一块 ESP32 能同时干三件事

```text
① ESPHome 设备（HA 原生 API 直连）→ 覆盖 ESPHome 协议线
② Bluetooth proxy → BLE 设备进 HA（能听广播，也能主动连接控制）
③ Matter 测试设备：HA 文档有 "Experiment with Matter using a ESP32 dev board" 一节，
   推荐 M5 Stamp C3 刷 Lighting app，零买 Matter 硬件先试协议
```

注意③是另一套固件，和①②不能同时跑，要重刷；而且它仍然需要一个能用的
Matter 控制端（见第 1 节），所以先解决 HA OS 那一步才有意义。

## 4. 与 v2 MCP 的关系

Matter 设备进 HA 之后同样是标准实体，8 动作 / 6 字段的投影规则不变，
差别只在接入基础设施；ESP32 则是 BLE 代理 + ESPHome 协议线 + Matter 试验田三用。

## 5. 来源

```text
官方文档   HA Matter（Supported installation types / Contact / commissioning 流程 /
           Experiment with Matter using a ESP32 dev board）
           matterjs-server docs/docker.md、docs/os_requirements.md
           HA ESPHome（手动 host + port 输入、mDNS 与 DHCP 发现）
           网页烧录：web.esphome.io（200）
本机实测   docker info（IPv6）、docker network（IPv6=false）、
           HA /api/config/config_entries/entry?domain=matter|thread|esphome
```
