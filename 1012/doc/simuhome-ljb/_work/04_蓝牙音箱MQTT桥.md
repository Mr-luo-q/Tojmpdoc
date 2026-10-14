# 04：蓝牙音箱 MQTT 桥（ERAZER SAB6）

> 核对时间：2026-10-10
> 依据：`ha_mcp_universal` 的 claim 规则与 contract 契约、`simuhome_mqtt_publisher` 的 discovery 写法
> 状态：**链路已端到端打通**（HA 实体 → MQTT → Windows 播放）。音箱本身还没配对，见第 7 节。

## 1 为什么需要这座桥

三条硬约束决定了"不能直接把音箱接给 HA"：

```text
① HA 在 Docker Desktop 的 Linux VM 里，拿不到 Windows 的蓝牙适配器
   （容器里连 bluez 库都没有）
② 就算给了蓝牙也没用：音箱是 Classic BT 的 A2DP 音频输出，
   HA 的 bluetooth 集成只处理 BLE 广播，不碰音频
③ MCP v2 的动作契约只支持 switch / climate / fan
   （contract/tools.py 的 ACTIONS_BY_KIND），没有 media_player
```

所以做法反过来：**Windows 负责出声，HA 只负责发命令**，中间用 MQTT 连起来。

## 2 拓扑

```text
HA 容器 :8123
    │  MQTT 集成（已连）
    ▼
broker :1883（amqtt）
    │  bt_speaker/v1/set
    ▼
Windows 上的 _work\bt_speaker\bridge.py
    │  winsound（默认音频输出设备）
    ▼
蓝牙音箱（Windows 负责 A2DP 配对）
```

## 3 实体与主题

| 用途 | 主题 | 载荷 |
| --- | --- | --- |
| discovery（开关） | `homeassistant/switch/bt_speaker/config` | retained JSON |
| discovery（量级） | `homeassistant/number/bt_speaker_volume/config` | retained JSON |
| 状态 | `bt_speaker/v1/state` | `ON` / `OFF`（retained） |
| 命令 | `bt_speaker/v1/set` | `ON` / `OFF` |
| 音量状态 | `bt_speaker/v1/volume` | `0`~`100`（retained） |
| 音量命令 | `bt_speaker/v1/volume/set` | `0`~`100` |
| 播报 | `bt_speaker/v1/say` | 任意文本 → Windows TTS → 播放 |
| 在线 | `bt_speaker/v1/status` | `online` / `offline`（LWT 维护） |

HA 里落地成两个实体，挂同一台设备：

```text
switch.bt_speaker         友好名「蓝牙音箱」    播放 / 停止
number.bt_speaker_volume  友好名「音箱音量」    0~100，对应系统默认输出设备的音量
```

两个实体的 discovery 里 `device.identifiers` 都是 `["bt_speaker"]`——**这一点是关键**：
HA 靠它把两个实体归到同一台设备，MCP 才会把 `power` 和 `level` 投影成同一台逻辑设备。

## 4 语义

```text
ON    播放 audio.media 指定的 WAV（默认 media/announce.wav，文件不存在会自动生成提示音）
      默认 audio.loop: true —— 一直循环播放，直到 OFF
      （原来默认播一遍，但提示音只有 2.5 秒，想中途停得抢时间，所以改成循环）
OFF   停止播放
音量  0~100，写的是输出设备的音量（pycaw）；改了会同步回 HA，
      你在系统里手动改音量，HA 里也会跟着变（默认每 5 秒同步一次）
say   不经过 switch，直接播报一段话（Windows 自带 SAPI 合成，不依赖第三方库）
```

注意 "ON/OFF" 是**播放开关**，不是音箱电源——蓝牙音箱的电源没法通过 A2DP 控制。

## 4b 为什么加一个 number 就能多出"量级"

MCP 的动作不是按"类别"写死的，而是**从角色表推**的（见 `registry/roles.py` 与
`registry/actions.py`）。角色推断里，`number` 域的范围落在 0~100 就会被判成 `level` 角色，
于是这台设备自动获得 `set_percentage`，落到 HA 的 `number.set_value`。

所以这次的改动量是：

```text
桥       多发一个 number 的 discovery，多接一个音量主题
MCP      只加了一条认领规则（local，unique_id_prefix: bt_），没有改任何源码
效果     inspect_device 里 state 从 {on} 变成 {on, level}，
         动作从 3 个变成 4 个（turn_on / turn_off / toggle / set_percentage）
```

这就是"分了几类去分别支持"的实际运作方式：**领域事件（实体）决定角色，角色决定动作**，
扩展方式是给设备加实体，不是加类别。

## 5 MCP 认领

