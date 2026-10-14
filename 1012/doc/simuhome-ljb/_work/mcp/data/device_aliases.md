# device_aliases.yaml

MCP server 的设备别名表。首次扫描自动生成，可以手工改；改完要重启 MCP server 才生效（别名在启动时读一次）。本文件被 `_work\.gitignore` 的 `data/` 规则排除，不进仓库。

## 数据结构

```text
devices    map：HA 的设备 hash → 我们给它的逻辑名
entities   map：留空（本机没有单独给实体起别名）
```

## 数据内容（18 条，逐条列出）

```text
0e833941ba871f1844f52e5238efa237   simuhome
2c3f8eaba8a20f86e67385506a739910   laundry_washer
40cc28a8236b64e6deba66812fe09dcd   utility_room
423910141eac48ce3d33e9d50249cbb2   on_off_light_2
446af7bb072e4f1bf673026cc0599806   on_off_light_3
4d75ff7d3197b60e6342ff9d97d60f00   air_purifier
4f5d690b7b79a490b66f09edd68c8972   dishwasher
54c8078d3aa0be6a00e127fa53eb6d82   fan
59577313e05a76692f394daa5c18ba90   living_room
5acefc8042f2448e53140a36d5cbda04   dimmable_light
7579b258457ca129ba25df9b2453f21d   bt_speaker
8347cf76ac99337771d6fbd90fd300fd   on_off_light
8e1d0b1ab7245d21e786740f5ceffa25   tv
a3cd8ef81e925028a288bf6e90854582   air_conditioner
ba4e467ee1e5901c54f79376ffb9994d   kitchen
bc605b2cc77251b025fd9934bc21aac4   laundry_dryer
eeae38761f53126bd0d9ecdb4f538de2   air_conditioner_2
f6952b98182664fdf5c7da132162a558   fridge
```

## 这份表与设备 id 的关系

这里的名字来自 HA 的设备名，而 MCP 对外的 `device_id` 由配置里的 `id_source` 决定：sandbox 段用 `identifier`，于是对外看到的是 `living_room_side_light` 这类 id；`bt_speaker` 这条对应 `local` 段的 `identifier`，对外 id 是 `speaker`。别把这份表里的值直接当成 MCP 的 device_id。

## 已知问题

第 13 行 `bt_speaker` 对应的那条只是个 hash 映射，容易和真实 HA device_id（`7579b258…`）混淆——`_work\ha_login.ps1` 里打开的设备页 `/config/devices/device/7579b258457ca129ba25df9b2453f21d` 用的就是这个 hash。

## 对应文件

```text
_work\mcp\data\device_aliases.yaml    本文件
_work\mcp\config.yaml                  aliases.file 指向本文件
```
