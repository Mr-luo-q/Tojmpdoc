# Home Assistant 构建文档（Android 手机 · proot 容器方案）

构建日期：2026-10-03
设备：华为 Pura 70 Pro+（HBN-AL80），Kirin 9010，Android 12，16 GB
目标：不使用 Docker、不需要 root，在手机上跑起 Home Assistant Core

---

## 一、结论

**已成功。** Home Assistant Core **2026.2.3** 运行在 Debian 13 容器内，HTTP 正常响应，
页面标题为 `<title>Home Assistant</title>`，日志零错误。

关键判断：**这件事根本不需要 Docker。** 网络上「手机跑 Home Assistant 要装 Docker」
的说法混淆了两件事，实际可行的路径是 proot 容器 + pip 安装 HA Core。

```text
需求           在手机上运行 Home Assistant
                    │
        ┌───────────┴───────────┐
        │                       │
   Docker 路线               proot 路线
   （走不通）                （本次采用）
        │                       │
   dockerd 需要             proot 做系统调用转译
   ① namespace             不是内核隔离
   ② cgroup 写权限         → 不需要任何特权
   ③ overlayfs 挂载         → 普通 Android 应用即可
   Android 应用一样都拿不到
```

---

## 二、最终架构

```text
Android 12（无 root）
│
└─ Termux（普通应用，UID 10279）
     │
     ├─ ~/start-homeassistant.sh      启停脚本（Termux 侧）
     │    └─ 用 setsid 把整个 login 会话脱离 ← 关键，见坑 ⑤
     │
     └─ proot-distro login debian     proot 容器会话
          │
          └─ Debian GNU/Linux 13 (trixie)   rootfs 来自 linuxcontainers.org
               │
               ├─ /usr/bin/python3        3.13.5（Debian 自带）
               │
               └─ ~/hass-venv/            虚拟环境，1.1 GB
                    └─ hass -c ~/hass-config     ← HA 主进程
                         └─ ~/hass-config/
                              ├─ configuration.yaml
                              ├─ .storage/           运行时状态
                              ├─ home-assistant_v2.db   SQLite 数据库
                              └─ home-assistant.log
```

组件清单与来源：

| 组件 | 版本 | 来源 | 说明 |
|---|---|---|---|
| proot | 5.1.107.96 | Termux pkg | 用户态 chroot，ptrace 拦截系统调用 |
| proot-distro | 5.9.0 | Termux pkg | 容器管理，5.x 起默认从 Docker Hub 拉镜像 |
| Debian rootfs | 13.7 trixie | **images.linuxcontainers.org** | 绕开 Docker Hub，见坑 ① |
| Python | 3.13.5 | Debian 13 自带 | 决定 HA 版本上限 |
| Home Assistant Core | **2026.2.3** | PyPI | 受 Python 3.13 限制 |
| home-assistant-frontend | 20260128.6 | PyPI | Web 界面 |

---

## 三、完整构建步骤

每一步都是实际执行过的，不是设想。

### 3.1 装 proot-distro

```bash
pkg install -y proot-distro proot
```

这一步正常。Termux 源用的是 bfsu 镜像，下载 12.3 MB。

### 3.2 装 Debian rootfs（关键：绕开 Docker Hub）

**不要用 `proot-distro install debian`** —— 那条命令会去 Docker Hub 拉镜像，本机不通（见坑 ①）。

改用 linuxcontainers.org 的官方 rootfs 压缩包：

```bash
BASE="https://images.linuxcontainers.org/images/debian/trixie/arm64/default/20261003_05:24"
curl -sL -o ~/SHA256SUMS "$BASE/SHA256SUMS"
curl -L --retry 3 -o ~/debian-trixie-rootfs.tar.xz "$BASE/rootfs.tar.xz"
sha256sum ~/debian-trixie-rootfs.tar.xz     # 应等于 c65d8cfa...44646
proot-distro install ~/debian-trixie-rootfs.tar.xz --name debian
```

proot-distro 会自动识别这是「plain rootfs tarball」，通过打分目录名
（`bin`/`usr`/`etc`/`var`）自动判断需要剥掉几层路径。

实测结果：`rootfs.tar.xz` 90,363,544 字节，SHA256 与官方发行文件一致，
安装结束打印 `[*] Finished installation.`

### 3.3 装编译依赖

在容器内执行，**注意容器内也要重置 PATH**（见坑 ④）：

```bash
DTOOL='export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
proot-distro login debian -- bash -c "$DTOOL; DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
  python3 python3-venv python3-dev python3-pip \
  build-essential pkg-config autoconf \
  libffi-dev libssl-dev libjpeg-dev zlib1g-dev \
  cargo \
  libopenjp2-7-dev libtiff-dev libturbojpeg0-dev \
  tzdata ffmpeg liblapack3 liblapack-dev \
  curl ca-certificates"
```

