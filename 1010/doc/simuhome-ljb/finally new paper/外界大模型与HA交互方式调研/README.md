# 外界大模型与 HA 交互方式调研

```text
01_现存控制方式分析.md   六条控制路线的拆解与对比：HA 内置对话代理、官方 MCP Server、
                        社区 MCP Server、HA 当 MCP 客户端、直接 REST/WS、非 LLM 传统通道

事实来源
  本地源码   ha_core_official\core\（dev 2026.7.0.dev0）里的 mcp_server / mcp / llm / 对话类集成
  本机实测   运行中的容器是 2026.6.4，官方 MCP 端点与 Assist 定位方式在
             ..\HomeAssistant双仓库接口分析\02 与 03 号文档里有实测记录
  社区现状   GitHub 搜索（2026-09-18 快照，星数与项目状态会变）

为什么不重复写 03 号文档
  03 号是"SimuHome 的 20 个工具 → 收敛到 10 个核心"的接口梳理；本文是"外界大模型
  能用什么方式控制 HA"的路线盘点，回答的是选型问题，两份互相引用、不重叠。
```
