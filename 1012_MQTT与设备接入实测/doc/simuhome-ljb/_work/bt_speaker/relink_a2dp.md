# relink_a2dp.ps1

## 职责

强制 Windows **拆掉并重建**蓝牙音箱的 A2DP 音频链路。用于这一类症状：
音箱显示"已连接"、Windows 也在渲染音频、但音箱不出声——端点存在且收得到样本，
而端点底下的 A2DP 流卡住了。

为什么不从项目代码里修：这块完全在 Windows 的蓝牙栈里，HA / MQTT / bridge.py
连不上也用不到它（`bridge.py` 只能把样本交给音频引擎，剩下的交给驱动）。

## 输入

```text
-Match 子串      设备名里含这个子串，默认 SAB6
-RestartAudio    附加：重启 Windows Audio 服务（Audiosrv）
-RestartBluetoothStack  附加：重启蓝牙支持服务（bthserv + bthHFSrv），相当于"只重启蓝牙"
-WaitSeconds N   重建后等几秒再看端点，默认 8
权限             必须是管理员；不是的话只打印提示并以 1 退出
```

## 输出

```text
== looking for A2DP source devnodes matching 'SAB6' ==
  OK     BTHENUM\{0000110B-...}_VID&00010642_PID&0220\7&29A66C89&0&414243B6B1D4_C00000000
== restart-device: BTHENUM\{0000110B-...}
正在重新启动设备 ...
== waiting 8 s, then re-checking endpoints ==
Status Present FriendlyName
OK         True 耳机 (EARZER SAB6)
OK         True 耳机 (EARZER SAB6)
```

退出码：0 正常 / 1 不是管理员 / 2 没找到匹配设备。

## 它做什么（步骤）

```text
1  按名字找出 BTHENUM 下、"Microsoft Bluetooth A2dp Source" 那个 devnode
2  pnputil /restart-device 重启它 —— 这一步会让 A2DP 流关闭再重开
3  可选：重启 Audiosrv（把所有音频端点重置一遍）
4  等几秒，重新打印音箱的音频端点，确认它们回来了
```

## 写入

不改文件、不改配置。改动的是 Windows 设备状态（重启一个设备节点），
重启本身可逆：不行就重新配对，或重启电脑即可回到原状。

## 不负责

不做蓝牙配对（配对在 Windows 设置里做），不改音箱本身的音量，
不判断"该不该换设备"，也不动 `bridge.py`。

## 为什么脚本正文是 ASCII

仓库里的 `.ps1` 约定存成**带 BOM 的 UTF-8**（PowerShell 5.1 按本地代码页读无 BOM 的文件）。
本脚本由补丁工具生成，带不上 BOM，所以正文的注释与提示一律用 ASCII，
中文说明放在这份 md 里，避免中文被读成乱码后连带把语法搞坏。

## 对应文件

```text
_work\bt_speaker\relink_a2dp.ps1   本文件
_work\bt_speaker\tone_test.py      重建之后用它听 2 声短音验证
_work\bt_speaker\meter.py          端点电平表，判断"有没有样本进端点"
_work\10_当前状况与音箱无声排查.md   这轮排查的完整证据
```
