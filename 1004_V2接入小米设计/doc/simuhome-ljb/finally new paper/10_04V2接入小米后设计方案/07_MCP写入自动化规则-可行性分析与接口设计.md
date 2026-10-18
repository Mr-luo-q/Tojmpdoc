# 07 MCP 写入自动化规则：可行性分析与接口设计

日期 2026-10-06。问题：基于目前 HA 暴露的接口，我们的 MCP 能否加一个
"写入自动化规则"的接口？按先简单（不用脚本）、后复杂（用脚本）分析。

## 0. 结论

```text
可行性   可行，HA 已经暴露完整的自动化/脚本配置接口，本机实测通过（见 §1）

简单规则 不用脚本就能覆盖：状态触发、时间触发、数值触发、条件、多个服务动作。
          MCP 侧建议暴露结构化参数（trigger/condition/action），由 MCP 编译成
          HA 自动化 JSON；不要求模型直接写 YAML/代码
          证据：本地 1.5B 零样本写 HA YAML 被 HA 拒（400），给一条正确示例后通过（200）

复杂规则 用脚本可覆盖：延时/等待、分支（choose/if）、循环（repeat）、并行（parallel）、
          变量与模板、调用其它脚本。接口同样可用（§3 实测脚本配置 CRUD），
          但必须加白名单与业务校验，因为 HA 只校验 schema、不校验"该不该调这个服务"

接口方案 建议新增第 9 个工具（manage_rule），动作词表不扩；脚本作为高级路径
```

## 1. 已核实的 HA 接口（本机实测 2026-10-06）

```text
自动化配置   POST /api/config/automation/config/{id}    200 {"result":"ok"}
             GET  同路径                                200，返回规范化后的配置
             DELETE 同路径                              200，实体被删除
             创建后 HA 自动 reload，出现 automation.<id> 实体
脚本配置     POST /api/config/script/config/{id}        200
             GET/DELETE 同路径                          200，出现/移除 script.<id>
自动化服务   automation.trigger / turn_on / turn_off / toggle / reload
脚本服务     script.turn_on / turn_off / toggle / reload
列表         没有 REST 列表端点（GET 基路径 404）；用 /api/states 过滤
             automation.* / script.*，单条配置用 GET 或 WebSocket automation/config
权限         配置接口是 @require_admin，需要管理员长期令牌（MCP 现在用的就是）
存储         写入 automations.yaml / scripts.yaml（本机 configuration.yaml 已 include）
```

实测记录：

```text
自动化探针  codex_llm_probe2  POST 200 → 出现 automation.codex_llm_probe2；DELETE 200；数量回 0
脚本探针    codex_script_probe POST 200 → 出现 script.codex_script_probe=off；
            GET 200；DELETE 200；数量回 0
```

## 2. 简单规则（不用脚本）

### 2.1 HA 侧最小数据结构

```json
{
  "alias": "客厅有人就开灯",
  "trigger": [
    {"platform": "state", "entity_id": "binary_sensor.living_room_motion", "to": "on"}
  ],
  "condition": [],
  "action": [
    {"service": "light.turn_on", "target": {"entity_id": "light.living_room_side_light"}}
  ],
  "mode": "single"
}
```

```text
简单侧能用的触发器   state / numeric_state / time / time_pattern / sun / zone / event
简单侧能用的条件     state / numeric_state / time / sun / zone / and / or / not
简单侧的动作         一次或多次服务调用（顺序执行），不带延时、分支、循环、模板
```

### 2.2 MCP 侧建议的结构化接口

```text
工具      manage_rule（新增第 9 个工具；动作词表保持 8 个不变）
op        create / update / delete / list / enable / disable / trigger
参数      rule_id、alias
          triggers[]    {type: state|time|numeric_state, entity_id?, to?, at?, above?, below?}
          conditions[]  {type: state|numeric_state|time, ...}（可选）
          actions[]     {device_id, action, params}  ← 复用我们现有的 8 个动作
```

编译方式：MCP 内部把 `device_id` 映射成 HA 实体、把 `action+params` 映射成服务调用
（复用 v2 已有的 registry / plan_execution），再 POST 到 HA 自动化配置接口。
所有 MCP 创建的规则用统一前缀（如 `mcp_`），便于列表与批量清理。

### 2.3 三个例子（MCP 调用 → 编译出的 HA JSON → 效果）

例 A：有人移动就开灯

```text
MCP 调用   manage_rule(op=create, rule_id=mcp_motion_light,
           triggers=[{type: state, entity_id: living_room_motion, to: on}],
           actions=[{device_id: living_room_side_light, action: turn_on}])
HA JSON    {"alias":"mcp_motion_light","trigger":[{"platform":"state",
           "entity_id":"binary_sensor.living_room_motion","to":"on"}],
           "action":[{"service":"light.turn_on","target":
           {"entity_id":"light.living_room_side_light"}}]}
效果       传感器变 on 时灯亮；可用 automation.trigger 手动触发做验收
```

例 B：每晚 22:00 关客厅灯

