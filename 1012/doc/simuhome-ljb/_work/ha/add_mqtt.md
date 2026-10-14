# add_mqtt.py

## 职责

通过 config flow 的 REST 接口，给沙盒 HA 添加 MQTT 集成。HA 的 MQTT 集成只能走 config flow（YAML 配置早就取消了），所以这里模拟浏览器逐步提交表单。

HA 容器在 Docker 里，所以 broker 地址填 `host.docker.internal:1883`，经它以宿主回环访问本机的 amqtt。

## 输入

```text
命令行     无参数
令牌       _secrets\ha_token.txt
待填值     模块顶部的 VALUES 字典（broker / port / discovery / discovery_prefix / keepalive / tls …）
```

## 输出

```text
stdout     每步打印 "步骤：<step_id>（<type>）" 与本次提交的字段
           成功后打印 "已创建集成：host.docker.internal"
HA 侧      新增一条 mqtt 集成条目
```

## 读取

`_secrets\ha_token.txt`；以及上一步 config flow 返回的 `data_schema`（字段名从它推）。

## 写入

向 HA 的 config flow 接口 POST，最终落成一条集成条目。

## 调用顺序

```text
POST /api/config/config_entries/flow            起一个 handler=mqtt 的流程
循环最多 6 次：
  取 data_schema 里的字段名 → 只填 VALUES 里认识的 → 提交到
  POST /api/config/config_entries/flow/{flow_id}
  遇到 type=create_entry 结束
```

`field_names()` 同时兼容 `data_schema` 的两种形状：列表（每项带 `name`）与对象（带 `properties`）。

## 不负责

不生成 MQTT 账号密码（本机 amqtt 允许匿名，username/password 留空），不装接收端，不校验实体是否出现。

## 失败时返回什么

`call()` 把 HTTPError 包装成 `RuntimeError("<path> -> HTTP <code>: <响应体>")`，响应体会原样带出来。schema 里出现 VALUES 不认识的字段时打印 `未知字段，脚本不认识：[…]`，然后照常提交（该字段不会出现在 payload 里）。步数超过 6 步会打印截断的 flow 内容并停下。

## 对应文件

```text
_work\ha\add_mqtt.py       本文件
_work\ha\onboard.py        前置：先有令牌
_work\ha\compose.yaml      它连的那个 HA
_work\broker\run_broker.py 它连的那个 broker
_work\02_本机部署记录.md     第 3 节
```
