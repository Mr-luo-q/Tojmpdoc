# probe_filter.py

## 职责

验证 broker 的订阅过滤行为：只订阅一个精确主题，看会不会收到别的主题的消息。

这个探针的价值在于抓到过真问题：amqtt 在投递 retained 消息时不按订阅过滤，只订阅 `bt_speaker/v1/set` 却收到了 59 条无关的 retained（全部 simuhome 的 discovery 与状态）。HA 之所以没暴露这个毛病，是因为它订的是 `homeassistant/#` 这类宽通配，收到无关消息也会忽略。

## 输入

```text
argv[1]   要订阅的精确主题，默认 bt_speaker/v1/set
时长      固定 8 秒
```

## 输出

```text
已订阅（精确主题）：<topic>
共收到 N 条
  [retained|live] <topic>  ::  <payload 前 60 字>
```

每条都标了是 retained 还是实时，方便区分"历史遗留"和"刚刚发生"。

## 读取

broker `127.0.0.1:1883`。

## 写入

无。纯只读。

## 不负责

不修 broker，不判定谁对谁错，只呈现事实。要在生产链路上规避这个行为，得靠订阅方自己校验 `message.topic`（`bt_speaker\bridge.py` 就是这么做的，不匹配就丢弃并计数）。

## 失败时返回什么

连不上 broker 时抛异常退出。收到 0 条也算正常结果（说明 broker 上确实没有可投递的 retained）。

## 对应文件

```text
_work\broker\probe_filter.py            本文件
_work\bt_speaker\bridge.py              受影响方之一，已加主题校验
_work\04_蓝牙音箱MQTT桥.md               第 8 节记录了这次发现的完整经过
```
