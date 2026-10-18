# `_tools/mcp_write_settle.py` 说明

## 功能

量一件事：**MCP 的写调用多久返回，和世界状态多久真正变过来，差多少**。

为什么值得单独量：B（官方 MCP）与 C（社区 MCP）都不做写后回读，工具一返回就结束了。
如果端侧模型紧接着去读状态，会读到"还没变"的旧值，于是要么误判自己失败，要么继续重试。

```text
输入   --http 或 --stdio（二选一，和 mcp_probe 一致）
       --entity <实体 id>（要观察的实体）
       --on-tool / --on-args-file    打开用的工具与参数
       --off-tool / --off-args-file  还原用的工具与参数
       --token-file（读状态用，默认 ..\_secrets\ha_token.txt）
输出   调用耗时、isError、状态落定耗时（轮询 HA 每 50 ms 一次）、还原是否成功
写入   会真的开一次、再关一次（等价于一次受控实验，跑完自动还原）
不负责   不做平均统计（要跑多轮就在外面循环）
对应   _tools\mcp_write_settle.py
```

## 用法

```powershell
# B 官方 MCP：按名字 + 区域开/关客厅侧灯
python _tools\mcp_write_settle.py --http http://localhost:8123/api/mcp `
    --entity switch.simuhome_living_room_side_light `
    --on-tool HassTurnOn  --on-args-file on.json `
    --off-tool HassTurnOff --off-args-file off.json

# C 社区 hass-mcp：按 entity_id 开/关
python _tools\mcp_write_settle.py --stdio "$env:USERPROFILE\.local\bin\uvx.exe hass-mcp" `
    --entity switch.simuhome_living_room_side_light `
    --on-tool entity_action  --on-args-file c_on.json `
    --off-tool entity_action --off-args-file c_off.json
```

参数文件里放 JSON（PowerShell 5.1 传带引号的 JSON 会被打散，所以一律走文件）：

```json
// on.json（B）
{"name": "On/Off Light On/Off Light", "area": "living_room"}
// c_on.json（C）
{"entity_id": "switch.simuhome_living_room_side_light", "action": "on"}
```
