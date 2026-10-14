# probe_volume.py

## 职责

探 pycaw 的 API 形状：读默认输出设备的当前音量与静音状态，并列出可用的设置接口。

存在的原因：pycaw 各版本取 `IAudioEndpointVolume` 的方式不同，有的版本 `device.EndpointVolume` 直接可用，有的要先 `Activate` 再 `QueryInterface`。先把能用的那条路打出来，再写正式代码。

## 输入

```text
命令行    无参数
依赖      pycaw（+ comtypes）
```

## 输出

```text
GetSpeakers() -> <类型名>
  有 EndpointVolume: True/False
  有 Activate: True/False
  有 QueryInterface: True/False
走哪条路（device.EndpointVolume 或 Activate + QueryInterface）
当前音量 = 0.xxx
是否静音 = True/False
设置 API: [含 Master 或 Mute 的方法名]
```

## 读取

系统音频端点状态（COM 接口）。

## 写入

无。只读探针，不设置音量、不改静音。

## 不负责

不判断设备对不对，不做音量换算，不处理多设备。

## 失败时返回什么

pycaw 未安装时 `ImportError`；找不到默认输出设备时 `GetSpeakers()` 抛异常。两者都以 traceback 结束。

## 对应文件

```text
_work\bt_speaker\probe_volume.py   本文件
_work\bt_speaker\bridge.py         里面的 Volume 类按本探针的结论写
```
