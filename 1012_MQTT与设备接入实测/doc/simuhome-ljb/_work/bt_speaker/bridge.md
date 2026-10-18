# bridge.py

## 职责

把本机的蓝牙音箱通过 MQTT discovery 接进 HA：HA 侧只出现两个实体，声音由本机 Windows 的音频输出负责。

拓扑是三段式的：

```text
HA 容器 :8123
    │  MQTT 集成（已连）
    ▼
broker :1883（amqtt）
    │  bt_speaker/v1/set
    ▼
本机 bridge.py（Windows）
    │  sounddevice 回调播放
    ▼
蓝牙音箱（Windows 负责 A2DP 配对）
```

之所以绕这一圈：HA 在 Docker 的 Linux VM 里拿不到 Windows 蓝牙；就算给了蓝牙，音箱是 Classic BT 的 A2DP 音频输出，而 HA 的 bluetooth 集成只处理 BLE 广播；MCP v2 的动作契约也没有 media_player。

## 输入

```text
配置文件  config.yaml（同目录）
MQTT      bt_speaker/v1/set           ON / OFF
          bt_speaker/v1/volume/set    0~100
          bt_speaker/v1/say           任意文本 → Windows TTS → 播放
```

## 输出

```text
MQTT 发布  homeassistant/switch/bt_speaker/config         retained，HA 建开关实体
          homeassistant/number/bt_speaker_volume/config   retained，HA 建音量实体
          bt_speaker/v1/state          ON / OFF（retained）
          bt_speaker/v1/volume         0~100（retained）
          bt_speaker/v1/status         online / offline（LWT 维护）
声音      播到配置里 device_name 匹配的输出设备；匹配不到就退回系统默认
```

## 读取

`config.yaml`；系统音频设备列表；定期读系统音量回同步给 HA。

## 写入

不写文件（生成的提示音写 `media\announce.wav`，仅在素材缺失时创建一次）。

## 关键实现点

```text
_shared_block()      两个实体的 device.identifiers 必须是「单个字符串的列表」。
                     写成 ["a","b"] 会被 HA 当成两台设备，MCP 也就无法把
                     power 与 level 两个角色投影成同一台逻辑设备。

ClipPlayer          自己持有 sounddevice.OutputStream，用回调喂数据。
                     用 sd.play(loop=True) + sd.stop() 停不掉（实测），
                     回调里抛 CallbackStop 再 stream.abort() 才可靠。

Player._resolve_device()  同一个音箱在 PortAudio 里会以四种 Host API 各出现一次，
                     其中 WDM-KS 那组打不开。选法是按名字筛候选 → 排掉免提档 →
                     用 check_output_settings 逐个验证 → 取第一个能用的。
                     解析失败不缓存，30 秒后允许重试（蓝牙会掉线又回来）。

Player.warmup()      首次枚举 PortAudio 要 8~9 秒，放在启动时后台预热，
                     命令到出声从十几秒降到 45 ms。

Volume               用 pycaw 读写系统输出设备音量；没装 pycaw 时自动降级关闭。

主题校验             amqtt 投递 retained 时不按订阅过滤，所以收到消息要自己比对
                     message.topic，不匹配就丢弃并计数。
```

## 不负责

不控音箱电源（A2DP 做不到），不做蓝牙配对（Windows 设置里做），不做多设备混音，不做曲线音量（只有量级 0~100）。

## 失败时返回什么

```text
播放失败        自动退回系统默认设备，不抛给调用方
设备解析失败    退回系统默认；30 秒后允许重试
config 缺字段    用模块默认值；audio.volume 为真但 pycaw 缺失时关闭音量实体并打日志
```

## 对应文件

```text
_work\bt_speaker\bridge.py                 本文件
_work\bt_speaker\config.yaml               它的配置
_work\bt_speaker\start_bridge.ps1          后台启动
_work\bt_speaker\probe_devices.py          选输出设备时的探针
_work\bt_speaker\probe_sessions.py         客观判断"还有没有在出声"
_work\04_蓝牙音箱MQTT桥.md                   设计、实测与三个播放层坑的完整记录
```
