# memory.yaml

MCP server 的长期记忆文件，`memory` 工具读写的就是它。路径由 `_work\mcp\config.yaml` 的 `memory.file` 指定。

## 当前内容

```text
0 字节（空文件）
```

## 数据结构

整段文本，读写同构：`memory` 工具的 `write` 直接覆盖整段内容，`read` 整段返回。上限由配置控制——`max_write_tokens: 200` 写入硬上限（超过返回 `BAD_REQUEST`），`max_read_tokens: 300` 超出按内部策略截断。

## 为什么现在是空的

`_work\llm\test_llm_surface_local.py` 跑测试时会把记忆文件指向临时目录（`write_temp_config()` 覆写 `memory.file`），跑完连临时目录一起删掉，所以这里的记忆不会被测试污染。上一次真写入的内容只存在于那次运行的临时目录里。

## 被 git 忽略

`_work\.gitignore` 里的 `data/` 规则把它排除，不进仓库。

## 对应文件

```text
_work\mcp\data\memory.yaml    本文件
_work\mcp\config.yaml          memory.file 指向本文件
```
