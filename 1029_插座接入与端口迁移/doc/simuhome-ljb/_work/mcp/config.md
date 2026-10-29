# config.yaml

这是沙盒用的 MCP server 配置。放在 `_work\` 下的原因：写进 `ha_mcp_universal\config.yaml` 等于往源目录写文件，与 AGENTS.md 第 1 条冲突。内容与 `ha_mcp_universal\config.example.yaml` 等价，只改了注释。

相对路径（`./data/...`）以运行时的工作目录为基准，所以运行时要把工作目录设成 `_work\mcp`，记忆文件、别名表、预约库都会落在 `_work\mcp\data\` 下。

## 数据内容

```text
ha              base_url=http://localhost:8123  token=${HA_TOKEN}  timeout_s=25
rooms           三个沙盒房间的 room_id → HA area_id 映射（同名）
room_env {}     留空：按 area + sensor.device_class 推导环境量
devices {}      留空：映射表由实体注册表在启动时生成
doors []        当前没有门磁实体，inspect_room 的 doors 恒为 null
```

认领规则决定"哪些实体属于 MCP"，三段：

```text
sandbox   platforms=[mqtt]  unique_id_prefix=simuhome_  id_source=identifier
          按后缀判类型：_switch→switch / _climate→climate / _fan→fan
          → 沙盒那 25 个实体

xiaomi    platforms=[xiaomi_home]  id_source=device_name
          domains=[switch,light,climate,fan,cover,number,select,sensor]
          exclude_category=[config,diagnostic]
          exclude_entities=["button.*","update.*","*_reset_*"]
          → 真米家冰箱的 12 个实体（被排除的是 reset 按钮与 event）

local     platforms=[mqtt]  unique_id_prefix=bt_  id_source=identifier
          → 蓝牙音箱桥的两个实体，逻辑 id 是 speaker

zigbee    platforms=[mqtt]  unique_id_prefix="0x"  domains=[sensor, switch]  id_source=device_name
          → ZB-GW04 + Z2M 接进来的 Zigbee 设备；Z2M 的 unique_id 形如
            0xa4c138..._temperature_zigbee2mqtt，桥自身的是 bridge_... 开头，天然不被误收
```

其余段：

```text
areas.alias       2646196763de_jia → 米家
areas.hide_empty  true           米家那边没放设备的空房间不出现在 observe_home
aliases.file      ./data/device_aliases.yaml
execution         verify_after_action=true  verify_delay_ms=800  verify_attempts=4
events            排除 sensor.simuhome_virtual_time（实测占 logbook 的 91%）
memory            ./data/memory.yaml  max_write_tokens=200  max_read_tokens=300
time              Asia/Shanghai  ./data/schedules.db  max_horizon_days=7  max_steps=8
tools.expose      8 个工具的白名单，顺序即 tools/list 顺序
server.transport  stdio（HTTP 段被注释掉，需要时再开并设 MCP_TOKEN）
```

## 实测得到的认领结果

```text
2026-10-10  {'sandbox': 25, 'xiaomi': 10, 'local': 2}
           投影设备 15 台，房间 4 个（3 沙盒 + 米家），投影实体 22 个

2026-10-27  加 zigbee 规则后：Z2M 的 TH01 温湿度计被认领，
           因为该设备只有 sensor（没有可控实体），按 mapping 的规则归入"房间环境量"，
           observe_home 多出一个房间 wo_shi（卧室），env={temperature, humidity}
           注意它不会出现在 devices 列表里，inspect_device 也查不到——它没有可控动作

2026-10-29  domains 补上 switch，插座 SPZ01 进来：
           observe_home 里 wo_shi / 卧室 devices: ["spz01"]，房间 6、设备 17
           inspect_device(spz01) → kind=switch、state{on}、actions{turn_on,turn_off,toggle}
```

## 对应文件

```text
_work\mcp\config.yaml                     本文件
ha_mcp_universal\config.example.yaml       等价模板（仓库只读文件）
_work\mcp\data\device_aliases.yaml         别名表（本文件 aliases.file 指向它）
_work\mcp\smoke.py                         用它做只读冒烟
_work\llm\test_llm_surface_local.py        用它做 12 项模型测试
```
