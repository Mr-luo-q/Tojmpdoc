# chat.py

## 职责

在终端里跟 DeepSeek 对话，让它经我们的 MCP 去读、去控 HA 里的设备。这是 E 路线最短的可用形态：模型在外部，工具由 MCP 提供，HA 只当被控后端。

## 它与仓库测试脚本的分工

```text
test_llm_surface_local.py   固定三组任务、带断言与通过率，用来回归
test_llm_fridge_local.py    固定任务、会写真冰箱并还原，用来验真机
chat.py                     没有断言，任务由你现场输入，用来试手感
```

## 输入

```text
键盘     一行中文或英文指令
         /tools  列出模型当前能用的工具
         /quit   退出（Ctrl+C、EOF 也可以）
配置     _work\mcp\config.yaml
密钥     ha_mcp_server\.env
令牌     _secrets\ha_token.txt
常量     MAX_TOOL_STEPS = 12（单轮工具调用上限）
         ALLOW_WRITE = True（改成 False 会把 execute_action 从工具面里摘掉，只读）
         WRITE_DENY = {"fridge_cold", "fridge_freeze"}（名单里的设备一律不下发写命令）
```

## 输出

```text
开场      模型名、思考模式、工具数量、写入开关
每轮      每次工具调用一行：工具名 / ok / args / verified / state_after / error
结尾      "模型> <回答>"
```

## 读取

`config.yaml`、`ha_mcp_server\.env`、`_secrets\ha_token.txt`；设备状态经 MCP 读取。

## 写入

`ALLOW_WRITE = True` 时，模型可以下发 `execute_action`，会真的改设备状态（含真冰箱）。每次调用都会打印出来。对话历史只存在内存里，不落盘。

`WRITE_DENY` 这一层是设备级的：命令在本地就被拦下，根本不进 MCP，模型会收到一个 `WRITE_DENIED` 的结构化错误并自行改口。它和 `ALLOW_WRITE` 分工不同——后者一关全关，前者只挡指定设备。

## 不负责

不做断言与通过率统计，不还原设备状态（要还原得自己再下一条指令，或者用那两个测试脚本），不落盘对话记录，不管多进程并发。

## 失败时返回什么

```text
密钥缺失     SystemExit，提示去 ha_mcp_server\.env 填
单轮异常     打印"调用失败：<类型>: <消息>"后继续下一轮，不退出
工具步数超限  回答位置返回"（工具调用超过 12 步，本轮提前结束）"
```

## 运行前提

在哪个目录调用都行。脚本内部的路径全部基于自身位置（绝对路径），MCP 子进程的 cwd 被固定成 `_work\mcp`，所以配置里的 `./data/...` 一律落在 `_work\mcp\data\`。

已实测：从仓库根目录用绝对路径调用，数据仍落在 `_work\mcp\data\`（`schedules.db-shm` 的写入时间随之更新），仓库根目录没有多出任何文件。

前提是沙盒链路在跑（HA :8123、SimuHome :8000、broker :1883、发布器）。没跑的话先执行 `_work\start_sandbox.ps1`。

## 实测（2026-10-12）

把三句话用管道喂进去，模型的工具选择与结果如下：

```text
你> 客厅侧灯现在开着吗？
   · inspect_room    ok=True  args={"room_id": "living_room"}
   · inspect_device  ok=True  args={"device_id": "living_room_side_light"}
模型> 客厅侧灯现在是开着的。

你> 把客厅侧灯关掉
   · execute_action  ok=True  args={"device_id": "living_room_side_light", "action": "turn_off"}
                     verified=True  after={"on": false}
模型> 客厅侧灯已关闭。

你> 把客厅侧灯打开
   · execute_action  ok=True  args={"device_id": "living_room_side_light", "action": "turn_on"}
                     verified=True  after={"on": true}
模型> 客厅侧灯已打开。
```

跑完复查 HA 里该实体的状态是 `on`，与跑之前一致。

### 拒写名单也验过

```text
你> 把冰箱冷藏室设定温度改成 6 度
   · observe_home    ok=True
   · inspect_device  ok=True  args={"device_id": "fridge_cold"}
   · execute_action  ok=False args={"device_id": "fridge_cold", "action": "set_temperature", "params": {"value": 6}}
                     error=WRITE_DENIED
模型> 冷藏室无法设定温度 —— 该设备在本机禁止写入名单里，命令没有下发。
      当前它处于「假日」模式，目标 8 度、实测 6 度。
```

事后核对 HA 里两条 `target_temperature`：冷藏 8、冷冻 -15，`last_changed` 仍停在 HA 重启那一刻，说明确实没有任何写命令落到冰箱上。

## 两个已修的坑

```text
SyntaxWarning: invalid escape sequence '\.'
  原因  build_client() 的普通文档串里写了 ha_mcp_server\.env
  处置  改成 r"""...""" 原始字符串

UnicodeEncodeError: 'utf-8' codec can't encode character '\udcae'
  现象  管道喂进去的中文在调用模型前就崩了
  原因  Windows 控制台默认 GBK，管道进来的 UTF-8 字节被按 GBK 解码成代理对
  处置  启动时把 sys.stdin / sys.stdout 切到 UTF-8（errors="replace"），
        并在读入后做一次 encode/decode 清洗，把残留代理对替换掉
```

## 对应文件

```text
_work\mcp\chat.py                       本文件
_work\mcp\config.yaml                   它读的配置
_work\mcp\smoke.py                      只读冒烟，不带模型
_work\llm\test_llm_surface_local.py     带断言的 12 项
_work\llm\test_llm_fridge_local.py      带真机写与还原的冰箱版
```
