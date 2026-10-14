# probe_sessions.py

## 职责

列出本机音频会话里属于 `python.exe` 的项，用会话状态客观判断"还有没有在出声"。

为什么需要：听感会骗人（音量低、环境吵都会误判）。Windows 的音频会话状态是可读的客观量：0=Inactive（没在播）、1=Active（正在播）、2=Expired。

## 输入

```text
命令行    无参数
依赖      pycaw
```

## 输出

```text
  PID <pid>  python.exe  state=Inactive|Active|Expired
  没有 python.exe 的音频会话（说明没在出声）
```

## 读取

`AudioUtilities.GetAllSessions()`。

## 写入

无。纯只读，不控制播放。

## 不负责

不区分是哪个 python 进程在放（只按进程名筛），不做时间维度统计，不代替听感验收。

## 失败时返回什么

pycaw 未安装时 `ImportError`。取不到的属性会退化成 `?`，不抛异常。

## 对应文件

```text
_work\bt_speaker\probe_sessions.py   本文件
_work\bt_speaker\bridge.py           ClipPlayer 的停止逻辑就是靠它验证的
_work\04_蓝牙音箱MQTT桥.md             第 10.5 节
```
