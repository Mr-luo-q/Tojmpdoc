# probe_devices.py

## 职责

找出 sounddevice 里真正能打开的输出设备，重点是那台蓝牙音箱。

背景：直接拿 `sd.query_devices()` 的索引去 `sd.play(device=...)` 会报 `Invalid device [PaErrorCode -9996]`——索引必须先用 `check_output_settings` 验过，光看名字会选到打不开的那组。

## 输入

```text
argv[1]   名字子串，默认 SAB6
依赖      sounddevice、numpy
```

## 输出

```text
默认输出设备索引 = N
== 名字含 'SAB6' 的输出设备 ==
  #索引 [Host API] ch=x default_rate=y 可用率=[44100,48000]
        <设备名前 80 字>
== 逐个试播（0.4 秒静音）==
  #索引 @ 采样率 播放成功 / 失败：<错误>
```

## 读取

PortAudio 的设备枚举。

## 写入

会真的打开输出设备并播 0.4 秒静音。除了占用音频端点，不影响任何状态。

## 不负责

不改系统默认设备，不设音量，不判断音质，不处理录音方向。

## 失败时返回什么

单个索引打不开时打印该索引的错误并继续试下一个采样率，整体仍以 0 退出。它不抛异常中断遍历。

## 对应文件

```text
_work\bt_speaker\probe_devices.py   本文件
_work\bt_speaker\bridge.py          Player._resolve_device() 按同一思路实现
_work\04_蓝牙音箱MQTT桥.md            第 10.2 节记了这个坑（同一音箱在 PortAudio 里出现四次）
```
