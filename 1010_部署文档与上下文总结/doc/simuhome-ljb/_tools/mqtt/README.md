# _tools/mqtt

用途：为"方案 A（MQTT discovery）"准备并验证 broker。本机 Docker Hub 不通，所以走两条本地可行的路。

## 目录内容

| 文件/目录 | 说明 |
| --- | --- |
| `mosquitto-2.0.20-install-windows-x64.exe` | Mosquitto 官方 Windows 安装包（27 MB，来自 mosquitto.org），需要管理员权限安装 |
| `wheels\` | amqtt（Python broker）、paho-mqtt（客户端）及其依赖的离线 wheel 包，共 23 个 |
| `probe_mqtt.py` | 可用性探针：本机起 amqtt broker，量"发布 → 订阅"的延迟与吞吐 |

## 为什么要有这个目录

```text
Docker Hub（registry-1.docker.io）在本机不通 → eclipse-mosquitto 镜像拉不下来
ghcr.io 公共镜像可用，但 HA 的 mosquitto add-on 镜像返回 denied
PyPI 可用 → amqtt 与 paho-mqtt 能装
mosquitto.org 可用 → Windows 原生安装包能下
两条路都留着，用哪条由部署形态决定
```

## 运行探针

```powershell
C:\ProgramData\anaconda3\python.exe "D:\D_coderesource\simuhome\_tools\mqtt\probe_mqtt.py"
```

探针会在 127.0.0.1:18830 起一个临时 broker，跑完自动关掉，不常驻。

实测结果（2026-09-17，amqtt 0.12.1，qos=0）：

```text
延迟   平均 1.10 ms ｜ 中位 1.08 ms ｜ p95 1.30 ms ｜ 最大 1.36 ms（n=50）
吞吐   连发 500 条约 0.17 秒，约 2900 条/秒
对比   SimuHome 自己的 API 单次往返约 100 ms（受 0.1 秒 tick 限制），
       所以 broker 这一跳对端到端延迟没有实际影响；我们的负载约 25 条/秒，余量充足
```

启动时会打印两条 amqtt 自带的配置提示（`password-file not found`、`sys_interval not set`），
属于它内部插件的默认值告警，探针功能不受影响。

## 安装方式（二选一）

```text
方式 1  Python broker（已装）
        pip install --no-index --find-links wheels amqtt paho-mqtt websockets
        已装进 anaconda：amqtt 0.12.1、paho-mqtt 2.1.0、websockets 15.0.1

方式 2  Mosquitto 原生版（需管理员）
        运行 mosquitto-2.0.20-install-windows-x64.exe，之后在 1883 端口常驻
        适合作为长期测试床的 broker：性能更好、与 HA 官方文档一致
```
