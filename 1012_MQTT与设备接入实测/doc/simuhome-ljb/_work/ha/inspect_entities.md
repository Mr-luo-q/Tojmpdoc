# inspect_entities.py

## 职责

盘一遍 HA 的集成条目与实体分布，按 platform 分组。装完小米集成后用它确认导入了多少设备、集成条目状态是否正常，也用来核对沙盒侧 MQTT 实体的数量。

## 输入

```text
命令行     无参数
令牌       _secrets\ha_token.txt
```

## 输出

```text
== 集成条目 ==        domain / title / state 三列
== 实体按 platform 分组 ==  按条数从多到少
== xiaomi_home 的实体（N 个）==   entity_id 与 unique_id
```

## 读取

走 WebSocket API：`config_entries/get`、`config/entity_registry/list`。注册表在 REST 上没有对应端点，所以这里必须用 WebSocket。

## 写入

无。纯只读。

## 不负责

不读实体状态（只读注册表，不含当前值），不改名，不删除任何条目。`xiaomi_home` 段是硬编码的过滤条件，换成别的集成需要改代码。

## 失败时返回什么

```text
认证失败   SystemExit("认证失败")
命令失败   RuntimeError(HA 返回的 error 对象)
```

## 对应文件

```text
_work\ha\inspect_entities.py     本文件
_work\ha\rename_entity.py        改名（本脚本发现问题后的下一步）
_work\ha\xiaomi_options.py       刷新小米设备列表
```
