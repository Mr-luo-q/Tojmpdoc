# peek.py

## 职责

只读探针：连上本机 broker，订阅 `homeassistant/#` 与 `simuhome/v1/#`，等若干秒后统计收到了哪些话题。用来确认发布器是否真的发出了 MQTT discovery、以及 retained 消息是否还在。

## 输入

```text
命令行    无参数
时长      固定 5 秒
```

## 输出

```text
总话题数 N
discovery 话题 M 条，状态话题 K 条
  前 20 条 discovery topic
  前 5 条 state topic
```

## 读取

broker `127.0.0.1:1883` 上两个通配订阅下的 retained 与实时消息。不读文件。

## 写入

无。纯只读，不影响任何设备状态。

## 不负责

不解析消息内容（只统计 payload 字节数），不区分 retained 与实时，不做长时间的持续监听（固定 5 秒窗口）。

## 失败时返回什么

连不上 broker 时抛异常退出。broker 在跑但没有任何话题时，输出「总话题数 0」，这通常说明发布器没启动或 HA 的 MQTT 集成没连上。

## 对应文件

```text
_work\broker\peek.py           本文件
_work\broker\probe_filter.py   另一个只读探针，验订阅过滤
simuhome_mqtt_publisher\publisher\publisher.py   这些 discovery 话题的生产者
```
