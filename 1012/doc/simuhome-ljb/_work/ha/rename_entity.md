# rename_entity.py

## 职责

改 HA 里的 `entity_id` 与友好名，走 WebSocket 的 `config/entity_registry/update`。

为什么需要这一步：HA 2026.5.4 的 MQTT discovery 不认 `object_id` 键，实体 id 由「区域 + 设备名 + 实体名」自动拼，中文名会被拼音化并重复两遍（实测得到 `switch.lan_ya_yin_xiang_lan_ya_yin_xiang`）。沙盒发布器发出的 25 个实体必须先跑 `simuhome_mqtt_publisher\publisher\rename_entities.py` 批量改名，个别漏网的就用这个脚本单独修。

## 输入

```text
argv[1]   旧 entity_id（必填）
argv[2]   新 entity_id（必填）
argv[3]   友好名（可选，给了才改）
令牌      _secrets\ha_token.txt

例：python _work\ha\rename_entity.py switch.lan_ya_yin_xiang_lan_ya_yin_xiang switch.bt_speaker 蓝牙音箱
```

## 输出

```text
成功   一行 "已改：<旧> → <新>（友好名 <名>）"，退出码 0
用法错 打印 docstring，退出码 2
失败   错误信息写 stderr，退出码 1
```

## 读取

`_secrets\ha_token.txt` 与命令行参数。

## 写入

HA 的实体注册表（entity_id 可能变，友好名可能变）。

## 不负责

不批量改（批量改名用仓库里的 `rename_entities.py`），不改设备注册表，不改实体所属区域。

## 失败时返回什么

```text
认证失败   stderr "认证失败"，退出码 1
改名失败   stderr 打印 HA 返回的 error JSON，退出码 1
```

## 对应文件

```text
_work\ha\rename_entity.py                                本文件
simuhome_mqtt_publisher\publisher\rename_entities.py      沙盒 25 实体的批量改名（仓库只读文件）
_work\02_本机部署记录.md                                    第 5 节说明这一步为什么不能省
```
