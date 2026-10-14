# start-homeassistant.sh 说明文档

## 一、职责

在手机 Termux 里启动 / 停止 / 查询 Home Assistant，并查看日志。
它解决的**核心问题是进程脱离** —— HA 跑在 proot 容器里，
而 proot 默认带 `--kill-on-exit`，会话一退出就杀掉容器内所有进程。
这个脚本把脱离动作放在正确的一层完成。

```text
输入                                   输出
──────────────────────────────────────────────────────────────
start（默认）   启动 HA               后台常驻的 proot 会话 + hass 进程
stop            停止 HA               杀掉相关进程
status          查看状态              打印 HTTP 状态码、地址、HA 版本
log             查看日志              打印 hass.log 尾部 40 行
```

## 二、命令行用法

```bash
bash ~/start-homeassistant.sh          # 启动
bash ~/start-homeassistant.sh stop     # 停止
bash ~/start-homeassistant.sh status   # 状态
bash ~/start-homeassistant.sh log      # 日志
```

脚本内可调的两个常量：

| 变量 | 值 | 含义 |
|---|---|---|
| `PORT` | `8123` | HA 监听端口 |
| `HOME_DIR` | `/data/data/com.termux/files/home` | Termux 真家目录（不依赖 `$HOME`，原因见第四节） |

## 三、它替你挡掉的两个坑

**第一，PATH 缺失。** 通过 `adb shell run-as com.termux` 调用时，
环境里的 `PATH` 只有 `/product/bin:/apex/...:/system/bin`，**完全不含 Termux 的 bin 目录**。
后果是 `proot-distro` 找不到 `proot`，会报：

```text
Error: proot utility does not exist on your system.
Install it with: pkg install proot
```

而实际上 proot 早就装好了。脚本开头显式导出 PATH 来避免这个误判。

**第二，进程脱离的层次搞错。** 见下节，这是本脚本存在的主要理由。

## 四、为什么必须用 Termux 侧的 setsid

这是本次构建踩得最久的一个坑，值得单独讲清楚。

proot-distro 给 proot 传的参数里带 `--kill-on-exit`，可以从进程命令行看到：

```text
PID=10314  proot --kill-on-exit --link2symlink --sysvipc --kernel-release=... 
```

这个选项的语义是：**login 会话结束时，杀掉容器内所有进程**。
所以只要脱离动作发生在容器内部，无论怎么写都活不下来：

```text
写法 A：容器内 nohup
  proot-distro login debian -- bash -c "nohup hass -c $CFG > log 2>&1 &"
  结果：连日志文件都没生成 —— 进程在命令返回的瞬间就被清了

写法 B：容器内 setsid 双 fork
  proot-distro login debian -- bash -c "/usr/local/bin/ha-run"   # 内部用 setsid
  结果：同上

写法 C：Termux 侧 setsid（本脚本采用）
  setsid proot-distro login debian -- hass -c $CFG > ~/hass.log 2>&1 &
  结果：成功，10 秒内 8123 返回 HTTP 302
```

原因在于脱离必须发生在**被 kill 的那一层之外**。写法 C 让整个
`proot-distro login` 进程成为新会话的首进程，它不再隶属于发起它的 shell，
因此 login 会话不会因为调用方退出而结束。

验证方法：看 HA 相关进程的 PPID。`PPID=1` 表示已由 init 接管，脱离成功。

```text
PID=10314  PPID=1        proot --kill-on-exit ...     ← 脱离成功
PID=10328  PPID=10314    hass-venv/bin/python3 .../hass
```

## 五、内部函数

| 函数 | 职责 |
|---|---|
| `lan_ip()` | 从 `ifconfig` 提取非 127.0.0.1 的 IPv4，用于打印局域网访问地址 |
| `hass_pids()` | 遍历 `/proc/*/cmdline`，按命令行内容匹配出 HA 的 python 进程。不用进程名匹配，因为容器内外进程名都是 `python3`，会误伤 |
| `stop_ha()` | 两轮清理：先杀带 `--kill-on-exit` 的 proot 会话（它会连带清理容器内进程），再补杀残留的 hass 进程 |
| `status_ha()` | 请求 8123 根路径，按 HTTP 状态码判断存活（200 或 302 都算正常），并读取 `.HA_VERSION` 显示版本 |
| `start_ha()` | 先探活避免重复启动；清掉旧进程；用 `setsid` 脱离启动；轮询最多 320 秒等就绪 |

启动就绪的判定是轮询 `http://127.0.0.1:8123/` 直到返回 200 或 302，
每 8 秒一次、最多 40 次。用轮询而不是固定 `sleep`，因为首次启动要初始化
`.storage` 与各集成，耗时随配置增长。

## 六、实测验证状态

**已验证的事实**

| 验证项 | 结果 |
|---|---|
| `status` 子命令 | 通过，输出 `正在运行（HTTP 302）`、地址、版本 2026.2.3 |
| `stop` 子命令 | 通过，输出 `已停止 Home Assistant` |
| `start` 子命令（完整流程） | 通过，输出 `Home Assistant 已就绪` 并给出两个地址 |
| 进程脱离 | 通过，`PPID=1`，无 adbd 祖先 |
| HA 服务本身 | 通过，`/`、`/auth/authorize`、`/manifest.json` 均 HTTP 200，页面标题正确 |
| 从 adb 与从 Termux 两种方式调用 | 通过（PATH 兜底同时覆盖两种情况） |

**待确认的风险**

`log` 子命令是一次 `tail`，没有跟随模式（没有 `-f`）。长时间观察需要重复执行。

脚本没有做开机自启。手机重启后需要手动执行一次。

## 七、日志与配置的位置

```text
~/hass.log                        脚本重定向的 HA 标准输出（stdout + stderr）
~/hass-config/                    HA 配置目录
  ├─ configuration.yaml           主配置（server_host 必须是 0.0.0.0）
  ├─ .storage/                    运行时状态
  ├─ home-assistant_v2.db         SQLite 历史数据库
  └─ home-assistant.log           HA 自己写的日志（与 hass.log 不同）
~/hass-venv/                      Python 虚拟环境（1.1 GB）
```

排错时的查看顺序：先 `status` 确认存活，再 `log` 看脚本捕获的输出，
最后才看 `~/hass-config/home-assistant.log` 里 HA 自己记录的详细日志。

## 八、两个使用注意事项

**服务不会随手机重启自动启动。** 这是 Android 对普通应用的限制，不是脚本问题。
需要每次手动执行 `bash ~/start-homeassistant.sh`。若要做到开机自启，
可配合 Termux:Boot 应用把脚本放进 `~/.termux/boot/`（本次未做）。

**首次启动明显慢于后续。** 首次要生成 `.storage`、初始化 `default_config`
下的全部组件、建 SQLite 库，实测约 2~5 分钟；之后启动约 20~40 秒。
脚本的就绪轮询上限按首次启动的耗时设置，所以首次使用时不要以为卡死了。
