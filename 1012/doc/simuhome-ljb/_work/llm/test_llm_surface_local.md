# test_llm_surface_local.py

这是 `ha_mcp_universal\tests\test_llm_surface.py` 的可运行副本，存在的唯一理由是让这个测试在不往仓库源目录写文件的前提下跑起来（AGENTS.md 第 1 条）。

```text
原始文件（只读）   ha_mcp_universal\tests\test_llm_surface.py
本副本            _work\llm\test_llm_surface_local.py
```

## 与原始文件的差异

只有两行，其余逐字相同。另有文件开头一段副本说明注释。

```text
原始  PROJECT_ROOT = Path(__file__).resolve().parents[1]
副本  PROJECT_ROOT = Path(r"D:\项目\simuhome-ljb\ha_mcp_universal")
      原因：副本不在 ha_mcp_universal 下，parents[1] 会指到 _work，
            进而让 sys.path、REPO_ROOT、tokens 路径全部指错

原始  temp_config = PROJECT_ROOT / "config.live_surface_test.yaml"
副本  temp_config = tmpdir / "config.live_surface_test.yaml"
      原因：原始会把临时配置写进 ha_mcp_universal\，
            在源目录里留下 config.live_surface_test.yaml
```

核对方式：`git diff --no-index` 两份文件，输出为 8 处新增（开头注释 + 两处替换行）与 2 处删除。

## 职责

用真实模型经 stdio 连自建 MCP server，验证模型能否正确调用 8 个工具。模型只负责发工具调用，脚本负责核对调用序列、核对设备的真实状态、并把设备还原。

```text
三组任务
  A 组  时间 + 设备 + 立即执行   observe_home → inspect_room → inspect_time
                                 → inspect_device → execute_action(turn_on)
  B 组  记忆读写                 memory(write) → memory(read)
  C 组  预约 + 取消 + 收尾       time_control(schedule→list→cancel→list) → finish
```

## 输入

```text
环境变量   DEEPSEEK_API_KEY       必填
           DEEPSEEK_BASE_URL      可选，默认 https://api.deepseek.com
           DEEPSEEK_MODEL         可选，默认 deepseek-flash
           DEEPSEEK_THINKING      可选，默认 disabled
           HA_TOKEN               未设时读 _secrets\ha_token.txt
命令行     --config <MCP 配置路径>  默认取 ha_mcp_universal\config.yaml
工作目录   需要能解析配置里的相对路径；本项目在 _work\mcp 下运行
```

## 输出

stdout 逐条打印 12 项检查并给出总结；退出码 0 表示全通过，1 表示有失败项。

## 读取

`--config` 指向的 MCP 配置；HA 的实体状态与注册表（经 MCP server）；模型返回的工具调用与文本。

## 写入

只写系统临时目录（记忆文件、预约库、临时配置，跑完删除）。设备侧会真实下发一次 `execute_action`，本测试的目标是沙盒设备 `living_room_side_light`，脚本跑完把状态还原。

## 不负责

不测 B/C 路线，不碰真机设备，不改 HA 配置，不往仓库任何目录写文件，不做性能基准。

## 失败时返回什么

单项不通过则该行标 `[失败]` 并在结尾汇总，退出码 1。依赖级异常（例如库版本不兼容）直接抛 traceback，不静默降级——本次就是靠 traceback 定位到 Brotli 版本问题。

## 运行方式

```powershell
$env:DEEPSEEK_API_KEY = "<密钥>"
$env:DEEPSEEK_MODEL   = "deepseek-flash"
$env:DEEPSEEK_THINKING = "disabled"
Set-Location <repo>\_work\mcp
python <repo>\_work\llm\test_llm_surface_local.py --config <repo>\_work\mcp\config.yaml
```
