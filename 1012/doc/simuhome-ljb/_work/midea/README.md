# midea

美的设备的接入相关文件。目标是接那台通过**美的美居**联网的温湿度计。

## 为什么走这条路线

仓库里已有一份调研：`finally new paper\10_04V2接入小米后设计方案\辅助调研文档\10_美的设备HA接入方案调研.md`，给了三条路线。它当时的"首选"是官方 `midea` 集成，但那是假设本地直连可用；本机实测下来两处约束把本地路线堵住了：

```text
官方 midea 集成    要求 HA >= 2026.8（沙盒是 2026.5.4），且运行期走局域网直连
                   升镜像要拉 Docker Hub —— 容器里 registry-1.docker.io 返回 Network unreachable
                   就算升上去，本地直连还要 HA 与设备同网段，而校园网开了客户端隔离

midea_ac_lan      同样本地直连，且最后推送停在 2024-08，两年未更新

midea_auto_cloud  纯云（manifest 里 iot_class = cloud_push），不碰局域网
                   美的美居云 mp-prod.smartmidea.net 实测 HTTP 200 可达
```

所以选云方案。

## 版本与兼容性（装机前核对过）

```text
仓库      sususweet/midea_auto_cloud   295★   最后推送 2026-09-20
版本      manifest 里是 v0.4.19
HA 要求   hacs.json 写 "homeassistant": "2024.11.0"  —— 沙盒 2026.5.4 满足
依赖      requirements: ["lupa>=2.0"]
          容器 Python 3.14.2；pip dry-run 解析到 lupa-2.8-cp312-abi3-musllinux_x86_64.whl，
          abi3 对 3.12+ 通用，装得上
设备定义  device_mapping\ 下 46 个 T0xNN 类型定义；sensor 平台支持从映射里带 device_class
```

## 装法

按装 `xiaomi_home` 的老路子，手工拷进沙盒（不引入 HACS）：

```text
来源    _work\midea\extract\midea_auto_cloud-master\custom_components\midea_auto_cloud
目标    D:\homeassistant-sandbox\custom_components\midea_auto_cloud
重启后  HA 日志出现 "We found a custom integration midea_auto_cloud"（2026-10-12 18:53:50）
```

`lupa` 此刻还没装，这是正常的：HA 在**配置条目建立时**才安装依赖，不是发现目录时装。

## 登录需要什么

配置流的字段（读 `config_flow.py` 得到）：

```text
步骤 user         account（账号）+ password（密码）+ server（1=MSmartHome，2=美的美居）
步骤 select_homes  勾选要导入的家庭
步骤 download      从云端下载该设备的 Lua 协议文件，落到 HA 存储目录
步骤 confirm       建条目
```

所以需要一份**美的美居的账号与密码**。按本项目一贯做法，写进 `_secrets\midea_account.txt`（第一行账号、第二行密码），不要贴在对话里；`_secrets\` 已被 `.gitignore` 排除。

## 预期与风险

```text
预期   登录后选家庭，集成自动下载该设备的 Lua 协议，HA 里出现传感器实体
       温湿度是只读量，MCP 侧会作为环境量（room_env 那条路）出现在 observe_home 里

风险一 2021 年后部分美的/贴牌机型实为涂鸦平台，美的协议系集成全部不适配
       （调研文档 §8 原话）。若登录后设备列表里没有这台温湿度计，就是这条，
       那时改走涂鸦路线或反向查它的设备类型码

风险二 账号风控：短时间内反复登录可能触发验证码，登录失败先等一会儿再试

风险三 这台设备在同一账号下若也被别的集成连接，可能出现互相打架（调研文档 §8 提到过）
```

## 实测（2026-10-12）

登录与安装都成功，卡在设备侧。逐步结果：

```text
1  集成拷进沙盒 → 重启 → 日志认出 "We found a custom integration midea_auto_cloud"
2  起 config flow → 步骤 user 提交账号密码（server=2 美的美居）→ 进 select_homes，无错误
3  可选家庭只有一个：id 247760014，名字"布鲁斯的家"
4  select_homes → 进 download（异步）→ 下载摘要："成功 0 个 / 跳过 1 个"
5  confirm → 建条目成功，title "5150 | 布鲁斯的家"，state=loaded
6  lupa 2.8 自动装上（HA 在建设置条目时装的，符合预期）
7  HA 里出现一个实体：binary_sensor.wen_shi_du_ji_device_status（platform=midea_auto_cloud）
   状态 unavailable，属性只有 device_class=connectivity，没有可访问字段列表
