# test_llm_fridge_local.py

这是 `ha_mcp_universal\tests\test_llm_fridge.py` 的可运行副本。

```text
原始文件（只读）   ha_mcp_universal\tests\test_llm_fridge.py
本副本            _work\llm\test_llm_fridge_local.py
```

## 与原文的差异

三处，其余逐字相同。另有文件开头一段副本说明注释。

```text
原始  PROJECT_ROOT = Path(__file__).resolve().parents[1]
副本  PROJECT_ROOT = Path(r"D:\项目\simuhome-ljb\ha_mcp_universal")
      原因：副本不在 ha_mcp_universal 下，parents[1] 会指到 _work，
            连带 sys.path、PYTHONPATH、以及 .env 与 _secrets 的查找路径全错

原始  COLD_DEVICE = "cn_911432173_cold"        ← 原文那台机器的别名
副本  COLD_DEVICE = "fridge_cold"              ← 本机别名表里的 id

原始  FREEZE_DEVICE = "cn_911432173_freeze"
副本  FREEZE_DEVICE = "fridge_freeze"
```

核对方式：`git diff --no-index` 两份文件，输出只有这三行替换加开头注释。跑前也用只读探针确认过 `fridge_cold` 可用（返回 `ok: true`，target 8 / current 6，范围 2~8）。

## 职责

让 DeepSeek 经我们自建的 MCP server 去控制**真实米家冰箱**：把冷藏设定温度在 2 与 6 之间来回切换。

```text
一轮的流程
  1  脚本快照两个温区的当前设定值（冷藏 + 冷冻）
  2  把任务丢给模型：它自己决定调 inspect_device / execute_action
  3  脚本回读核实（不信模型的口头结论）
  4  无论模型跑成什么样，finally 里把两个温区还原成快照值
```

模型用的系统提示词是「你是家庭环境助手，通过工具读取和控制这个家。无论用户用什么语言提问，都用中文回答。」

## 输入

```text
环境变量   DEEPSEEK_API_KEY        必填，从 ha_mcp_server\.env 读
           DEEPSEEK_BASE_URL       默认 https://api.deepseek.com
           DEEPSEEK_MODEL          默认 deepseek-flash
           DEEPSEEK_THINKING       默认 disabled
           HA_TOKEN                未设时读 _secrets\ha_token.txt
命令行     --config <MCP 配置路径>
常量       ROUNDS = 3，TARGET_LOW/TARGET_HIGH = 2/6，MAX_TOOL_STEPS = 24
```

## 输出

```text
测试前：冷藏设定 / 冷冻设定
=== 工具调用序列 ===      逐条打印 工具名 / ok / verified / value / state_after
模型总结：<模型最后一句话>
模型跑完时：冷藏设定
已还原：冷藏设定 / 冷冻设定
六项检查的通过与否
结论：N / 6 项通过；退出码 0 = 全通过，1 = 有失败
```

## 读取

`ha_mcp_server\.env`、`_secrets\ha_token.txt`、`--config` 指向的 MCP 配置；冰箱两个温区的真实设定值。

## 写入

```text
真实冰箱   冷藏与冷冻的设定温度，一轮最多 6 次 set_temperature（3 轮 × 2 次）
           finally 里一定还原成测试前的值
MCP 数据   memory / schedules 用 --config 指定的那份配置，
           在本项目里落在 _work\mcp\data\（gitignored）
```

## 六项检查

```text
1  模型先查再动（调过 inspect_device）
2  对冷藏室至少写了 ROUNDS × 2 = 6 次
3  成功的写都 verified=true（失败重试不算失败）
4  写序列里 2 与 6 都出现过
5  脚本回读与模型最后一次写的一致
6  两个温区都还原成测试前的设定值
```

## 不负责

不测 B/C 路线，不改 HA 配置，不往仓库源目录写文件，不碰沙盒设备，不做性能基准。

## 失败时返回什么

单项不通过则该行标 `[失败]` 并在结尾汇总，退出码 1。`DEEPSEEK_API_KEY` 为空时打印提示并 `SystemExit(2)`。连接或库级异常直接抛 traceback，不静默降级。

## 运行方式

```powershell
Set-Location <repo>\_work\mcp
python <repo>\_work\llm\test_llm_fridge_local.py --config <repo>\_work\mcp\config.yaml
```

密钥已在 `ha_mcp_server\.env`，不需要额外设环境变量。

## 对应文件

```text
_work\llm\test_llm_fridge_local.py     本文件
_work\llm\test_llm_fridge_local.md     这份说明
_work\llm\test_llm_surface_local.py     同一套的 12 项版本（只碰沙盒设备）
_work\mcp\config.yaml                   --config 指向它
ha_mcp_server\.env                      密钥来源
deploy\04_米家真机接入.md                 第 4 节提到这个测试（6/6）
```