各依赖的作用：

```text
python3-venv / python3-dev   建虚拟环境、编译 C 扩展
build-essential              编译器
libffi-dev                   cffi / cryptography 需要
libssl-dev                   cryptography 需要
libjpeg-dev / zlib1g-dev     Pillow 需要
cargo                        cryptography 在无预编译 wheel 时用 Rust 编译
libopenjp2-7-dev             HA 前端图像处理
libtiff-dev / libturbojpeg0-dev   PyTurboJPEG
tzdata                       时区，HA 必需
ffmpeg                       媒体相关集成
liblapack3 / liblapack-dev   numpy 线性代数
```

**注意不要加 `libatlas-base-dev`** —— Debian 13 已移除 atlas（见坑 ③）。

### 3.4 建 venv 并装 HA

```bash
VENV=~/hass-venv
proot-distro login debian -- bash -c "$DTOOL; python3 -m venv $VENV"
proot-distro login debian -- bash -c "$DTOOL; $VENV/bin/pip install --upgrade pip wheel setuptools"
proot-distro login debian -- bash -c "$DTOOL; $VENV/bin/pip install homeassistant"
```

耗时约 6 分钟（22:13 开始，22:19 结束）。编译了两个原生扩展：
`lru-dict`（生成 `lru_dict-1.3.0-cp313-cp313-linux_aarch64.whl`）与 `PyRIC`。

### 3.5 补装 HA 懒加载所需的组件

HA 采用懒加载，很多前端与集成依赖不会被 pip 自动拉取。不装会导致界面打不开或集成缺失：

```bash
proot-distro login debian -- bash -c "$DTOOL; $VENV/bin/pip install \
  home-assistant-frontend \
  hassil home-assistant-intents \
  numpy av mutagen pymicro-vad ha-ffmpeg PyTurboJPEG PyNaCl \
  cached-ipaddress file-read-backwards go2rtc-client async-upnp-client \
  pyspeex-noise"
```

### 3.6 打两个必需补丁

**补丁 ① ifaddr** —— Android 10+ 在 proot 内屏蔽 `getifaddrs()`，HA 启动时探测网络
会抛 `PermissionError` 直接崩：

```bash
IFADDR=$VENV/lib/python3.13/site-packages/ifaddr/_posix.py
sed -i 's/        raise OSError(eno, os.strerror(eno))/        return []/' $IFADDR
```

原理：让它在拿不到接口列表时返回空列表而不是抛异常。因为我们已在
`configuration.yaml` 里显式指定 `server_host: 0.0.0.0`，HA 不依赖自动探测也能监听。

**补丁 ② zeroconf** —— IPv6 接口枚举在 Android 上失败，会拖垮 USB/DHCP/天气等集成。
给 `ip6_addresses_to_indexes` 的循环体包一层 try/except，把失败网卡跳过：

```python
# $VENV/lib/python3.13/site-packages/zeroconf/_utils/net.py
    for iface in interfaces:
        try:
            if isinstance(iface, int):
                result.append((interface_index_to_ip6_address(adapters, iface), iface))
            elif isinstance(iface, str) and ipaddress.ip_address(iface).version == 6:
                result.append(ip6_to_address_and_index(adapters, iface))
        except Exception:
            pass          # ← 吞掉失败网卡，继续处理其余接口
```

### 3.7 写配置

```yaml
# ~/hass-config/configuration.yaml
homeassistant:

http:
  server_host: 0.0.0.0    # 必须是 0.0.0.0，否则只有本机能访问
  server_port: 8123

mobile_app:

default_config:
```

`server_host` 这一行同时是补丁 ① 能生效的前提。

### 3.8 启动

**必须用 Termux 侧的 `setsid` 把整个 login 会话脱离**（见坑 ⑤）：

```bash
setsid proot-distro login debian -- \
  ~/hass-venv/bin/hass -c ~/hass-config > ~/hass.log 2>&1 < /dev/null &
```

实测启动后 **10 秒内** 8123 端口即返回 HTTP 302。

---

## 四、六个坑（全部实际踩过）

### ① Docker Hub 不通 —— 拦路虎

```text
[*] Installing 'debian:latest' as 'debian'...
[*] Authenticating with registry (anonymous)...
[*] Authenticating library/debian: attempt 1/5 failed
    (<urlopen error [Errno 110] Connection timed out>); retrying in 5s...
... 重试 5 次后
[!] Failed to install: Network error
```

proot-distro 5.0 起改用 Docker OCI 镜像仓库作为 rootfs 来源，而本机到 Docker Hub 全断。

各源实测可达性：

