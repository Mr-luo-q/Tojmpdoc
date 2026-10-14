# MCP 接入真实设备的映射扩展设计

触发这次讨论的事实：2026-09-23 米家（Xiaomi Home 官方集成）接进 HA 成功，
导入了 1 台真实设备——米家对开门冰箱（`midjd6.fridge.6101`，did `cn_911432173`），
它在 HA 里表现成 **1 台设备 + 12 个实体**（7 sensor / 2 number / 1 select / 1 button / 1 event）。
而我们自建的 MCP **看不见它**。本文说明为什么会这样、算不算"草率"、以及要接入这类设备该怎么改。

结论先行：现状不是随手写的，是**为沙盒实验刻意收窄的范围**；但收窄的方式把
"接入层"和"统一语义层"用命名约定粘在了一起，确实是一笔技术债。要把真实设备接进来，
需要按三层拆开改：认领规则、设备模型、动作/状态映射。

## 1. 现在的认领链路：三道硬编码闸门

`ha_mcp_server\src\home_mcp\backend_ha\mapping.py` 里的 `build_view()` 是唯一的映射入口，
它给每一条实体记录连过三道闸门：

```text
闸门 1  platform 必须是 mqtt                mapping.py:244  if entity.get("platform") != "mqtt": continue
闸门 2  设备标识必须以 simuhome_ 开头          mapping.py:66-76  logical_id_from_identifiers()
闸门 3  实体 unique_id 必须 simuhome_ 开头     mapping.py:79-87  split_unique_id()
        且以 _switch / _climate / _fan 结尾   mapping.py:21-25  KIND_BY_SUFFIX

另有两条附带的约定
        虚拟时间实体写死 simuhome_virtual_time   mapping.py:35
        房间传感器也要 unique_id 以 simuhome_ 开头 mapping.py:271（否则不进 sensors_by_area）
```

米家实体在**闸门 1** 就被丢掉了：它们的 `platform` 是 `xiaomi_home`，不是 `mqtt`。
就算放开闸门 1，闸门 2/3 也过不了——米家的设备标识是 `['xiaomi_home','cn_911432173']`，
实体 unique_id 是 `midjd6_cn_911432173_6101_target_temperature_p_3_2` 这类形式。

三道闸门的直接后果：

| 影响面 | 现状 |
| --- | --- |
| 设备清单 | 只含 12 台 simuhome 可控设备；米家设备一台都进不来 |
| 房间环境量 | 只聚合 simuhome 的房间传感器；米家的冷藏/冷冻温度不会被当成房间温度（目前反而是好事） |
| 动作表 | 只有 switch / climate / fan 三类（`contract\tools.py` 的 `ACTIONS_BY_KIND`） |
| check_goal 目标 | 只认 `<room>.<metric>` 与 `<device_id>.<六字段>` |

## 2. 这算"草率"吗：一半是范围收窄，一半是债

```text
是范围收窄的部分（有意为之，写在 11 号文档里）
  · 论文的主实验是"SimuHome 沙盒 ↔ HA 真机 双后端同语义"，
    两边必须是同一批设备、同一套动作、同一套状态字段，才能对照
  · 沙盒侧固定 3 房间 / 12 台可控设备，所以 HA 侧只投影这批
  · 收窄换来的是：启动零配置（映射全从注册表生成）、语义面可控、单测简单

是债的部分（实现把"范围"写成了"硬编码"）
  · 平台判断写死 mqtt：任何非 MQTT 集成（米家、Zigbee、Matter…）都被挡在门外
  · 逻辑 id 与 kind 从前缀/后缀里"猜"：命名约定成了隐式契约，
    改一次 unique_id 就可能让设备消失（reset_discovery 后要重跑 rename 就是这个原因）
  · 一台设备 = 一个实体：装不下米家这种"一台设备 12 个实体"的形态
  · 动作词表在文档里写着 8 个（含 set_brightness / set_position 预留），
    代码里 `ACTIONS_BY_KIND` 只有 3 类、`ACTION_SERVICE` 只有 6 个动作——
    文档与代码已经有落差，接 light/cover 之前必须补齐
```

## 3. 扩展目标（和不做什么）