```

日志里的两条关键信息（把 `custom_components.midea_auto_cloud` 调到 debug 后拿到）：

```text
Can't load mapping file for type T0x54.
   sn8: 402M0001, subtype: 1001, category: temperature-humidity-sensor

Status update: {'connected': False}
Device 温湿度计 (212305752896363) failed 3 consecutive polls;
   marking entities unavailable until data flows again
```

设备身份已经拿到：**温湿度计**，云端 id `212305752896363`，分类 `temperature-humidity-sensor`，
设备类型 `T0x54`，subtype `1001`，sn8 `402M0001`。

## 两个问题（一个已确认，一个待验证）

```text
已确认  上游没有 T0x54 的映射文件。
        内置 device_mapping\ 47 个文件里没有 T0x54.py；
        下载下来的 plugin\T0x54_10008857.zip 是美的美居 App 的 UI 插件
        （weex.js + 图片 + 字体，plugin.json 写着"智有范旋钮"），不是设备协议映射。
        .storage/midea_auto_cloud/lua\ 里只有 bit.lua 与 cjson.lua，没有这台设备的 lua
        —— 对应下载摘要里的"跳过 1 个"。

待验证  这台设备的实时数据到底在不在云上。
        云侧报 connected: False，轮询拿不到数据，Status 实体的属性因此是空的。
        一个可能：它是蓝牙型，美的美居 App 就近用蓝牙读它，
        云上只有设备登记、没有实时读数。这能同时解释"lua 被跳过""实体一直 unavailable"
        以及"46 个内置类型里没有它"（那些都是 Wi-Fi 家电）。
```

## 下一步的三条路

```text
判定它是不是蓝牙型（最省事）
  把手机蓝牙关掉或退出美的美居，再跑一次 _work\ble\scan.py。
  扫到 → 它是蓝牙型，改走 Windows 侧读广播 → MQTT → HA（音箱桥那套模式）
  扫不到 → 它不是广播型，继续看下面两条

给上游提适配
  按 midea_auto_cloud 的 CONTRIBUTING 提 issue，附 Device type / Subtype / category
  以及 .storage/midea_auto_cloud/lua 下的 lua 与 plugin 里的 zip。
  我们缺 lua（被跳过了），所以这条依赖上面那个判定。

自己写映射
  需要设备 status 的字段名。README 说 Status 实体的属性里会列出所有可访问字段，
  但那要设备能上报数据才有——现在它是空的，所以同样卡在"设备不上报"。
```

调试用的日志级别已调回 warning，避免刷日志。

## 结论（2026-10-12，用户补充信息后）

用户确认：这台温湿度计在家里，**美的美居里显示"数据未同步，要连蓝牙或网关"**。
这一句把前面所有现象都解释了：

```text
它本身没有联网能力 —— 要么手机在它旁边用蓝牙读，要么在家放一个网关替它接
用户在学校、设备在家里 → 云上永远没有它的实时数据
于是：云侧 connected: False、lua 被跳过、Status 实体一直 unavailable
      —— 这些都不是配置错误，而是"数据根本没进云"
```

所以**走哪条路都不取决于我们这边的操作**：只要它身边没有网关、也没有一台能就近读它的机器，
HA 就不可能拿到数据。美的那个集成本身没问题（登录、家庭、设备识别都成功了）。

已做的清理：把 `midea_auto_cloud` 的条目停用（`disabled_by: user`，state 变 `not_loaded`），
日志不再每 30 秒刷 `Can't load mapping file for type T0x54`。配置保留，随时可启用。

## 三条可选的路（按成本从低到高）

```text
一  换一个能上云的温湿度计
   米家系最省事：它的数据进米家云，而我们已装的 xiaomi_home 集成直接就能导入，零新代码
   若换成 Wi-Fi 型的美的，则用已经装好的 midea_auto_cloud（内置映射里有对应类型即可）

二  在家里放美的的网关
   就是 App 提示里的"要连蓝牙或网关"。网关在设备旁边就近读它并上传云端，
   之后我们现装的 midea_auto_cloud 就能拿到数据。启用条目即可，不用改代码
   需要确认：美的有哪款网关支持这台温湿度计，以及它的型号

三  家里放一台常驻小主机做蓝牙读取桥
   成本最高。要复刻它的蓝牙协议（可能是私有格式、可能要配对密钥），
   而且那台机器必须常驻在设备旁边。除非你有现成的机器与时间，不建议先走这条
```

## 目录内容

```text
midea_auto_cloud-master.zip   从 GitHub 下的源码包
extract\                       解压结果（拷进 HA 的那份就在里面）
```

这两份都是别人的代码，不按"每份代码配同名 md"的规矩逐个写说明；来源与选择依据都记在这里。
