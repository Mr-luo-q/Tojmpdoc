# ha_api.py

## 职责

给树莓派上那台 HA（HA Container）做接口调用：用账号密码换 access_token，
再把 REST 与 WebSocket 两条通道暴露成命令行。

存在的理由：本机那套 HA 工具（`_tools\`、`_work\ha\*.py`）都指向 Windows 沙盒那台 HA，
令牌也绑在那边；树莓派上是另一个实例、另一套账号，需要一个独立的入口。

## 输入

```text
--base        HA 地址，默认 http://192.168.137.2:8123（网线直连时的树莓派）
--user        默认 pi
--password    默认取部署记录里的那套 HA 登录口令

子命令
  entries [domain]       列配置条目；给 domain 就只看那一个集成
  get <path>             REST GET，例如 get /api/config
  post <path> <json>     REST POST，例如 post /api/config/config_entries/flow '{"handler":"bluetooth"}'
  delete <path>          REST DELETE
  ws <type> [json]       WebSocket 发一条命令，例如 ws config_entries/get '{"domain":"bluetooth"}'
```

## 输出

```text
entries           一行汇总 + 每个条目一行：domain / state / title / disabled_by
get/post/delete   [HTTP 状态码] + 响应正文（截前 4000 字符）
ws                原始 JSON 回执
```

## 读取

HA 的公开 HTTP 与 WebSocket 接口。不读也不写本地文件。

## 写入

由子命令决定：`post` / `delete` 会真的改 HA（建条目、跑配置流程、删条目）。
脚本自身不落任何本地文件，也不保存 token（每次现登）。

## 不负责

不保存会话、不解析实体状态（要读状态用 `get /api/states`）、
不管树莓派的 SSH（那是 `ssh_run.py` 的活）、不做批量操作。

## 失败时返回什么

```text
登录失败      打印 HA 返回的 errors 字段，退出码 1
HTTP 4xx/5xx  打印状态码与正文，退出码 1
连不上        抛 requests 的异常
```

## 对应文件

```text
_work\pi\ha_api.py                          本文件
_work\pi\ha_api.md                          这份说明
_work\pi\ssh_run.py / ssh_run.md            树莓派上的命令执行（走 SSH）
D:\项目\树莓派\HomeAssistant容器部署记录.md     树莓派 HA 的部署参数与登录方式
```
