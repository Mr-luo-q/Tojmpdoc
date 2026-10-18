# stop_sandbox.ps1

## 职责

停掉本机沙盒。默认只停我们自己起的三个（发布器、amqtt broker、HA 容器），刻意保留 SimuHome API——它启动慢，留着下次可以直接重启链路。

## 输入

```text
-StopSimuHome    连 SimuHome API 一起停
```

## 输出

```text
已停 <命令行特征>（PID N）        每个被杀的进程一行
docker compose ... stop 的输出    HA 容器停止信息
```

## 读取

进程列表（按命令行特征匹配 `*publisher.py*` 与 `*run_broker.py*`，以及 `*src.simulator.api.app*`）。

## 写入

```text
Stop-Process -Force 杀掉匹配到的进程
docker compose -f _work\ha\compose.yaml stop
```

## 不负责

不停 Docker 引擎本身，不删容器，不清理 retained 消息，不清空数据目录。要彻底回滚沙盒状态得另做（重启 broker 后 retained 自然消失）。

## 失败时返回什么

杀进程带 `-ErrorAction SilentlyContinue`：目标已经不在时静默跳过，不报错。命令仍然成功返回。

## 注意

脚本内部把 `HA_CONFIG_DIR` 设成 `D:\homeassistant-sandbox`，因为 compose 文件里那个 `${HA_CONFIG_DIR:?…}` 是必填项，不设会直接报错。

## 对应文件

```text
_work\stop_sandbox.ps1         本文件
_work\start_sandbox.ps1        启停的另一半
_work\ha\compose.yaml          被 stop 的 compose 文件
```
