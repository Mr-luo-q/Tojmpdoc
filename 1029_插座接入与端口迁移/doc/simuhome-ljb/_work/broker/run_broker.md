# run_broker.py

## 职责

在本机起一个常驻 MQTT broker（amqtt，纯 Python 实现），默认监听 `127.0.0.1:1883`（可用 `MQTT_PORT` 覆盖），供沙盒链路使用：发布器往它写，HA 容器经 `host.docker.internal` 从它读。

为什么不用 Mosquitto：本机 `registry-1.docker.io` 不通，拉不到 `eclipse-mosquitto` 镜像；仓库 `_tools\mqtt\README.md` 给出的本机可行路线之一就是 amqtt。这里的配置照搬同目录 `probe_mqtt.py` 已实测过的写法（单向监听、允许匿名、不做主题校验），只把端口从探针的 18830 换成正式的 1883。

## 输入

```text
命令行    无参数
环境变量  MQTT_PORT   监听端口，默认 1883
          为什么需要它：Windows 的 Hyper-V/WSL 会把一段端口划成保留区
          （netsh interface ipv4 show excludedportrange protocol=tcp 可查），
          2026-10-29 开机后 1883 落在 1815-1914 里，绑定直接报 WinError 10013，
          这时用 MQTT_PORT=2883 换个端口即可，Z2M / HA / MCP 侧同步改
外部依赖  amqtt（PyPI 可装）
```

## 输出

```text
stdout    一行 "amqtt broker listening on 127.0.0.1:1883"
进程      常驻，直到被 Ctrl+C 或 stop_sandbox.ps1 杀掉
```

## 读取

无文件读取。所有配置写死在模块顶部的 `CONFIG` 字典里。

## 写入

```text
监听端口  127.0.0.1:${MQTT_PORT:-1883}（本机当前用 2883）
持久化    无。进程重启后 retained 消息全部丢失，发布器需要重发 discovery
```

## 不负责

不做鉴权（`allow-anonymous` 为真），不做主题 ACL（`topic-check` 关闭），不提供 TLS，不做持久化。它只服务于本机沙盒。

## 失败时返回什么

端口被占用时 `Broker.start()` 抛异常，进程退出并打印 traceback。脚本没有做端口预检，占用冲突要靠 traceback 里的 `Address already in use` 判断。

## 安全边界

只监听环回。改成 `0.0.0.0` 会把这个无鉴权 broker 暴露到局域网甚至公网，不要这么改。

## 对应文件

```text
_work\broker\run_broker.py            本文件
_tools\mqtt\probe_mqtt.py             配置写法的来源（仓库只读文件）
_work\start_sandbox.ps1               第 4 步启动本 broker（端口已占用则跳过）
_work\stop_sandbox.ps1                按命令行特征停止本进程
```
