# `_tools/mcp_surface_bench.py` 说明

## 功能

量一个 MCP server 的"接口面开销"：端侧模型每轮都要背的工具清单有多大、
单次读操作吐多少字、错误信息有多长、每次调用耗时多少。

```text
输入   --profile b|c|e（三套预设调用档案）+ --http 或 --stdio
       --token-file（HTTP 传输用，默认 ..\_secrets\ha_token.txt）
       --out <json 路径>（可选，落明细）
输出   控制台摘要：工具数 / 工具面字节与估算 token / 必填为空的工具数 / 带约束的工具数 /
       提示与资源体量 / 每个调用的状态、耗时、字节、token 与说明
读取   HA（经被测 server）；令牌文件
写入   只调档案里列的只读或"安全错误"调用；不写设备
不负责   不接模型、不判任务成功率（那是下一步的对照实验）
对应   _tools\mcp_surface_bench.py
```

## 三套档案

```text
b  官方 MCP Server  GetLiveContext（全屋上下文）+ HassTurnOn 传一个不存在的名字（看错误输出体量）
c  社区 hass-mcp    list_entities / get_entity（正常）+ get_entity 传不存在的实体（看错误输出体量）
e  我们的 MCP       observe_home / inspect_room / inspect_device + execute_action 传不存在的设备
```

`estimate_tokens` 是粗略估算（中日韩字符按 1.5 字/词、其余按 4 字/词），
只用来横向比较量级，不当作精确计费口径。

## 用法

```powershell
cd D:\D_coderesource\simuhome

# B 官方 MCP
C:\ProgramData\anaconda3\python.exe _tools\mcp_surface_bench.py --profile b `
    --http http://localhost:8123/api/mcp --out "finally new paper\外界大模型与HA交互方式调研\_measure\b.json"

# C 社区（先给 HA_URL / HA_TOKEN 环境变量）
$env:HA_URL="http://127.0.0.1:8123"; $env:HA_TOKEN=(Get-Content _secrets\ha_token.txt -Raw).Trim()
C:\ProgramData\anaconda3\python.exe _tools\mcp_surface_bench.py --profile c `
    --stdio "$env:USERPROFILE\.local\bin\uvx.exe hass-mcp"

# E 我们自己
$env:PYTHONPATH="ha_mcp_server\src"
C:\ProgramData\anaconda3\python.exe _tools\mcp_surface_bench.py --profile e `
    --stdio "C:\ProgramData\anaconda3\python.exe -m home_mcp.entry --config ha_mcp_server\config.yaml"
```

注意：本机开着系统代理时，httpx 会把 localhost 也代理掉（表现为 502），
脚本启动时会自动把 `localhost / 127.0.0.1 / ::1` 写进 `NO_PROXY`。
