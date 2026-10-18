# start_sandbox.ps1

## 职责

一键拉起本机沙盒全链路：Docker 引擎与 HA 容器 → SimuHome API → 载入 home → MQTT broker → 发布器 → 汇总核对。每一步幂等，已经在跑的就跳过。

## 为什么另起一份

仓库的 `_tools\start_simuhome_stack.ps1` 把两处写死了：SimuHome 路径固定成 `simuprocject\Simuhome_experiment`，broker 固定成原生 Mosquitto。这台机器两条都对不上（SimuHome 在 `D:\Simuhome\SimuHome`，broker 是 amqtt）。按 AGENTS.md 的隔离要求没有去改它，而是另写这份指向实际路径。

## 输入

```text
命令行    无参数
环境变量  HA_CONFIG_DIR 由脚本自己设为 D:\homeassistant-sandbox
依赖      PATH 里有 python；docker 可用
```

## 输出

```text
logs\broker.out.log / broker.err.log             amqtt 的输出
logs\simuhome-api.out.log / .err.log             SimuHome API 的输出
simuhome_mqtt_publisher\logs\publisher.console.err.log   发布器的输出（由仓库脚本写）

stdout 末尾汇总：
  SimuHome 房间数   3（应为 3）
  broker 端口 1883  True
  发布器进程        运行中
  HA 实体           25 个（应为 25），其中 unavailable 0 个
```

## 读取

```text
D:\Simuhome\SimuHome\home_full.json            房间数为 0 时用来载入
_secrets\ha_token.txt                          读 HA 实体数用
_work\ha\compose.yaml                          起 HA 容器
simuhome_mqtt_publisher\publisher\start_publisher.ps1   仓库的发布器启动脚本
```

## 写入

```text
启动顺序（有依赖，不能乱）
  1  Docker 引擎 → HA 容器
  2  SimuHome API :8000
  3  房间数为 0 时 POST home_full.json 载入
  4  MQTT broker :1883（amqtt）
  5  发布器（用仓库自己的 start_publisher.ps1）
  6  汇总核对
```

## 不负责

不起蓝牙音箱桥（那个由 `bt_speaker\start_bridge.ps1` 单独起），不装集成，不签发令牌，不做停止操作（停止用 `stop_sandbox.ps1`）。

## 失败时返回什么

```text
找不到 python     Write-Error 后 exit 1
各等待步骤        都是"等到超时为止"，超时后继续往下走，不中断
末尾汇总          以实际观察值打印，是否达标由人判断（没有以退出码表达）
```

## 注意

脚本不要接管道。发布器的启动脚本会留下长命子进程，子进程继承管道写端，接了会挂住。

## 对应文件

```text
_work\start_sandbox.ps1        本文件
_work\stop_sandbox.ps1         停止
_work\ha\compose.yaml          它起的 HA
_work\broker\run_broker.py     它起的 broker
_work\02_本机部署记录.md         首次跑通时的记录与差异说明
```
