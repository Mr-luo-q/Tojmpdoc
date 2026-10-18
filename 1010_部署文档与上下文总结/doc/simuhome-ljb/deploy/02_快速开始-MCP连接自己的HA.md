# 02：快速开始——MCP 连接自己的 HA

目标：不依赖沙盒，把你的 HA 变成 MCP 的 8 个统一语义工具。全程只需要 HA 的地址和一枚长期令牌。

## 1 前提

```text
① 一个能访问的 HA 实例（Docker / HA OS / Core 均可），浏览器能打开 http://<host>:8123
② HA 里创建一个长期访问令牌：
   点左下角用户名 → 安全 → 长期访问令牌 → 创建令牌 → 复制
③ Python 3.13（或 >=3.11）
```

## 2 安装

```powershell
cd <repo>\ha_mcp_universal
python -m pip install -e .
# 或者只装依赖：python -m pip install mcp==1.26.0 PyYAML websockets
```

## 3 配置

```powershell
copy config.example.yaml config.yaml
$env:HA_TOKEN = "<上一步的令牌>"
```

`config.yaml` 关键段（config.yaml 不入库，可以放心填本机信息）：

```text
ha.base_url   你的 HA 地址；Docker 在同机时 http://localhost:8123
ha.token      ${HA_TOKEN} 占位符，运行时从环境变量取；也可直接写死
rooms         room_id → HA 的 area_id；给三个沙盒房间用，接真机可留空
claim         决定"哪些实体属于 MCP"：
              sandbox 段认领 MQTT discovery 的 simuhome 实体（层2 用）
              xiaomi 段认领小米官方集成实体（层3 用）
aliases.file  首次扫描会生成 ./data/device_aliases.yaml，可手工改成好读的 device_id
tools.expose  对模型开放的 8 个工具白名单；顺序即 tools/list 顺序
server        transport: stdio（默认）；也可改 http + MCP_TOKEN
```

## 4 冒烟（先离线、再真机）

```powershell
# 离线测试：不需要 HA，36 项
python -m pytest tests\test_contract_tools.py tests\test_memory.py tests\test_time_control.py `
       tests\test_inspect_time.py tests\test_claim.py tests\test_roles.py -q

# 只装配不起服务：打印 8 个工具名
$env:PYTHONPATH = "$PWD\src"
python -m home_mcp.entry --config config.yaml --dry-run

# 真机端到端（22 项；见下方注意）
python tests\test_e2e_real_ha.py --config config.yaml
```

注意：`test_e2e_real_ha.py` 的检查写死了沙盒设备 id（`living_room_side_light` /
`living_room_ac` / `kitchen_fan` / `living_room_tv` 等）。换到你家，先改脚本里的设备常量，
或只用 `observe_home` / `inspect_room` / `inspect_device` 手工验证。

## 5 接大模型（stdio）

任何支持 MCP 的客户端都可以，典型配置长这样：

```json
{
  "mcpServers": {
    "home-mcp": {
      "command": "python",
      "args": ["-m", "home_mcp.entry", "--config", "<repo>\\ha_mcp_universal\\config.yaml"],
      "env": {
        "HA_TOKEN": "<你的令牌>",
        "PYTHONPATH": "<repo>\\ha_mcp_universal\\src"
      }
    }
  }
}
```

## 6 用 DeepSeek 实测（可选）

```powershell
# 密钥放 ha_mcp_server\.env：DEEPSEEK_API_KEY=...（可选 DEEPSEEK_MODEL，默认 deepseek-flash）
python tests\test_llm_surface.py --config config.yaml
# 12 项：8 个接口全部真实调用（observe/inspect×3/execute/finish/time_control/memory）
```

8 个工具一览（详见 `finally new paper\10_04V2接入小米后设计方案\15_目前方案与交付接口.md`）：

```text
observe_home / inspect_room / inspect_device / execute_action / finish
inspect_time / time_control（schedule→list→cancel）/ memory（read/write）
```