| 源 | 结果 | 判定 |
|---|---|---|
| `auth.docker.io` / `registry-1.docker.io` / `hub.docker.com` | HTTP 000 | 不通 |
| `dockerproxy.com` / 腾讯云镜像 | HTTP 000 | 不通 |
| `docker.m.daocloud.io/v2/` | HTTP 401 | 通（401 = 服务在，需令牌） |
| `ghcr.io` / `quay.io` / `registry.gitlab.com` | HTTP 401 | 通 |
| `deb.debian.org` / 清华 / 阿里 | HTTP 200 | 通 |
| **`images.linuxcontainers.org`** | **HTTP 200** | **采用** |

**解法**：从 linuxcontainers.org 下官方 `rootfs.tar.xz`，用 proot-distro 的本地包安装模式。

顺带一条经验：**401 不等于不通**。它说明服务端在正常响应、只是需要认证，与
`HTTP 000`（连 TCP 都没建立）是两回事。判断源是否可用时要区分。

### ② run-as 下 HOME 与 PREFIX 都不对

通过 `adb shell run-as com.termux` 执行脚本时：

```text
HOME   = /data/user/0/com.termux        ← 不是 Termux 真正的家目录
PREFIX = （空）
PATH   = /product/bin:/apex/...:/system/bin    ← 完全没有 Termux 的 bin
```

后果有三个，而且表现各不相同，很容易误判：

```text
日志写到错误位置     $HOME/ha-install.log 落到了 /data/user/0/com.termux/
                     排查时一直找不到，以为脚本没运行
proot-distro 找不到 proot   报 "Error: proot utility does not exist"
                     ← 其实 proot 装好了，只是 PATH 里没有它
工具"时有时无"       setsid 能执行但 command -v 找不到
                     ← 同一个 PATH 原因
```

**解法**：凡是从 adb 调用的脚本，开头必须写：

```bash
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"
```

### ③ libatlas-base-dev 在 Debian 13 已移除

```text
E: Package 'libatlas-base-dev' has no installation candidate
install_rc=100
```

**一个包不存在会让整个 apt 事务失败**，前面列的其他包一个都不会装上。
去掉它，用 `liblapack3 liblapack-dev` 即可。

### ④ proot 把 Termux 的 PATH 带进容器

这是最隐蔽的一个坑，它会让你误判容器环境：

```text
未重置 PATH 时   容器内 python3 → 3.14.6   ← 其实是 Termux 的 Python
重置 PATH 后     容器内 python3 → 3.13.5   ← 这才是 Debian 自己的
```

后果：pip 编译 C 扩展时链接的是 Termux 的目标环境，而不是容器内的。
本机 `clang` 一度报 21.1.8（Termux 的版本），而 Debian 13 自带的是 19。

**解法**：在容器内执行命令时统一带上 PATH 前缀：

```bash
DTOOL='export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
proot-distro login debian -- bash -c "$DTOOL; <命令>"
```

**这个坑直接改变了版本结论**：发现它之前以为容器里是 Python 3.14.6
（可以上最新 HA），发现后才确认是 3.13.5（只能到 2026.2.x）。

### ⑤ proot 的 --kill-on-exit 让后台进程活不下来

从 proot-distro 的输出可以看到它给 proot 加了 `--kill-on-exit`
（见第五节的进程命令行）。这个选项会在 login 会话退出时**杀掉容器内所有进程**。

因此下面两种写法都无效：

```bash
# 写法 A：容器内 nohup —— 失败
proot-distro login debian -- bash -c "nohup $VENV/bin/hass -c $CFG > log 2>&1 &"
# 结果：连日志文件都没生成

# 写法 B：容器内脚本里 setsid —— 同样失败
proot-distro login debian -- bash -c "/usr/local/bin/ha-run"
# ha-run 内部用 setsid 双 fork，结果同上
```

**解法**：脱离动作必须发生在 **Termux 侧**，把整个 `proot-distro login` 会话脱离：

```bash
setsid proot-distro login debian -- $VENV/bin/hass -c $CFG > ~/hass.log 2>&1 < /dev/null &
```

验证生效的方法 —— 看进程的 PPID：

```text
PID=10314  PPID=1        proot --kill-on-exit ...
           父进程: 已终止/由 init 接管     ← 这一行就证明脱离了
PID=10328  PPID=10314    hass-venv/bin/python3 .../hass
```

### ⑥ 补丁不打就崩

见 3.6 节。`ifaddr` 不打，HA 启动即抛 `PermissionError`；
`zeroconf` 不修，网络相关集成报错。

---

## 五、验证记录

### 服务可达性

```text
/                    HTTP 200
/auth/authorize      HTTP 200
/manifest.json       HTTP 200
页面标题             <title>Home Assistant</title>
```

### 版本

```text
Home Assistant  2026.2.3
Python          3.13.5
```

### 配置文件（首次启动后自动生成）

