# smoke.py

## 职责

用 MCP 客户端连本机 server，跑一遍只读冒烟：列工具 → `observe_home` → `inspect_device`。可选地再执行一个动作，用来验证端到端写路径。

## 输入

```text
argv[1]   device_id，默认 cn_911432173
argv[2]   动作名（可选，给了才会执行）
argv[3]   动作参数 JSON（可选，默认 {}）
令牌      _secrets\ha_token.txt

例：python smoke.py fridge_cold
    python smoke.py speaker turn_on
```

## 输出

```text
工具面: [8 个工具名]
== observe_home ==                格式化后的 JSON
== inspect_device(<id>) ==        格式化后的 JSON，失败时打印"调用失败"与 error 段
== execute_action(...) ==         仅当给了 argv[2]
```

## 读取

`_secrets\ha_token.txt`；同目录的 `config.yaml`；HA 的实体与注册表（经 MCP server）。

## 写入

默认无。给了 argv[2] 时会真的下发一次控制命令，可能改变设备状态。

## 已知问题

默认 `device_id` 还是旧的 `cn_911432173`，而现在别名表里的设备 id 是 `fridge_cold` / `fridge_freeze`，所以不带参数跑 `inspect_device` 会返回 `UNKNOWN_DEVICE`。要读冰箱请显式传 `fridge_cold`。

## 不负责

不做断言、不算通过率、不还原设备状态（这是它和 `_work\llm\test_llm_surface_local.py` 的分工差别：那个测试负责核对与还原，这个只负责"能连上、能看到什么"）。

## 失败时返回什么

工具调用失败时打印"调用失败"并把 HA 返回的 error 段打出来，进程仍以 0 退出。连接层失败以 traceback 结束。

## 对应文件

```text
_work\mcp\smoke.py                        本文件
_work\mcp\config.yaml                     它用的配置
_work\llm\test_llm_surface_local.py       带断言的 12 项版本
```
