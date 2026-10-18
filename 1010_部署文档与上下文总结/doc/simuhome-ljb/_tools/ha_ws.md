# ha_ws.py 说明

## 功能

用 `_secrets/ha_token.txt` 里的长期令牌连上 HA 的 WebSocket API，执行一条命令并打印结果。
HA 的设备注册表、区域注册表、实体注册表只有 WebSocket 命令能读，REST 没有对应端点，所以需要这个工具。

## 用法

```powershell
C:\ProgramData\anaconda3\python.exe _tools\ha_ws.py config/area_registry/list
C:\ProgramData\anaconda3\python.exe _tools\ha_ws.py config/device_registry/list
C:\ProgramData\anaconda3\python.exe _tools\ha_ws.py config/entity_registry/list --full
C:\ProgramData\anaconda3\python.exe _tools\ha_ws.py config/area_registry/delete '{\"area_id\":\"chu_fang\"}'
```

## 输入 / 输出

```text
输入   HA 长期令牌（读 _secrets\ha_token.txt）、WS 命令名与 JSON 参数
输出   列表类命令打印条数与前 3 条（加 --full 打印全部）；其它命令打印结果摘要
```

## 注意

```text
只读命令可以随便跑；delete / update 这类会改 HA 配置，执行前先确认参数
令牌失效时抛“认证失败”，此时需要重新生成令牌
```