```text
~/hass-config/
  .HA_VERSION                  8 字节
  .storage/                    运行时状态目录
  home-assistant_v2.db         151552 字节（SQLite）
  home-assistant.log           532 字节
  home-assistant.log.1
  home-assistant.log.fault     0 字节
  configuration.yaml           322 字节
  deps/                        集成按需安装的依赖
```

### 日志错误数

```text
grep -icE 'error|traceback' ~/hass.log  →  0
```

唯一的警告是无害的：

```text
WARNING [aiohttp_fast_zlib] zlib_ng and isal are not available,
        falling back to zlib, performance will be degraded.
```

还有两条首次启动的正常提示（Recorder 发现上次会话未正常关闭，已自动结束）：

```text
WARNING [recorder.util] The system could not validate that the sqlite3 database
        at //.../home-assistant_v2.db was shutdown cleanly
WARNING [recorder.util] Ended unfinished session (id=1 ...)
```

### 进程隔离

```text
HA 进程 PPID=1        ← 已脱离 adb 会话，拔线不受影响
无 adbd 作为祖先
```

### 资源占用

```text
hass-venv        1.1 GB
hass-config      235 KB
可用内存         6.39 GB（16 GB 总内存）
磁盘剩余         237 GB
SoC 温度         49°C（空闲）
```

---

## 六、已知限制

**① 版本落后约 7 个月。** 容器内是 Debian 13 自带的 Python 3.13.5，
HA 官方 `pyproject.toml` 写的是 `requires-python = ">=3.14.2"`。
pip 只会解析到解释器能满足的最新版，所以停在 2026.2.x。

对照：同一台树莓派上跑的是 HA **2026.9.4**（镜像内置 Python 3.14.6）。

想追新版本需要给容器装 Python 3.14 —— 社区有走第三方源
（`deb.pascalroeleven.nl/python3.13` 这类）的做法，但会引入外部依赖。
本次未做。

**② mDNS 自动发现在 Android 上被禁用。** 智能设备必须**手动填 IP** 添加
（如 TP-Link Kasa）。若原树莓派环境依赖自动发现接入了一批设备，迁移后要逐个改。

**③ 没有加载项（Add-on）。** HA Core 模式不带 Supervisor。但树莓派用的
Home Assistant Container 模式同样没有，所以这不是迁移带来的新增损失。

**④ proot 的性能开销。** proot 用 ptrace 拦截每个系统调用，文件系统密集操作
（编译、包管理）明显慢于原生。这是安装耗时较长的原因之一。

**⑤ 空间可能缓慢增长。** 社区有人报告 proot 容器跑几个月后占满手机存储
（重启 distro 即恢复）。本机尚未观察到，但值得定期检查。

**⑥ 与 llama-server 叠加时的发热。** 本机已实测热降频能吃掉 4 倍性能
（详见 `提速调研报告.md`）。两个长期服务并存会更容易触发降频。

---

## 七、日常使用

```bash
bash ~/start-homeassistant.sh          # 启动（后台脱离运行）
bash ~/start-homeassistant.sh stop     # 停止
bash ~/start-homeassistant.sh status   # 查看状态与地址
bash ~/start-homeassistant.sh log      # 查看日志尾部
```

访问地址：

```text
手机本机      http://127.0.0.1:8123
局域网其他设备 http://<手机IP>:8123
```

首次访问需要在浏览器里创建管理员账户，数据仅存本机。

**服务不会随手机重启自动启动。** 需要重新执行 `bash ~/start-homeassistant.sh`。
若要做到开机自启，可以配合 Termux:Boot 应用，把启动脚本放进
`~/.termux/boot/`（本次未做）。

---

## 八、如果要搬到手机上，先想清楚

这台手机上的 HA 是**实验性质**的。决策前对照下面几点：

| 维度 | 树莓派（现有） | 手机（本次搭建） |
|---|---|---|
| HA 版本 | 2026.9.4 | 2026.2.3 |
| 供电 | 7×24 专用电源 | 手机电池 + 充电器 |
| 稳定性 | 无电池管理与后台回收 | 受 Android 内存/电量管控 |
| mDNS 自动发现 | 正常 | 不可用，需手动填 IP |
| 加载项 | 无 | 无（两者相同） |
| 网络 | 千兆有线 | WiFi，且 proot 下接口探测已被 patch |
| 优势 | 稳定、版本新 | 自带电池（相当于内置 UPS）、有屏幕可当面板 |

**相对更省事的替代方案**：如果目标只是「随时查看/控制」，
手机装 Home Assistant App 连树莓派那台即可，不必在手机上跑服务。
如果目标是「让 HA 用上本地大模型」，把树莓派的 HA 指向手机上
llama-server 的 OpenAI 兼容接口（`http://<手机IP>:8080/v1`）更直接。
