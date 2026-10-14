# ssh_run.py

## 职责

在树莓派上跑一条或多条命令，把输出带回本机。存在的理由：Windows 自带的 `ssh` 不支持在命令行里传密码，非交互场景下没法用它登录树莓派；paramiko 可以。

## 输入

```text
--host       默认 192.168.137.50（网线直连时 DHCP 发的地址）
--user       默认 pi
--password   默认 password
             若 _secrets\pi_account.txt 存在（两行：用户名、密码），优先用它
--put 本地 远端  把一个本地文件传上去（SFTP，覆盖式）；可以给多次
--sudo       所有命令都用 sudo -S 跑；密码通过 stdin 喂进去，不出现在命令行里
位置参数      一条或多条要执行的命令，依次执行
```

## 输出

```text
已登录 <user>@<host>
$ <命令>
<stdout>
[stderr] <stderr>      有才打
[退出码 N]              非 0 才打
```

## 读取

`_secrets\pi_account.txt`（可选，被 .gitignore 排除）。

## 写入

无本地写入。远端做什么是命令自己决定的 —— 这个脚本只负责转发。

## 不负责

不做文件传输（要传文件用 scp 或另写）、不保存会话、不做交互式 shell（每条命令独立执行，`cd` 不会跨命令保留）。

## 失败时返回什么

```text
连不上     stderr 打一行原因，退出码 2
命令非 0   照常打输出，最后以最后一条命令的退出码结束
```

## 账号说明

默认账号来自 `D:\项目\树莓派\树莓派配置记录.md` 里的记录（`pi` / `password`）。那是弱口令，记录里也提示过：接入公共网络前建议换掉，或改用 SSH 密钥。

## 对应文件

```text
_work\pi\ssh_run.py                        本文件
_work\pi\ssh_run.md                        这份说明
D:\项目\树莓派\树莓派配置记录.md              账号、烧录、联网与网线直连的原始记录
_work\ble\scan.py / watch.py               要传到树莓派上跑的 BLE 工具
```
