# scan.py

## 职责

扫一遍周围的 BLE 广播，列出设备地址、名字、信号强度、广播里的服务 UUID / 厂商数据 / 服务数据，并标出疑似温湿度计。

存在的理由：HA 跑在 Docker 的 Linux VM 里，拿不到 Windows 的蓝牙适配器（见 `_work\04_蓝牙音箱MQTT桥.md` 第 1 节）。BLE 设备只能在本机 Windows 这一侧读，再经 MQTT 转给 HA。这个脚本回答第一步的问题——PC 能不能收到它的广播。

## 输入

```text
argv[1]   扫描秒数，默认 12
依赖      bleak（pip 包）
```

## 输出

```text
每台设备一行：地址、rssi、名字；疑似温湿度计的那台带 <== 标记
名下缩进列出：服务 UUID / 厂商数据（company id + 前 24 字节十六进制）/ 服务数据
结尾：疑似温湿度计几台，分别是哪个地址
```

## 读取

蓝牙适配器收到的广播包。不连接、不配对、不读 GATT。

## 写入

无。纯只读，不影响设备状态，也不影响手机 App 的连接。

## 判定"疑似温湿度计"的两条依据

```text
名字里含 SENSOR_HINTS 的片段   LYWSD / MJ_HT / MJWSD / ATC_ / Thermo /
                              Temp / Humid / CGG / MHO-C / XMWSDJ / TH- / SHT
广播里带标准环境感知服务        0000181a-0000-1000-8000-00805f9b34fb
```

这两条只是启发式。很多便宜传感器不带名字、也不广播标准服务，载荷走厂商私有格式，
所以"没标出来"不等于"没在广播"——要按型号确认，或者用厂商数据反查。

## 不负责

不解析广播载荷里的温湿度数值（要按厂商协议写，见下一步的桥），不连接设备，不做 GATT 读取，不写 MQTT。

## 失败时返回什么

`bleak` 未安装时 ImportError。蓝牙适配器关闭或没有权限时抛异常退出。扫到 0 台也算正常结果。

## 手机已经连着它，会不会冲突

大多数 BLE 温湿度计是广播型：读数写在广播包里，任何接收方都能被动收到，不需要建立连接。手机 App 连着它通常不阻止别人接收广播。真正的例外是固件在"已连接"状态下主动停播，那种情况脚本会扫不到。

## 实测（2026-10-12）

### 在树莓派上跑（bleak 0.11.0）

同一份脚本从 Windows 搬到树莓派，撞到两处 bleak 的版本差异，都已做兼容：

```text
discover(return_adv=True) 的返回形状
  Windows（新 bleak）   dict {address: (device, adv)}
  树莓派 bleak 0.11.0    签名是 (timeout, **kwargs)，return_adv 被忽略，
                        返回 list[BLEDevice]，里面没有广播数据
  处理                  改用 BleakScanner(detection_callback=...)，两边都成立

信号强度放在哪
  Windows   adv.rssi
  树莓派    AdvertisementData 没有 rssi，取 device.rssi
  处理     加 rssi_of(device, adv) 兼容两者
```

树莓派上的实测输出：扫 10 秒拿到 46~50 台设备（mobike、REDMI Buds、EDIFIER BLE 等有名字的若干），结论"疑似温湿度计 0 台"——设备在家里，本来就扫不到，这一步验的是工具链。

### 在 Windows 上跑

```text
环境    本机 Intel Wi-Fi 6E AX211 的蓝牙，bleak 可用
时长    15 秒
结果    收到 193 台设备的广播，疑似温湿度计 0 台

扫到的东西（抽样）
  company=0x004c  Apple 系设备（手机、耳机、AirTag 之类）
  company=0x038f  服务数据 0000fdaa，载荷里能读出 "Redmi Note 13 Pro"、
                  "Xiaomi Pad 7"、"Redmi K..." 等机型名 —— 小米设备的互联广播
  0x0006 / 0x0837 / 0x079a 等  其它手机与可穿戴
  EDIFIER BLE / WH-CH720N / REDMI Buds / Bass BS2 Lite  耳机与音箱
  mobike / hellobike  共享单车

没有出现的
  厂商数据里没有 0xfe95（小米 MiBeacon 用的公司标识）
  没有任何设备广播 0x181a（环境感知服务）
```

## 对应文件

```text
_work\ble\scan.py                 本文件
_work\ble\scan.md                 这份说明
_work\bt_speaker\bridge.py         同一模式的先例：Windows 读 → MQTT discovery → HA
_work\04_蓝牙音箱MQTT桥.md          为什么不能让 HA 直接碰蓝牙
```
