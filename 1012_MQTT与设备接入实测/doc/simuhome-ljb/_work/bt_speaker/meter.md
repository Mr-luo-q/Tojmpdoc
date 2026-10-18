# meter.py

## 职责

读 Windows 每个**输出端点**当前的峰值电平，用来把"音箱没声音"这件事切成两半：
问题在 Windows 之前（流没起来 / 被静音），还是端点之后（蓝牙传输、音箱本身）。

它存在的理由：桥会打「收到命令：ON」「开始播放 announce.wav（device=4）」，
`probe_sessions.py` 也会显示 `python.exe state=Active`——**这三条都只证明"有一个音频流开着"，
不证明声音进了音箱**。电平表是唯一不靠耳朵就能回答"样本有没有被渲染到这一路"的东西。

## 输入

```text
argv[1]   采样秒数，默认 6
依赖      pycaw、comtypes；接口 IAudioMeterInformation 由脚本自带定义
```

## 输出

```text
默认输出 = 耳机 (EARZER SAB6)
采样 6.0 秒，逐端点记录最大峰值（0.000 = 完全没收到音频）

  0.412  ################               耳机 (EARZER SAB6) ← 默认输出
  0.000                                  扬声器 (Realtek(R) Audio)
```

## 读取 / 写入

只读系统音频状态；不写文件、不改音量、不播放。

## 怎么判读

```text
默认端点峰值 > 0，音箱仍无声   Windows 在渲染，问题在蓝牙传输或音箱侧
                               （音箱音量旋钮、音箱连着别的手机、A2DP 链路卡住）
默认端点峰值 = 0              没有音频进这一路，问题在 Windows 侧
                               （流没起来、去了别的端点、被静音）
别的端点峰值 > 0              音频去了别的设备，选错输出设备了
```

## 不负责

不判断"该用哪个 Host API"（那是 `play_to.py`），不改桥的设备选择（那是 `bridge.py`），
不做主观听感结论——它只给客观读数，听不听得见仍要人耳确认。

## 对应文件

```text
_work\bt_speaker\meter.py          本文件
_work\bt_speaker\probe_sessions.py 会话状态（只能证明"有没有流"）
_work\bt_speaker\play_to.py        同一音箱四档 Host API 的试播
_work\04_蓝牙音箱MQTT桥.md          设计与排查记录
```
