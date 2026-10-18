# onboard.py

## 职责

把新建的沙盒 HA 实例初始化完，并签发一枚长期访问令牌——全程走 HTTP 与 WebSocket API，不需要打开浏览器点引导页。仓库脚本默认从 `_secrets\ha_token.txt` 读令牌，这个脚本就是那份令牌的生产者。

## 输入

```text
命令行    无参数
前置      HA 已经在 127.0.0.1:8123 起来
          若 _secrets\ha_sandbox_credentials.txt 已存在，则走登录流程，不重建账号
依赖      websockets
```

## 输出

```text
_secrets\ha_token.txt                  长期令牌（单行），lifespan 3650 天
_secrets\ha_sandbox_credentials.txt    沙盒 HA 的登录用户名与密码（各一行）
```

两个文件都在 `_secrets\` 下，该目录被 `.gitignore` 的 `/_secrets/` 排除，不进仓库。

## 读取

`_secrets\ha_sandbox_credentials.txt`（存在则读，不存在则跳过）。

## 写入

```text
HA 侧     建 owner 账号（首次）、走完 onboarding 三步、签发长期令牌
文件侧    上面两个文件
```

## 调用顺序

```text
1  get_auth_code()
     凭据文件不存在 → POST /api/onboarding/users 建号，返回 auth_code
     凭据文件存在   → POST /auth/login_flow 起流程
                      POST /auth/login_flow/{flow_id} 提交用户名密码，拿到 auth_code
2  POST /auth/token 用 auth_code 换 access_token
3  finish_onboarding()  依次 POST core_config / analytics / integration，失败只提示
4  create_long_lived_token()  走 WebSocket 命令 auth/long_lived_access_token
5  令牌落盘
```

## 不负责

不改 HA 的配置目录，不装任何集成（MQTT 由 `add_mqtt.py` 装，小米走浏览器登录），不处理二次签发失败。

## 失败时返回什么

```text
HTTP 错误    urllib 抛 HTTPError，带状态码
签发失败     抛 RuntimeError("签发长期令牌失败：…")，把 HA 的原始返回打出来
已知行为     复跑时签发新令牌会返回 unknown_error（HA 侧行为，未深究）；
             已有令牌不受影响，脚本报错不改变现状
```

## 对应文件

```text
_work\ha\onboard.py            本文件
_work\ha\add_mqtt.py           下一步：装 MQTT 集成
_work\ha\compose.yaml          它服务的那个 HA 容器
_work\02_本机部署记录.md         第 3 节记了这次初始化的完整经过
```
