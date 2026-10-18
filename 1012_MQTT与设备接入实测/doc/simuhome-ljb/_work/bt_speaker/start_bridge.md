# start_bridge.ps1

## 职责

后台启动蓝牙音箱 MQTT 桥，日志落到 `_work\bt_speaker\logs\`。幂等：已经在跑就跳过启动，只做状态汇报。

## 输入

```text
命令行    无参数
依赖      PATH 里有 python
```

## 输出

```text
logs\bridge.out.log    子进程 stdout
logs\bridge.err.log    子进程 stderr
stdout                 一行状态："桥运行中：PID N，日志 <路径>"，或报错
```

## 读取

进程列表（`Get-CimInstance Win32_Process`），按「进程名 python.exe + 命令行含 `bt_speaker\bridge.py`」判定是否已在运行。

## 写入

启动一个隐藏窗口的 python 子进程，并把它的 stdout/stderr 重定向到日志文件。

## 不负责

不做开机自启，不做崩溃重启，不检查 broker 是否在跑（broker 没起时桥会连不上，日志里能看出来）。

## 失败时返回什么

```text
找不到 python   Write-Error 后 exit 1
启动后进程不在  Write-Error "桥未启动，看 …\bridge.err.log"
```

## 注意

脚本不要接管道。子进程会继承管道写端，接了会挂住——仓库自己的 `start_simuhome_stack.ps1` 里也记了同一条。

## 双击入口（start_bridge.cmd）

`start_bridge.cmd` 是三行包装：`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_bridge.ps1"` 加一句 `pause`。`%~dp0` 指向本文件所在目录，从任何位置双击都能找到同目录的 ps1；`pause` 让窗口留住，方便看启动结果或报错。它不透传参数，需要传参就直接调 ps1。

## 对应文件

```text
_work\bt_speaker\start_bridge.ps1     本文件
_work\bt_speaker\start_bridge.cmd     双击入口（见上一节）
_work\bt_speaker\bridge.py            被启动的程序
```
