# 09 国内可买到 Matter 小型设备调研（≤100 元，网络文章与帖子）

调研日期 2026-10-06。渠道：搜狗微信（公众号文章）+ 网页检索 + 品牌官网；
按用户要求不查淘宝/天猫，价格以文章与官网信息为准。

## 0. 结论

```text
现在（2026-10）要在国内直接买到"有明确文章记录、单件 ≤100 元"的 Matter 成品，
选择很少；最值得等的是宜家即将入华的 21 款 Matter 新品：
  已通过中国 CCC 认证，涵盖智能灯泡、无线开关、各类传感器、智能插座；
  文章口径"价格与传统 Zigbee 产品持平"；宜家中国现有 Zigbee 智能产品
  （官网搜索价格片段）：TRETAKT 插座 ¥50、TRADFRI 系列 ¥37 起
  → 预计多数 Matter 单品落在 ¥40~120，部分 ≤100
  但宜家 Matter 新品以 Thread 为主，需要 DIRIGERA 网关/Thread 边界路由器；
  截至 2026-10-06 宜家中国官网搜 "Matter" 仍是 0 件商品（尚未上架）

其他候选（实测/文章）：
  Aqara P2 门磁/人体传感器   Matter over Thread，国内首发；文章称"极具性价比"，
                            但未给价格，按海外定价推测可能 >100；且需 Thread 边界路由器
  乐天派 Matter 人体存在传感器 ¥312（京东旗舰店，传感器+支架+2米线）——超预算；
                            亮点是 Matter over WiFi，不需要额外硬件
  小米首款 Matter 灯泡       文章明确是"米家（海外区）"产品，国内买不到/需进口
  Yeelight Cube             579 元，超预算；Yeelight Pro 系列支持 Matter，
                            Pro P20 人体传感器价格未在文章给出（Pro 系列通常 >100）
  和众科技 S1 国标10A Matter 插座  有产品介绍与使用教程，价格/零售渠道未写，
                            更像方案商参考产品
  涂鸦 Matter 方案           全栈支持、白牌设备多，但文章里没有 ≤100 元的明确零售价

一句话：想 ≤100 元买 Matter，最现实的是等宜家上架（接受 DIRIGERA 网关成本），
或者关注 Matter over WiFi 的白牌/涂鸦设备（无需边界路由器，但需要自行核实价格与认证）。
```

## 1. 关键前提：Matter over WiFi 与 Matter over Thread

```text
Matter over WiFi   设备直接走 WiFi；配网用手机蓝牙，运行不需要额外硬件；
                   适合 ≤100 元预算（白牌插座/灯泡/乐天派传感器属于这类）
Matter over Thread 设备走 Thread 网络；必须有一个 Thread 边界路由器：
                   IKEA DIRIGERA、Aqara M3、Apple HomePod mini、Google Nest Hub、
                   或 HA 的 Thread 无线电（如官方 ZBT-2）
                   边界路由器本身通常 >100 元；买 Thread 设备要把这笔成本算进去
```

## 2. 候选清单（按"离 ≤100 元 + 国内可买"的距离排序）

### 2.1 宜家 21 款 Matter 新品（最接近，尚未上架）

```text
文章口径（微信公众号，2026-09）
  "宜家21款Matter新品过审入华：中国智能家居的'价格鲶鱼'来了？"
    → 21 款 Matter 新品，涵盖智能灯泡、无线开关、各类传感器、智能插座；
      已过中国合规流程，"距正式上架中国市场为时不远"
  "【行业资讯】宜家Matter智能家居即将入华：首批产品通过CCC认证"
    → 首批产品通过 CCC 认证，价格与传统 Zigbee 产品持平
  "宜家 Matter 推广：一场关于规模、价格与简洁性的考验"
    → 传感器、遥控器、空气净化产品陆续加入 Matter；宜家在研究 Matter 绑定

价格参照（宜家中国官网搜索页，2026-10-06）
  TRETAKT 智能插座       官网价格片段 ¥50
  TRADFRI 系列（灯泡等）  官网价格片段 ¥37 起
  → Matter 新品"与 Zigbee 持平"，预计多数单品 ≤100，但以官网实际上架为准

限制
  宜家 Matter 以 Thread 为主，需要 DIRIGERA 网关（Thread 边界路由器）才能用；
  DIRIGERA 本身价格需另查（通常几百元），若已有 Apple/Google 边界路由器可复用；
  宜家中国官网当前搜 "Matter" 为 0 件商品，说明尚未开卖
```

### 2.2 Aqara P2 门磁 / 人体传感器（国内已售，需边界路由器）

```text
文章
  "绿米Aqara发布旗下首款Thread产品P2门磁"（2024-04）
    → "Aqara P2门磁由我司国内首发，登陆线上平台"
  "绿米Aqara发布P2 matter over thread人体传感器"（2024-04）
    → Matter over Thread；"相对于价格高昂的 Eve Motion 来说，P2 极具性价比"

结论
  国内可买渠道存在（Aqara 线上/线下），但文章没给具体价格；
  按 P2 海外定价与"Aqara 比小米贵"的定位推测，单件可能 >100；
  且它是 Thread 设备，需 Aqara M3 网关或其他 Thread 边界路由器
  （Aqara 网关 M2 支持 Matter，但网关本身 >100）
```

### 2.3 乐天派 Matter 人体存在传感器（WiFi，超预算）

```text
文章  "我们最近又买了 5 个好用的「新玩意」"（2024-04）
  入手渠道：京东 乐天派旗舰店；入手价格 ¥312（传感器+折叠支架+2米线）
  "Matter 连接基于 Wi-Fi，无需其他硬件，只考验 AP 性能"

结论  Matter over WiFi、无需边界路由器，但 ¥312 超出 100 元预算；
      可作为"Matter 传感器确实存在且能 WiFi 直连"的证据
```