```text
MCP 调用   manage_rule(op=create, rule_id=mcp_night_off,
           triggers=[{type: time, at: "22:00:00"}],
           actions=[{device_id: living_room_side_light, action: turn_off}])
HA JSON    {"trigger":[{"platform":"time","at":"22:00:00"}],
            "action":[{"service":"light.turn_off","target":
            {"entity_id":"light.living_room_side_light"}}]}
效果       到点自动关灯；测试时可先手动 trigger 验证动作
```

例 C：厨房温度高于 30 且有人在家，开风扇 60% 档

```text
MCP 调用   manage_rule(op=create, rule_id=mcp_kitchen_fan,
           triggers=[{type: numeric_state, entity_id: kitchen_temperature, above: 30}],
           conditions=[{type: state, entity_id: person_user, state: home}],
           actions=[{device_id: kitchen_fan, action: set_percentage, params: {value: 60}}])
HA JSON    {"trigger":[{"platform":"numeric_state","entity_id":
            "sensor.simuhome_kitchen_temperature","above":30}],
            "condition":[{"condition":"state","entity_id":"person.user","state":"home"}],
            "action":[{"service":"fan.set_percentage","target":
            {"entity_id":"fan.simuhome_kitchen_fan"},"data":{"percentage":60}}]}
效果       温度越限且满足条件时设档；不满足条件不执行
```

简单侧的边界：做不了延时等待、分支、循环、模板、变量、调用脚本（这些进 §3）。

## 3. 复杂规则（使用脚本）

### 3.1 HA 脚本能力（接口已实测可用）

```text
脚本配置   /api/config/script/config/{id}
           body = {alias, sequence:[...], mode, max, fields?}
sequence 可用  服务调用、delay、wait_template、wait_for_trigger、choose/if、
               repeat、parallel、variables、continue_on_error、停止/调用其它脚本
调用方式  自动化 action 里写 script.turn_on（target: script.xxx），
          或直接 action: script.xxx
```

### 3.2 两个脚本例子

例 D：离家后收尾（脚本 + 自动化引用）

```text
脚本     script.mcp_away_sequence
         sequence:
           - choose: 若客厅灯开着 → light.turn_off
           - delay: 00:05:00
           - action: persistent_notification.create
             data: {message: "离家 5 分钟，已执行收尾"}
自动化   trigger: state person.user → not_home
         action: script.turn_on target: script.mcp_away_sequence
效果     一条规则里做"条件分支 + 等待 + 通知"；脚本还能被别的规则复用
```

例 E：电影模式（多设备编排）

```text
脚本     script.mcp_movie_mode
         sequence:
           - light.turn_on   target 客厅灯, brightness_pct 20
           - cover.set_cover_position  target 窗帘, position 0
           - media_player.turn_on      target 电视
           - choose: 若时间晚于 22:00 → 发通知
自动化   trigger: 按钮/时间/语音 → action: script.mcp_movie_mode
效果     一条动作编排多个设备；自动化只负责"什么时候触发"
```

### 3.3 复杂侧的约束与风险

```text
安全白名单   模板/脚本能调用任意 HA 服务（含 homeassistant.restart、shell_command），
             MCP 必须在写入前校验：device_id 属于已认领设备、action 属于 8 个动作、
             params 在设备自报范围内；不允许自由写 service 名
模板限制     端侧小模型不建议生成 Jinja 模板；需要计算时优先用结构化参数或固定脚本
错误处理     HA 400 → MCP 返回 BAD_REQUEST；创建失败不留半成品（先校验后写入）
命名与清理   统一 mcp_ 前缀；list 只列前缀内规则；episode 结束批量 delete
时间语义     HA 虚拟时间 1:1，不能快进；时间触发测试要么真实等待，要么手动 trigger
持久化       规则写在 HA 配置里，重启仍在；RL 环境必须显式清理，避免跨 episode 污染
```

## 4. MCP 接口方案对比

```text
方案 A（推荐）  新增第 9 个工具 manage_rule：结构化 trigger/condition/action，
                MCP 编译成 HA 自动化 JSON；脚本作为高级路径（script 字段）
方案 B          扩 execute_action 的动作词表（加 create_rule）——破坏 8 动作契约，不推荐
方案 C          保持 8 工具不变，规则在外部用 HA API 管理（现状）——可用，
                但规则不在 MCP 的统一语义面内，模型无法自己设定规则
```

## 5. 验收计划（可执行）

| # | 用例 | 步骤 | 期望 |
| --- | --- | --- | --- |
| 1 | 状态触发 | create 例 A → 改传感器状态或 automation.trigger | 灯亮；check_goal 通过；delete 后数量回 0 |
| 2 | 时间触发 | create 例 B（at=当前+2分钟） | 到点关灯；query_events 有记录 |
| 3 | 数值+条件 | create 例 C → 构造温度与在家状态 | 满足时才设档 |
| 4 | 脚本序列 | create 例 D 脚本 + 自动化 | 分支/等待/通知按序执行 |
| 5 | 非法配置 | 不存在的实体、越界参数、危险服务 | HA 400 或 MCP 本地拦截（BAD_REQUEST） |
| 6 | 清理 | 删除全部 mcp_ 规则 | automation/script 数量回 0 |

```text
已验证     automation/script 配置接口的创建、读取、删除；服务清单；实体出现与清理
未验证     触发到执行的完整链路（用例 1~4）、模板/脚本运行、并发创建冲突
```