```text
目标
  1  认领规则可配置：按集成平台 + 域白名单收设备，不再写死 mqtt/simuhome
  2  设备模型支持"一台设备多个实体"：给每个实体一个角色（power/target/mode/current/level…）
  3  动作面补齐 light / cover（set_brightness / set_position），并允许声明式映射
  4  六字段状态保持为"统一视图"，映射不到的字段允许为 null

不做（这一版）
  · 不追求把米家所有属性都映射进六字段（压缩机转速、故障位图这类留在 HA 侧）
  · 不改沙盒主实验的设备集合与口径（扩展默认关闭，用配置开关打开）
  · 不做场景/自动化/仪表盘类实体（button、event、update 一律不收）
```

## 4. 设计方案：分三层改

### 4.1 认领层：从硬编码改成"配置 + 平台白名单"

```yaml
# config.example.yaml 草案（新增 devices.claim，留空 = 保持现在的行为）
devices:
  claim:
    - platform: mqtt              # 沙盒发布器
      id_prefix: simuhome_        # 设备标识前缀 → 逻辑 id
      unique_id_prefix: simuhome_ # 实体 unique_id 前缀
      kind_by_suffix:             # 从 unique_id 后缀推类别
        _switch: switch
        _climate: climate
        _fan: fan
    - platform: xiaomi_home       # 米家官方集成
      domains: [switch, light, climate, fan, number, select, sensor]
      id_from: device_name        # 逻辑 id 用设备名 slugify（可读），不用 did
      kind_by_domain:             # 域直接决定类别；number/select/sensor 走角色映射
        switch: switch
        light: light
        climate: climate
        fan: fan
```

改动点：`build_view()` 按 `claim` 列表逐条匹配（平台 → 前缀/域），不再有全局常量；
`IDENTIFIER_PREFIX` / `KIND_BY_SUFFIX` 退化成默认 claim 的取值。

### 4.2 设备模型层：一台设备 = 一个 device_id + 若干实体角色

```python
@dataclass(frozen=True)
class EntityRef:
    """一个角色绑定的实体。"""
    entity_id: str
    domain: str                 # switch / number / select / sensor …

@dataclass(frozen=True)
class DeviceRow:
    device_id: str              # 对外逻辑 id，如 fridge 或 living_room_ac
    area_id: str | None
    name: str
    kind: str                   # 主类别（决定动作子集）：switch/light/climate/fan/fridge…
    roles: dict[str, EntityRef] # power / mode / target / current / level / position / fault …
    ha_device_id: str
```

角色表的初版约定（按六字段对齐）：

```text
power     → switch.* / light.*                映射到 on
mode      → select.*（如冰箱"手动/智能"）       映射到 mode
target    → number.*（如冷藏设定温度）          映射到 target
current   → sensor.*（如冷藏室温度）            映射到 current
level     → number.* / fan.*（档位、亮度）      映射到 level
position  → cover.*                            映射到 position
```

米家冰箱这种"一台设备两个温区"的情况，需要给角色加子键（`target.fridge`、`target.freezer`），
或者把它当成两个逻辑设备（`fridge_cold` / `fridge_freeze`）发布——这是这一版必须拍板的取舍，
建议先用子键（保持"一台物理设备"的直觉），在 `inspect_device` 里展开成两个动作参数。

### 4.3 语义层：动作面补齐 + 声明式动作映射

```yaml
# 动作映射草案：动作名 → HA 服务 + 用哪个角色当目标
actions:
  set_brightness: {service: light.turn_on,        target_role: power, field: brightness_pct}
  set_position:   {service: cover.set_cover_position, target_role: position, field: position}
  set_target:     {service: number.set_value,     target_role: target, field: value}
  set_mode:       {service: select.select_option, target_role: mode,   field: option}
```

配合 `contract\tools.py` 的动作词表扩到文档里承诺的 8 个（现在代码只有 6 个服务映射）。

### 4.4 状态层：六字段是"统一视图"，不是"全部真相"

```text
映射得到的字段填值，映射不到的字段给 null —— 与掉线时的处理一致，不猜
米家特有的量（压缩机转速、故障位图、门未关提醒）本轮不进六字段，
需要时走 query_events（HA 侧本来就有历史）或二期加"扩展字段"通道
```

