# diag_audio.py

## 职责

诊断音频链路：列出所有音频设备、报默认输出设备与音量/静音状态、可选择先把音量调到某个值，然后直接放一次 `media\announce.wav`。

排查顺序被刻意固定成「先看设备和音量，再看播放器」——本项目最早那次"没声音"其实就是音量只有 15%，提示音只有 2.5 秒，听不见。

## 输入

```text
argv[1]   目标音量百分比 0~100（可选，给了才改）
argv[2]   播放次数，默认 1

例：python _work\bt_speaker\diag_audio.py            # 只看设备与音量，放一次
    python _work\bt_speaker\diag_audio.py 60 3       # 音量调到 60%，连放 3 次
```

## 输出

```text
== 所有音频设备（render = 输出）==  每台设备一行，标 render / capture
== 默认输出设备 ==                  名字、音量（小数与百分比）、是否静音
== 试放 ==                          文件路径与存在性、每次播放完成一行
```

## 读取

`media\announce.wav`；系统音频设备与音量。

## 写入

```text
设了 argv[1] 就写系统音量（SetMasterVolumeLevelScalar）
会真的用 winsound 播放该 WAV，声音外放
```

## 不负责

不改默认输出设备（改默认设备请在 Windows 设置里做），不做音量还原，不做设备切换。

## 失败时返回什么

`announce.wav` 不存在时打印提示并返回 1（正式桥会在启动时自动生成）。其他异常以 traceback 结束。

## 对应文件

```text
_work\bt_speaker\diag_audio.py      本文件
_work\bt_speaker\bridge.py          media\announce.wav 的生产者
_work\bt_speaker\probe_devices.py   播放器侧选设备的探针
_work\04_蓝牙音箱MQTT桥.md            第 10.4 节记了"音量只有 15%"那次误判
```
