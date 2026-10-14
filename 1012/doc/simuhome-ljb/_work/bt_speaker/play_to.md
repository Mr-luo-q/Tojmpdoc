# play_to.py

## 职责

把 `media/announce.wav` 播到**指定的 PortAudio 输出索引**，用来判断同一个蓝牙音箱的哪一档 Host API 真能把声音送出去。

存在的理由：同一个音箱在 PortAudio 里会以 MME / DirectSound / WASAPI / WDM-KS 四档各出现一次。桥的选法是"名字匹配 + `check_output_settings` 通过就取第一个"，于是它锁在索引最小的 MME 那一档。但**"能打开"不等于"声音出得去"**——如果 MME 那一档是哑的，桥就会一直显示"已开始播放"而音箱没声音。这个脚本就是把同一段音频依次播到几档上，用耳朵分辨。

## 输入

```text
--name=子串    按这个名字子串筛设备，默认 SAB6（可以换成 Realtek 之类做对照）
--rate=采样率  播放前把素材线性重采样到该采样率（WASAPI 只吃设备默认率，常用 48000）
无索引         只列出匹配到的输出索引、Host API、可用采样率
若干索引       依次播到这些索引，每播一次停 1 秒

例：python play_to.py            # 先看有哪些索引
    python play_to.py 4 10 13    # 再逐个试
    python play_to.py --name=Realtek 9   # 对照：播给笔记本自己的扬声器
    python play_to.py 13 --rate=48000    # WASAPI 那一档必须重采样才能试
依赖：sounddevice、numpy
```

## 输出

```text
默认输出索引
名字含 SAB6 的输出设备： #索引 [Host API] 可用率 名字
音频：路径 时长 采样率
播到 #N <名字> …… / 播放调用返回，耗时 X.XX 秒 / 失败（X.XX 秒）：<原因>
```

耗时是有用的信号：真播完 2.5 秒素材，耗时就该在 2.5 秒上下；瞬间返回说明设备收下了流却没真播。

重采样是线性插值，只用于试播提示音（不做抗混叠），目的是让 WASAPI 那一档也能被试到。

## 读取

`media/announce.wav`（相对本目录）。脚本会先 chdir 到自身目录，所以从哪跑都行。

## 写入

无。只播放，不改配置、不改音量。

## 不负责

不改桥的设备选择（那要改 `bridge.py` 的 `_resolve_device`），不做循环播放，不判断原因——它只负责"这一档到底出不出声"。

## 失败时返回什么

单个索引播不出来时打印失败原因，继续试下一个，整体仍以 0 退出。

## 背景：为什么会有这个问题

`_work\04_蓝牙音箱MQTT桥.md` 第 10.2 节记过同一台音箱在 PortAudio 里出现四次、WDM-KS 那组打不开。
这次是另一种情况：桥显示"开始播放"、Windows 音频会话也是 `Active`，但音箱没声音，
所以要分辨是不是选中的那一档 Host API 只"接受流"而不"送出声音"。

## 对应文件

```text
_work\bt_speaker\play_to.py      本文件
_work\bt_speaker\bridge.py       里面的 Player._resolve_device() 决定锁哪一档
_work\bt_speaker\probe_devices.py 同一件事的只读版（只试 0.4 秒静音）
_work\bt_speaker\probe_sessions.py 查音频会话状态，判断"还有没有在流"
_work\04_蓝牙音箱MQTT桥.md         第 10 节记录了播放层的几个坑
```
