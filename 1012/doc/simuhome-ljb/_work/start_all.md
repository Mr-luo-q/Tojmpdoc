# start_all.ps1

## 职责

把本机整条链**按依赖顺序、幂等地**拉起来。每一段先看"是不是已经在跑"，
在跑就跳过，所以重复执行是安全的。顺序有依赖，不能乱：

```text
Docker / HA
   └─> MQTT broker（amqtt，127.0.0.1:1883）
          └─> SimuHome API（127.0.0.1:8000，必要时载入 home_full.json）
                 └─> 发布器（SimuHome -> MQTT discovery/状态）
                        └─> 蓝牙音箱桥（HA 实体 -> 本机出声）
```

背景：之前这些进程是各起各的，只有 HA 靠 Docker 的 `unless-stopped` 自愈；
broker / SimuHome / 发布器 / 桥都是宿主机上的普通 Python 进程，没有自启。
这个脚本就是把这些"手动活"合并成一次调用。

## 输入

```text
-ResetHome    可选；强制把 SimuHome 重置回 home_full.json 初始状态
固定路径       HA 配置 D:\homeassistant-sandbox；Python 用 D:\Anaconda\python.exe；
              SimuHome 在 D:\Simuhome\SimuHome（用它自己的 .venv）
```

## 输出

每段打一行进度，末尾汇总：

```text
[1/6] HA reachable: True
[2/6] broker 1883 ready: True
[3/6] SimuHome ready: True  rooms=3
[6/6] summary:
  rooms = 3
  _work\broker\run_broker.py   PID 1234
  src.simulator.api.app        PID 2345
  publisher\publisher.py       PID 3456
  bt_speaker\bridge.py         PID 4567
  bt_speaker entities = 2
  simuhome entities = 25, unavailable = 0
```

## 读取 / 写入

读 Docker 状态、HA 8123、SimuHome 8000、broker 1883、HA 实体列表。
写入：起进程（后台隐藏窗口），各进程日志落在 `_work\logs\` 与 `_work\bt_speaker\logs\`。

## 不负责

不装 SimuHome、不装依赖、不生成 MQTT 账号、不在 HA 里加 MQTT 集成——
那些一次性前置仍按 `deploy\03_沙盒全链路部署.md` 做。也不做音箱的蓝牙配对。

## 失败时返回什么

每段独立、失败不中断；末尾汇总里能看到哪个进程 `NOT running`，
以及 SimuHome 房间数、HA 实体数与 unavailable 数，照着补即可。

## 为什么脚本正文是 ASCII

与 `_work\bt_speaker\relink_a2dp.ps1` 同理：仓库的 `.ps1` 约定存带 BOM 的 UTF-8，
补丁工具生成的脚本带不上 BOM，PowerShell 5.1 会按本地代码页读无 BOM 文件，
所以正文只写 ASCII，中文说明放这份 md。

## 对应文件

```text
_work\start_all.ps1            本文件
_work\broker\run_broker.py     它拉起的 broker
_work\bt_speaker\bridge.py     它拉起的音箱桥
simuhome_mqtt_publisher\publisher\publisher.py   它拉起的发布器
deploy\03_沙盒全链路部署.md     各段的一次性前置
```
