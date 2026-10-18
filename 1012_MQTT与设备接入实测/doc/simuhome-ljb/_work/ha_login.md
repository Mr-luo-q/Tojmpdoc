# ha_login.ps1

## 职责

用一个带 DNS 映射的浏览器专用窗口打开沙盒 HA，解决小米登录的回跳问题，且不需要管理员权限。

原理是 Chromium 的 `--host-resolver-rules="MAP homeassistant.local 127.0.0.1"`：只在这个进程内把域名映射到本机，不动系统的 hosts 文件。

## 输入

```text
命令行    无参数
自动探测  Edge 与 Chrome 的四个常见安装路径，取第一个存在的
```

## 输出

```text
已用「<浏览器可执行文件>」打开专用窗口（这个窗口里 homeassistant.local 解析到 127.0.0.1）
接下来的四步操作提示（登录 → 添加集成 → 选区域 → 登录小米账号）
```

## 读取

浏览器安装路径；本目录下的 profile 名（`edge-ha-profile` 或 `chrome-ha-profile`）。

## 写入

```text
启动浏览器进程，profile 落在 _work\<浏览器名>-ha-profile\
不改 hosts，不改系统 DNS 设置
```

## 两个必须遵守的条件

```text
1 必须用独立 profile。
  浏览器已经在运行时，新起的进程只会把 URL 转给已有进程，命令行参数会被丢掉，
  映射就不生效了。

2 Edge 与 Chrome 都要试。
  两者都是 Chromium 内核，同一个参数都支持（两个都实测过）。
  脚本优先 Edge（用户实际使用），找不到再退到 Chrome。
```

## 不负责

不改 hosts（那是 `fix_hosts.ps1`），不代替人输账号密码，不管理浏览器 profile 的生命周期。

## 失败时返回什么

```text
找不到浏览器  打印提示"请改用 fix_hosts.cmd"，exit 1
```

## 双击入口（ha_login.cmd）

`ha_login.cmd` 是三行包装：`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ha_login.ps1"` 加一句 `pause`。`%~dp0` 指向本文件所在目录；`pause` 让窗口留住，方便看"已用哪个浏览器打开"与"接下来做什么"这两段提示。它不透传参数。

## 对应文件

```text
_work\ha_login.ps1       本文件
_work\ha_login.cmd       双击入口（见上一节）
_work\fix_hosts.ps1      需要全局生效时的替代方案
_work\03_层三米家接入.md   第 2 节两种解法的比较
```
