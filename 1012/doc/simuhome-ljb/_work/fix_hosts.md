# fix_hosts.ps1

## 职责

往 Windows 的 hosts 文件加一条 `127.0.0.1 homeassistant.local`，全局永久解决小米登录回跳断链（需要管理员权限，会弹 UAC）。

背景：上游 `XiaoMi/ha_xiaomi_home` 把 OAuth 回跳地址写死在源码里（`OAUTH_REDIRECT_URL = 'http://homeassistant.local:8123'`），而 Docker Desktop 不会把容器名注册到宿主 DNS，浏览器解析不了这个域名，登录最后一步就断在那里。

## 输入

```text
命令行    无参数
前置      需要管理员权限；未提权时脚本会自己 Start-Process -Verb RunAs 再跑一次
```

## 输出

```text
需要提权提示 / 已添加提示 / "已有该条目，无需修改"
解析结果：127.0.0.1
撤销方法说明
```

## 读取

`C:\Windows\System32\drivers\etc\hosts`（先查有没有，避免重复追加）。

## 写入

```text
追加一行            127.0.0.1 homeassistant.local
不改动已有内容      只在缺失时追加
```

## 不负责

不改 HA 配置，不重启 DNS 客户端服务，不校验 HA 是否在跑。解析测试失败时只提示等几秒或手工 `ipconfig /flushdns`。

## 失败时返回什么

```text
未提权     拉起一个新进程提权后 exit 0（原进程不再继续）
解析失败   打印提示，不报错退出
```

## 与另一条路的关系

```text
fix_hosts.ps1  提权一次，全局永久，所有浏览器和程序都生效
ha_login.ps1   不提权，用带 --host-resolver-rules 的浏览器专用窗口，
               只对那个窗口生效，重启窗口后需要重新执行
```

## 双击入口（fix_hosts.cmd）

`fix_hosts.cmd` 是三行包装：`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_hosts.ps1"` 加一句 `pause`。`%~dp0` 指向本文件所在目录，双击即可运行；`pause` 让窗口留住，方便看 UAC 提示与"解析结果"那几行。它不透传参数、不自行判断。

## 对应文件

```text
_work\fix_hosts.ps1      本文件
_work\fix_hosts.cmd      双击入口（见上一节）
_work\ha_login.ps1       免管理员的替代方案
_work\03_层三米家接入.md   第 2 节
```
