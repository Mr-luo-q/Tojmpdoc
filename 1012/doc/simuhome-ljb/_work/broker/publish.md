# publish.py

## 职责

往本机 broker 手工发一条 MQTT 消息。排查与测试用：验证订阅方有没有收到、清掉某个主题的 retained 值、手工触发一次桥的动作。

## 输入

```text
argv[1]   topic
argv[2]   payload（可省略，省略时发空串）
argv[3+]  --retain 出现即带 retain 标志

例：python _work\broker\publish.py bt_speaker/v1/set ON
    python _work\broker\publish.py bt_speaker/v1/set ""      # 清掉该主题的 retained
```

## 输出

```text
stdout   一行 "已发布 topic=... payload=... retain=..."
无参数时  打印模块 docstring 作为用法说明后以非 0 退出
```

## 读取

命令行参数。

## 写入

```text
broker 127.0.0.1:1883   指定 topic 上的一条消息
```

## 实现要点

```text
连接后先 loop_start() 再 sleep(0.5) 才 publish，然后 sleep(0.8) 才断开：
这两段等待是给 paho 的网络线程留出发送窗口，否则进程可能在消息出网前就退出
client_id 固定为 "probe-publish"，便于在 broker 日志里辨认
```

## 不负责

不做鉴权（连的是本机匿名 broker），不订阅，不等待对方确认，不做批量发送。

## 失败时返回什么

连不上 broker 时 paho 抛 `ConnectionRefusedError`，进程以 traceback 结束。发布本身不校验接收方是否存在。

## 对应文件

```text
_work\broker\publish.py    本文件
_work\broker\peek.py       反向操作：看 broker 上有什么
_work\bt_speaker\bridge.py  常见接收方之一（订阅 bt_speaker/v1/set）
```