## 5. 三个落地选项（按工作量排）

```text
A 最小可用（约 0.5 天）
  只做 4.1：认领规则改成配置 + 放开平台/域白名单；
  仍要求"一台设备一个实体"，所以只能接米家的 switch/light/climate/fan 单实体设备。
  冰箱这类多实体设备仍然进不来。

B 设备级映射（约 1.5~2 天）
  A + 4.2（roles 模型）+ 4.3 里的 set_target/set_mode。
  验收样例就用冰箱：能读出 current/target/mode，能写设定温度与模式。
  这是"真实设备接入"的最小完整闭环。

C 通用声明式映射（约 3~5 天）
  B + 完整的 YAML 动作映射 + 单测 + 文档；
  目标是"HA 里任何可控设备，只要写一段配置就能按统一语义接入"。
  工作量主要花在边界：参数类型转换、单位、枚举、回读期望值。
```

建议：先做 B（把冰箱打通），C 留到论文扩展实验需要更多设备时再做。

## 6. 验收方式（以米家冰箱为试点）

```text
读     inspect_device(fridge) →
        state {on: null, mode: "手动", target: 5, current: 4}（on 允许为 null：冰箱没有开关语义）
        actions: [set_target(冷藏 1~9), set_target(冷冻 -24~-16), set_mode(手动/智能…)]
写     execute_action(fridge, set_target, {zone: "fridge", value: 6}) → 回读 target=6 → 复原成 5
判定   check_goal(conditions=[{target: "fridge.current", op: "lte", value: 6}]) → pass
回归   simuhome 12 台设备与三条测试线不变：契约 12/12、端到端 21/21、降级 21/21
隔离   扩展默认关闭（claim 里不写 xiaomi_home 时，行为与现在完全一致）
```

## 7. 风险与边界

```text
实体 id 太长     midjd6_cn_911432173_6101_target_temperature_p_3_2 不该直接给模型；
                逻辑 id 必须走"设备名 slugify + 角色"而不是 unique_id 截断
无开关语义设备    冰箱没有 on/off：六字段里 on=null，动作表里不能出现 turn_on/off，
                否则模型会尝试并拿到 UNSUPPORTED_ACTION
云端时延与配额    米家是云端轮询（iot_class=cloud_polling），命令落定比 MQTT 慢；
                回读的 verify_delay_ms × attempts 可能要放宽，或按设备类别配置
房间归属         米家设备现在挂在自动生成的区域（2646196763de_jia）；
                要么让用户在 HA 里改 area，要么在映射层写 area 覆盖
命名与语义        米家自己也会一设备多实体、一实体多属性；
                我们只承诺六字段能装下的部分，装不下的明确写 scoping
别污染主实验      扩展开关默认关闭；论文主实验仍用 3 房间 / 12 台 simuhome 设备，
                真实设备作为单独一节（"接入层对第三方集成的可扩展性"）来写
```

## 8. 改动清单（文件级，B 方案）

```text
mapping.py        build_view 支持 claim 列表；DeviceRow 加 roles；summarize_state 支持多实体取值；
                  resolve_target 支持角色字段（fridge.current / fridge.target.fridge）
contract\tools.py  ACTIONS_BY_KIND 扩到 light/cover；动作词表补 set_target（或复用 set_temperature）
execute_action.py  动作 → 服务映射改成从配置读；补 set_brightness / set_position
config.example.yaml 新增 devices.claim 与 actions 两段（留空 = 现状）
tests\            新增 test_mapping_claim.py（假注册表：mqtt + xiaomi 两种平台）
                  新增米家冰箱的夹具（12 个实体）与写读回读用例
文档              11 号 §5.4 补"认领规则可配置"；12 号补 light/cover 动作落地状态
```

## 9. 与论文的关系

```text
现在能写的      "统一语义在自建投影（SimuHome→HA）上验证过"——这是已完成的
这次扩展能加的   "同一套语义接口可以接第三方集成的真实设备"——一条可举证的扩展性证据
不能吹的        不要声称"支持所有米家设备"：只跑通 1~2 类设备就按 1~2 类写，
                其余（多组件、特殊单位、只读设备）如实写进 scoping
```
