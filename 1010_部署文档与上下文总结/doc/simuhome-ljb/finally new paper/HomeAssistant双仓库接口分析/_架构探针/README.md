# 架构探针（临时验证，不是实现）

用途：用最小可运行骨架**实测**上一版架构的解耦程度，而不是靠嘴判断。
目录名前面加了 `_`，表示它是一次性验证物，验证完可以整体删掉。

```text
它验证什么
  P1 包内依赖方向：是否单向、有无环
  P2 协议壳是否泄漏后端词汇（server.py 里不许出现 ha / entity / domain / service）
  P3 换后端是否只改入口：跑 ha 与 fake 两个后端，比对文件哈希与工具表
  P4 契约是否被强制：后端少实现一个工具时能否在启动期报错
  P5 同一套契约测试能否在两个后端上复用
  P6 配置是否能用 ${VAR} 占位符（不用自定义 YAML tag）
```

每个文件的职责（代码与文档一一对应，按仓库规则合并写在本文件里）：

| 文件 | 职责 | 输入 | 输出 |
| --- | --- | --- | --- |
| `src/home_mcp/errors.py` | 统一错误类型 | 无 | `MissingToolsError` |
| `src/home_mcp/contract/__init__.py` | 契约层：工具定义与条件求值，只依赖标准库 | 无 | `TOOLS`、`missing_tools()`、`evaluate_condition()` |
| `src/home_mcp/server.py` | 协议壳：只认契约与注入的后端 | 后端工具表 | 校验通过的工具表 |
| `src/home_mcp/runtime.py` | 配置加载，支持 `${VAR}` 替换 | YAML 文件路径 | dict |
| `src/home_mcp/backend_ha/__init__.py` | HA 后端（探针里用假数据） | 工具参数 | 与契约一致的返回 |
| `src/home_mcp/backend_fake/__init__.py` | 第二个后端，用来验证可替换性 | 工具参数 | 同上 |
| `src/home_mcp/entry.py` | 入口：读环境变量选后端并组装 | `HOME_MCP_BACKEND` | 启动结果 |
| `probe.py` | 跑 P1~P6 并打印报告 | 无 | 控制台报告 |

```text
运行
  cd "D:\D_coderesource\simuhome\finally new paper\HomeAssistant双仓库接口分析\_架构探针"
  C:\ProgramData\anaconda3\python.exe probe.py
```
