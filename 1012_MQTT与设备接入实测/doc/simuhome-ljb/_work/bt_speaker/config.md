# config.yaml

这是 `bridge.py` 的配置。四个段，数据如下。

```text
broker
  host        127.0.0.1
  port        1883
  client_id   bt-speaker-bridge
  username    （空：本机 amqtt 允许匿名）
  password    （空）

name          蓝牙音箱          HA 里的友好名
model         ERAZER SAB6       写进 discovery 的 device.model

audio
  media        media/announce.wav  ON 时播放的文件（相对本目录）
  loop         true                ON 一直循环，直到 OFF
  dry_run      false               true 时只打日志不出声
  device_name  SAB6                输出设备名的子串匹配
  say_voice_rate  0                TTS 语速，-10 ~ 10
  volume       true                是否暴露 number.bt_speaker_volume
  volume_poll_s   5                把系统音量同步回 HA 的间隔（秒）
```

两个容易踩的点，都写在注释里了：

```text
device_name 用 SAB6 而不是 ERAZER SAB6，
因为音箱上报的厂商名把 ERAZER 拼错成了 EARZER，用 SAB6 这个不会拼错的部分更稳。

loop 默认 true。提示音只有 2.5 秒，播一遍的话想中途停得抢时间；
改成循环之后"停止"随时都有作用。
```

## 对应文件

```text
_work\bt_speaker\config.yaml            本文件
_work\bt_speaker\bridge.py              读取方
_work\bt_speaker\probe_devices.py       用来确认 device_name 该写什么
```
