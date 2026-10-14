# `_tools/mcp_probe.py` 说明

## 功能

一个统一的 MCP 探针：连上任意 MCP server，列出它的三个能力面（tools / prompts / resources），
可选再调一个工具。用来横向对比不同接入方案的工具面，不用为每个项目写一份客户端。

```text
输入   --http <URL> 或 --stdio "<命令行>"（二选一）
       --token-file（默认 ..\_secrets\ha_token.txt，只有 HTTP 传输会带 Authorization 头）
       --call <工具名> --args '<JSON>'（可选）
       --args-file <路径>（可选，替代 --args；PowerShell 传带引号的 JSON 容易被打散时用）
输出   工具清单（名字 / 参数 / 必填 / 描述首行）、提示与资源清单、可选的工具调用结果
读取   令牌文件；stdio 模式下继承当前环境变量（社区 server 多靠环境变量拿 HA 地址与令牌）
写入   无（探针本身只读；被探的 server 可能写设备，取决于你调哪个工具）
不负责   不评估模型、不做任务编排、不记录耗时统计（那些属于对比实验的脚本）
对应   _tools\mcp_probe.py
```

## 两种传输

```text
stdio             在本地起子进程当 server：--stdio "uvx hass-mcp"
                  env 里要给社区 server 需要的变量（比如 HA_URL / HA_TOKEN）
streamable HTTP   连远端端点：--http http://localhost:8123/api/mcp
                  走 HA 官方 MCP Server 集成时，会带 HA 长期令牌
```

## 已知坑：本机系统代理

本机开着系统代理（`127.0.0.1:7897`）时，httpx 会把发往 `localhost` 的请求也交给代理，
结果拿到 502 bad gateway。探针在启动时把 `localhost / 127.0.0.1 / ::1` 写进 `NO_PROXY`，
stdio 子进程也继承这个设置；如果你的环境另有代理，按同样思路处理。

## 用法

```powershell
cd D:\D_coderesource\simuhome

# HA 官方 MCP Server（Streamable HTTP）
C:\ProgramData\anaconda3\python.exe _tools\mcp_probe.py --http http://localhost:8123/api/mcp

# 社区 stdio server（先把环境变量给足）
$env:HA_URL = "http://localhost:8123"; $env:HA_TOKEN = (Get-Content ..\_secrets\ha_token.txt -Raw).Trim()
C:\ProgramData\anaconda3\python.exe _tools\mcp_probe.py --stdio "uvx hass-mcp"

# 调一个只读工具看链路是否通
C:\ProgramData\anaconda3\python.exe _tools\mcp_probe.py --http http://localhost:8123/api/mcp `
    --call GetLiveContext --args "{}"
```