### 2.4 其他线索（不满足 ≤100 或国内不可买）

```text
小米首款 Matter 灯泡  文章"小米吹响了进军matter的号角"（2026-04）
                      16M 色、2700K–6500K，价格定位亲民；但明确写"米家（海外区）"
                      → 国内不销售，需要进口/海外区账号
Yeelight Cube         Matter 协议，579 元（小米有品）→ 超预算
Yeelight Pro P20      首款支持 Matter 的人体存在传感器（2023-01 合作稿），
                      Pro 系列全系支持 Matter；价格未写，Pro 系列通常 >100
和众科技 S1 插座      "S1智能插座(国标10A Matter版)"产品介绍与使用教程；
                      国标 10A、Matter 认证；价格与零售渠道未写
涂鸦（Tuya）          Matter 全栈方案、白牌设备多；文章集中在方案与认证，
                      没有给出具体 ≤100 元的零售型号与价格
```

## 3. 市场层面的旁证

```text
"Matter 认证设备价格普遍高于普通设备"（"告别乱买和瘫痪!智能家居8大主流协议优缺点与终极选型指南"）
"欧瑞博价格比非Matter版贵10-20%"（AWE2026 智能家居实战文章）
"基础类传感器（如温湿度、门磁）价格已降至几十元"——这是 Zigbee 口径，
  Matter 版本通常更贵；温湿度计、门磁、插座在 Matter 认证品类里都存在
（"Matter协议能否拯救智能家居设备间的互联互通?"提到 1000+ 认证产品里
  包括遮挡传感器、环境温湿度计、智能插座、门锁、照明等）
```

## 4. 接入 HA 的条件（官方 Matter 集成）

```text
HA 有官方集成   https://www.home-assistant.io/integrations/matter/
                官方说明：推荐在 Home Assistant OS 上运行 Matter app
                （"this is currently the only supported option"）；
                Container 安装要自己跑 Matter server 的 Docker 镜像，
                官方标注 at your own risk

配网            用 Home Assistant Companion 手机 App 完成（手机蓝牙下发网络凭证）；
                Matter 设备也可以同时加入 Apple Home / Google Home（multi-admin）

网络前提        Matter 走 IPv6；Thread 设备必须有 Thread 边界路由器；
                同一局域网/VLAN，别开 AP 隔离

对我们这台机器  当前 HA 跑在 Docker Desktop 上（IPv6 关闭、NAT 网络），
                19 号文档已实测：Matter 在本机"有集成但跑不动"；
                要买 Matter 设备，先把 HA 换成 HA OS（树莓派等，见 20 号文档），
                或者准备一个支持 Thread 边界路由器的环境
```

## 5. 建议的采购顺序（≤100 元目标）

```text
第一优先   等宜家 Matter 新品上架（官网/门店），优先看灯泡、插座、温湿度/门磁传感器；
           价格预计与 Zigbee 持平（参照 TRETAKT ¥50、TRADFRI ¥37 起）；
           同时确认是否需要 DIRIGERA 网关（Thread 边界路由器）
第二优先   Matter over WiFi 的白牌/涂鸦设备（不需要边界路由器）；
           文章里没有可靠价格，买前要自己核实 Matter 认证与 HA 兼容性
不建议     为了 ≤100 元去买需要额外几百元边界路由器的 Thread 传感器；
           除非你已经有 Apple HomePod mini / Google Nest Hub / DIRIGERA / Aqara M3
提醒       单件 ≤100 不等于总成本 ≤100；Thread 路线的门槛在边界路由器
```

## 6. 来源与检索说明

```text
检索渠道   搜狗微信搜索（公众号文章标题与摘要）；搜狗网页/Bing 中文检索受限；
           价格参照用宜家中国官网搜索页（ikea.cn）
文章清单   "宜家21款Matter新品过审入华：中国智能家居的'价格鲶鱼'来了？"（2026-09）
           "【行业资讯】宜家Matter智能家居即将入华：首批产品通过CCC认证"
           "宜家 Matter 推广：一场关于规模、价格与简洁性的考验"
           "绿米Aqara发布旗下首款Thread产品P2门磁"（2024-04）
           "绿米Aqara发布P2 matter over thread人体传感器"（2024-04）
           "我们最近又买了 5 个好用的「新玩意」"（乐天派 ¥312，2024-04）
           "小米吹响了进军matter的号角"（2026-04，米家海外区）
           "新品 | Yeelight 推出 Cube 魔方智能灯：Matter 协议、可自定义，579 元"
           "【产品介绍】S1 Matter智能插座" / "【使用教程】S1智能插座(国标10A Matter版)"
           "涂鸦智能领跑Matter全球市场应用" / "Matter1.2标准正式发布，涂鸦智能持续推进应用落地"
           "告别乱买和瘫痪!智能家居8大主流协议优缺点与终极选型指南"
           "AWE2026智能家居实战:零基础搭建全屋AI系统(附海尔/追觅/华为方案对比)"
官网       https://www.ikea.cn/cn/zh/search/products/?q=TRETAKT （价格片段 ¥50）
           https://www.ikea.cn/cn/zh/search/products/?q=TRADFRI （价格片段 ¥37 起）
           https://www.home-assistant.io/integrations/matter/ （HA 官方 Matter 集成）
未确认     IKEA 中国 Matter 具体型号/价格/上架时间；Aqara P2 国内价格；
           HooRii S1 零售渠道；涂鸦白牌 Matter 的 ≤100 元零售型号
```
