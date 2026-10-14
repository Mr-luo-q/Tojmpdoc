# tone_test.py

## 职责

往指定的 PortAudio 输出设备播一段**幅度恒定、持续若干秒**的正弦音，用来做"到底响不响"的
可控听感测试；可选地把系统音量临时拉到指定值并在结束后还原。

它存在的理由：`media\announce.wav` 是衰减提示音，真正响的只有开头约 1 秒，中途还有 2.5 秒循环的静默段。
音量偏低时，"响过"和"没响"在主观上分不清（`_work\04_蓝牙音箱MQTT桥.md` 10.4 节踩过一次）。
稳态音把"时长"和"音量"这两个混淆变量都去掉，响不响一目了然。

## 输入

```text
--device 索引     PortAudio 输出设备索引，默认 4（桥当前锁定的 MME 那一档）
--name 子串       按名字选设备，优先于 --device；会用 check_output_settings 验"能不能打开"
--include-handsfree  允许选中免提档（Hands-Free / bthhfenum）；默认跳过
--seconds 秒      时长，默认 4
--freq Hz         音高，默认 660
--amplitude 0~1   幅度，默认 0.3
--rate Hz         采样率，默认 44100
--beeps N         播 N 声短音（每声 0.4s 响 + 0.25s 静）；>1 时用于"自报家门"
--tag 文本        只影响日志，用来区分矩阵里的几路
--volume 0~100    可选：先把系统默认输出音量设成这个值，播完还原
--dry-metadata    只打印目标设备是谁，不播
依赖              sounddevice、numpy；--volume 时才需要 pycaw
```

## 输出

```text
[C] 目标设备：#30 [Windows WDM-KS] Output 2 (@...btha2dp.sys…)
  系统音量临时设为 100%（原 23%）
  正在播放 3 声 660Hz 短音 ……
  播放结束，耗时 1.95 秒
  音量已还原为 23%
```

耗时约等于音频时长说明设备真的把这段音频播完了；**瞬间返回**说明设备收下了流却没真播。

`--beeps` 的用处：把几路测试连着跑，听的人只要数"听到几声"就知道哪一路是通的，
不需要记住播放顺序，也不需要在每一声之间回来确认。

## 典型用法：四路矩阵

```text
A  1 声  --name "扬声器 (Realtek"   笔记本自己的扬声器：验证"测试本身听得到"
B  2 声  --name SAB6                音箱走 Windows 音频引擎（桥现在用的就是这条路）
C  3 声  --name btha2dp --rate 48000   音箱走 WDM-KS 直通（绕过音频引擎与音效处理）
D  4 声  --name bthhfenum --include-handsfree --rate 48000   同一个音箱的免提档

只听得到 A            → 音频引擎下面的蓝牙/音箱那一段断了
听得到 A、C，听不到 B → Windows 音频引擎（含音效/增强）这一段有问题
全都听不到 A          → 先怀疑听音环境或笔记本自身输出（跟音箱无关）
```

## 读取 / 写入

读 PortAudio 设备表；写系统音量（仅在给了 `--volume` 时，且必还原）。不写文件。

## 怎么用

```text
配合 meter.py 一起看：
  一个窗口 python meter.py 8
  另一个窗口 python tone_test.py --device 4 --seconds 6 --volume 100

  meter 峰值 > 0 而人耳没听到  → 音频进了 Windows 端点，问题在蓝牙传输或音箱侧
  meter 峰值 = 0              → 流没真的渲染到这一路，问题在 Windows 侧
```

## 不负责

不判断该用哪一档 Host API（`play_to.py` 是做这个的），不改桥的设备选择（`bridge.py`），
不改变桥的 ON/OFF 状态。听感结论仍要人耳确认——脚本只保证"什么被播出去了"。

## 对应文件

```text
_work\bt_speaker\tone_test.py      本文件
_work\bt_speaker\meter.py          端点峰值读数，配合它用
_work\bt_speaker\play_to.py        同一音箱四档 Host API 的逐档试播
_work\04_蓝牙音箱MQTT桥.md          排查记录与已知的三个播放层坑
```