`_work\mcp\config.yaml` 里加了一条规则（不动 `ha_mcp_universal\` 的源文件）：

```yaml
  - name: local
    platforms: [mqtt]
    unique_id_prefix: bt_       # unique_id = bt_speaker_switch
    id_source: identifier       # 设备标识 bt_speaker → 逻辑 id speaker
    kind_by_suffix:
      _switch: switch
```

于是设备在 MCP 里叫 `speaker`，动作是标准的 `turn_on` / `turn_off` / `toggle`。

## 6 实测结果

```text
MCP execute_action(speaker, turn_on)
  → HA switch.turn_on → bt_speaker/v1/set = ON
  → 桥播放 announce.wav（2.5s）
  → state_diff {on: false→true}，verified=true，elapsed_ms=815
  → 播完自动回 OFF（HA 里确认 state=off）

播报：publish bt_speaker/v1/say "客厅灯已经打开"
  → 合成 bt_speaker_say.wav（3.3s）→ 播放 → 结束

MCP execute_action(speaker, set_percentage, {value: 35})
  → number.set_value(number.bt_speaker_volume, 35)
  → 系统音量实测从 7 变成 35，state_diff {level: 7→35}，verified=true，elapsed_ms=844
  → 测完用 publish 把音量还原成原来的 7

改名：switch.lan_ya_yin_xiang_lan_ya_yin_xiang → switch.bt_speaker
      number.lan_ya_yin_xiang_yin_liang → number.bt_speaker_volume
      （HA 的 MQTT discovery 不支持 object_id，中文名会被拼音化并重复两遍）
```

观察 25 秒日志零新增，没有反馈回环。

## 7 还没做的：把声音真正送到音箱

现在 `dry_run: false` 且播放走的是**系统默认输出设备**，所以刚才响的是你电脑的扬声器。
要送到音箱：

```text
1. Windows 设置 → 蓝牙 → 添加设备 → 配对 ERAZER SAB6
2. 把它的输出设为默认（或连接时 Windows 自动切过去）
3. 桥不需要改配置就能生效；config 里的 audio.device_name 目前只用来打日志提示
```

如果希望"不抢占默认输出、只在播报时切到音箱"，需要加 `pycaw` 做定向切换
（`pip install pycaw comtypes`），当前版本没做。

## 8 顺带发现的 broker 问题（重要）

**amqtt 在投递 retained 消息时不按订阅过滤。** 实测：只订阅精确主题
`bt_speaker/v1/set`，却收到了 59 条完全无关的 retained 消息（所有 simuhome 的
discovery 和状态）。HA 之所以没暴露这个毛病，是因为它订阅的是 `homeassistant/#`
这类宽通配，收到无关消息也会忽略。

影响面：

```text
桥                已加防御——自己校验 message.topic，不匹配就丢弃并计数（日志里能看到）
simuhome 发布器   订阅 simuhome/v1/+/set，理论上会收到别的 retained 消息，
                  目前没观察到异常；值得留意
HA                无影响（宽通配 + 忽略未知主题）
```

这正是"MQTT 客户端不该假设 broker 只送它订阅的东西"的现实例子。

## 9 文件

```text
_work\bt_speaker\bridge.py        桥本体（discovery + set/state + LWT + 播放/TTS）
_work\bt_speaker\config.yaml      配置（broker / 实体名 / 音频 / 干跑开关）
_work\bt_speaker\start_bridge.ps1 后台启动（.cmd 双击版）
_work\bt_speaker\probe_volume.py  探 pycaw 的 API 形状（版本间差异大，先探再用）
_work\broker\publish.py           往 broker 发一条消息（排查与测试用）
_work\broker\probe_filter.py      验证订阅过滤（就是靠它抓到第 8 节那个问题）
_work\ha\rename_entity.py         改 HA 的 entity_id / 友好名
```

## 10 播放层的三个坑（2026-10-10 排查"没声音/不能暂停"时挖出来的）

### 10.1 停止是空操作：`winsound` 的 `SND_PURGE` 在现代 Windows 上不受支持

第一版用 `winsound.PlaySound(..., SND_ASYNC)` 播放、用
`winsound.PlaySound(None, SND_PURGE)` 停止。问题在于 Python 文档明写
**`SND_PURGE` 在现代 Windows 上不受支持**——所以那句"停止"压根没作用，
用户按了停止当然不停。加上默认提示音只有 2.5 秒，想按的时候往往已经播完，
两个假象叠在一起就成了"怎么按都没反应"。

换成 **`sounddevice`**：`sd.play(data, rate, device=..., loop=...)` + `sd.stop()`，
停止是立即生效的（实测命令到停止约 200 ms）。顺带解决了"只想播到默认设备"的
脆弱依赖。

### 10.2 选错了设备：PortAudio 里同一个蓝牙音箱会出现四次，其中 WDM-KS 那组打不开

同一个音箱在 PortAudio 里会以四种 Host API 各出现一次：

