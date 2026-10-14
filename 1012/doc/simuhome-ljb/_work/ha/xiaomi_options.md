# xiaomi_options.py

## 职责

驱动 Xiaomi Home 集成的 options flow，用来强制刷新云端设备列表，把新加入米家账号的设备导进 HA。

为什么需要：官方集成把设备清单缓存在本地（`.storage\xiaomi_home\miot_devices\`），单纯重载配置条目不会回云端刷新，必须走一次 options flow。

## 输入

```text
无参数               只起流程，打印每一步的 type / step_id / flow_id / schema / errors
'<json1>' '<json2>'  依次提交这些步骤（JSON 内联）
'@step1.json'        参数以 @ 开头表示从文件读 JSON
令牌                 _secrets\ha_token.txt
集成条目 id          模块顶部的 ENTRY_ID 常量（换账号或重建条目后要改）
```

## 输出

```text
每一步的关键信息：type、step_id、flow_id、title、menu_options、data_schema（截断 1400 字）、errors
遇到 type=create_entry 打印"流程已完成"
没走完则打印当前 flow_id，提示带上下一步 JSON 再跑
```

## 读取

`_secrets\ha_token.txt`、命令行里的 JSON 或 `@文件`。

## 写入

HA 的 Xiaomi Home 集成条目（options flow 完成后会重载集成并回云端拉设备）。

## 设计取舍

这个脚本刻意做成"交互式半自动"：它不猜 schema，而是把每一步的 schema 打出来，由人决定下一步提交什么。原因是 options flow 的步骤链和字段会随集成版本变化，写死一份 payload 会在升级后失效。

Windows 控制台默认编码是 GBK，schema 里的非 GBK 字符会直接抛错，所以开头强制把 stdout 切成 UTF-8。

## 不负责

不自动推断该选哪个菜单项，不解析 schema 语义，不改集成条目以外的任何东西。

## 失败时返回什么

```text
HTTP 错误   RuntimeError("<path> -> HTTP <code>: <响应体>")
JSON 解析错 json.loads 原样抛出
```

## 对应文件

```text
_work\ha\xiaomi_options.py    本文件
_work\ha\onboard.py           令牌来源
_work\03_层三米家接入.md        层三接入的完整记录（含登录步骤）
```
