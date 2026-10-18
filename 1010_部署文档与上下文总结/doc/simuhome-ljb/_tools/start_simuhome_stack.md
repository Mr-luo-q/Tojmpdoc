# `_tools/start_simuhome_stack.ps1` 说明

## 功能

一键拉起 SimuHome 全链路，顺序有依赖，每步幂等：已在跑就跳过。

```text
输入   -ResetHome 开关（可选）：强制把 SimuHome 重置回 home_full.json 的初始状态
输出   各步进度 + 末尾汇总（房间数 / 各进程 / HA 实体数与 unavailable 数）
读取   _secrets\ha_token.txt（查 HA 实体）、simuprocject\Simuhome_experiment\home_full.json
       （SimuHome 上游源码不在仓库里，按 deploy\03 克隆）
写入   起 Docker Desktop、HA 容器、SimuHome API、mosquitto、发布器；必要时重置 SimuHome home
不负责   不跑验收测试（那是 ha_mcp_universal\tests\ 的事），不改 HA 配置
对应   _tools\start_simuhome_stack.ps1
```

## 前置

```text
① SimuHome 已克隆到 simuprocject\Simuhome_experiment（含 home_full.json，见 deploy\03）
② Mosquitto 已安装，且已跑过 broker\make_credentials.ps1 生成账号文件
③ HA 容器；不存在时脚本用 deploy\compose.yaml 建，需要先设环境变量：
   $env:HA_CONFIG_DIR = "D:\homeassistant\config"
```

## 顺序与依赖

```text
1 Docker Desktop → HA 容器 homeassistant → 等 :8123 返回 200
2 SimuHome API   → 等 :8000/api/__health__ 返回 200
3 载入 home      → GET /api/home/state 房间数为 0 时才 POST /api/simulation/reset
4 mosquitto      → 起 broker 并跑 health_check（:1883）
5 发布器          → 连 broker、发 discovery 与状态
6 汇总            → 25 个 simuhome 实体、0 个 unavailable 才算齐
```

## 为什么第 3 步不能省

SimuHome 重启后 `home` 是空的：`/api/home/state` 返回 0 个房间，
而设备级接口（`GET /api/devices/<id>/attributes`、`POST /api/devices/<id>/commands`）直接 404。
此时 HA 里的实体仍然在线（旧的 retained discovery 还在），写命令会被 HA 接受但落不到设备，
表现为 `execute_action` 回 `verified=false`——2026-09-18 冷启动时实测踩过这个坑。

## 用法

```powershell
cd <仓库根>
$env:HA_CONFIG_DIR = "D:\homeassistant\config"    # 首次建 HA 容器用；已存在可忽略
powershell -NoProfile -ExecutionPolicy Bypass -File _tools\start_simuhome_stack.ps1
# 需要把仿真恢复到初始状态（例如实验跑前）时：
powershell -NoProfile -ExecutionPolicy Bypass -File _tools\start_simuhome_stack.ps1 -ResetHome
```

本文件存成 **带 BOM 的 UTF-8**：PowerShell 5.1 按本地代码页读 `.ps1`，
不带 BOM 时中文字符串会被解坏、直接语法报错（实测踩过）。