```text
#4   [MME]                耳机 (EARZER SAB6)         —— 能打开
#10  [Windows DirectSound] 耳机 (EARZER SAB6)         —— 能打开
#13  [Windows WASAPI]      耳机 (EARZER SAB6)         —— 能打开
#29  [Windows WDM-KS]      Output 1 (@...btha2dp.sys) —— 名字最像正主，但打不开
#32/#33 同样 WDM-KS 的是免提档（bthhfenum），也别用
```

第一版按"名字里带 btha2dp"去挑，正好挑中了打不开的 `#29`，播放直接报
`Invalid device [PaErrorCode -9996]`。

现在的选法：**先按名字筛出候选 → 排掉免提档 → 用 `sd.check_output_settings`
逐个验能不能真的打开 → 取第一个能用的**（实测落在 `#4`，MME）。并且播放失败时
自动退回系统默认设备，不让一个选错把功能全废掉。

顺带一个发现：这音箱上报的名字是 **`EARZER SAB6`**（厂商把 ERAZER 拼错了一个字母），
所以配置里用 `SAB6` 这种不会拼错的子串去匹配。

### 10.3 首次播放要等 8~9 秒

PortAudio 第一次枚举设备很慢（实测 8~9 秒），而这发生第一次播放的命令路径上，
"按下到出声"就变成了十几秒。现在改成**启动时在后台预热**（解析设备 + 预读音频），
实测命令到出声 **45 ms**。

### 10.4 顺带的音量教训

"没声音"最早其实是**音量只有 15%**——2.5 秒的提示音在这个音量下几乎听不见。
排查音频问题时要先看默认设备和音量，再看播放器；这次差点在播放器上白费功夫。

### 10.5 更狠的一层：`sd.play(loop=True)` + `sd.stop()` 也停不下来

换成 sounddevice 之后，日志显示每次 OFF 都收到了、也打了"已停止播放"，
**但音箱继续响**。原因是用 `sd.play(..., loop=True)` 起的循环播放，`sd.stop()`
并不能可靠地把它掐掉；而且每点一次 ON 就再叠一个流，越点越停不下来。

最终改成**自己持有 `sounddevice.OutputStream`、用回调喂数据**（`ClipPlayer` 类）：

```text
播放   回调按帧往 outdata 里填，循环就回绕，非循环就填零并抛 CallbackStop
停止   把 playing 置 False（回调随即抛 CallbackStop）再 stream.abort() + close()
```

这条路径不依赖"库里应该会停"的假设。客观验证（`_work\bt_speaker\probe_sessions.py`
查 Windows 音频会话状态）：

```text
播放中   python.exe 音频会话 = Active
发 OFF   python.exe 音频会话 = Inactive（3 秒后复查仍是 Inactive）
```

### 10.6 蓝牙设备会掉线又回来：解析失败不能缓存

蓝牙音箱断开时（音频端点状态变 `Unknown`），`_resolve_device` 找不到它、
退回系统默认。但第一版把"解析过一次"直接标成 True，于是**音箱重新连上也不会再认它**。

现在：解析成功才标记完成；失败则 30 秒后允许重试（PortAudio 枚举一次要好几秒，
不能每次播放都重来）。
## 11 2026-10-12：音箱接上，端到端出声验证

第 7 节那条"还没做的：把声音真正送到音箱"这次做完了。

```text
音箱状态    已开机并连上 Windows；PortAudio 里出现四组：
            #4 [MME] / #10 [DirectSound] / #13 [WASAPI] / #29 #30 [WDM-KS]
            这次 WDM-KS 那两组也报出了可用采样率（之前是打不开的那组）
            系统默认输出设备索引变成 4，也就是 MME 那一档的 耳机 (EARZER SAB6)

桥启动日志  已连接 broker 127.0.0.1:1883
            discovery 已发布：homeassistant/switch/bt_speaker/config
            输出设备锁定为 #4 耳机 (EARZER SAB6)
            预热完成：设备与音频都就绪

HA 实体     switch.bt_speaker off / number.bt_speaker_volume 40
            两个都从 unavailable 变成可用

端到端      发 ON  →「收到命令：ON」→「开始播放 announce.wav（2.5s，loop=True，device=4）」
                     HA 里 switch.bt_speaker = on
            发 OFF →「收到命令：OFF」→「已停止播放」

客观验证    _work\bt_speaker\probe_sessions.py
            播放中：PID 95744 python.exe state=Active
            停止后：PID 95744 python.exe state=Inactive
```

一个操作上的坑（这次踩到）：用 `Start-Process -Wait` 去跑 `start_bridge.ps1` 会**卡死**——
`-Wait` 等的是整个子进程树，而桥是常驻进程。正确做法是不加 `-Wait`，或者把输出重定向到文件后
用 `Get-Content` 看结果。脚本本身没问题。
