# Home Assistant 容器模式部署记录（Raspberry Pi 4B）

部署日期：2026-10-02
设备：Raspberry Pi 4 Model B（8GB），Raspberry Pi OS 64-bit（Debian 13 trixie）

---

## 一、部署目标

在树莓派上以**容器模式**（Home Assistant Container）部署 Home Assistant，并验证：

1. 服务能否正常运行、Web 界面能否访问；
2. **外接 MCP**（HA 作为 MCP 客户端连接外部 MCP 服务器）能否正常工作；
3. HA 作为 MCP 服务器（供外部 AI 客户端调用）能否启用。

> 选择容器模式的原因：外接的 MCP 服务器通常是一个独立服务，容器模式下可以直接把
> 它作为另一个 Docker 容器跑在同一台机器上，HA 通过 `localhost` 直连；而 HAOS 模式
> 需要把服务打包成 Add-on，改造成本高。

---

## 二、环境与依赖

| 项目 | 值 |
| --- | --- |
| 系统 | Debian GNU/Linux 13 (trixie)，内核 6.18.50+rpt-rpi-v8 |
| Docker | 26.1.5（来自 Debian 官方源 `docker.io`） |
| Compose | 未使用（单容器直接 `docker run`） |
| 镜像 | `ghcr.io/home-assistant/home-assistant:stable`，2.31 GB |
| HA 版本 | 2026.9.4（内置 Python 3.14.6） |
| 镜像来源 | 经南大镜像 `ghcr.nju.edu.cn` 拉取（直连 ghcr.io 反复重试） |
| 数据目录 | `/home/pi/ha-config`（挂载到容器 `/config`） |
| 时区 | `Asia/Shanghai`（通过 `-e TZ` 传入） |

---

## 三、部署步骤

### 3.1 安装 Docker

```bash
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker pi
```

注意：官方一键脚本（`get.docker.com` → `download.docker.com`）在国内网络被重置，
必须走系统软件源。

### 3.2 拉取镜像

```bash
# 直连 ghcr.io 反复重试，改用南大镜像（断点续传，已下载的层会复用）
sudo docker pull ghcr.nju.edu.cn/home-assistant/home-assistant:stable
sudo docker tag  ghcr.nju.edu.cn/home-assistant/home-assistant:stable \
                 ghcr.io/home-assistant/home-assistant:stable
```

### 3.3 启动容器

```bash
mkdir -p ~/ha-config
sudo docker run -d \
  --name homeassistant \
  --privileged \
  --restart=unless-stopped \
  -e TZ=Asia/Shanghai \
  -v /home/pi/ha-config:/config \
  -v /run/dbus:/run/dbus:ro \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable
```

要点：

- `--network=host` 是必须的，HA 依赖主机网络做设备发现（mDNS 等）。
- `--privileged` 用于访问 USB 设备（Zigbee/Z-Wave 棒）与蓝牙；若不接硬件可去掉。
- `-v /run/dbus:/run/dbus:ro` 提供蓝牙相关的 D-Bus 访问。

### 3.4 初始化账号

通过 onboarding API 完成（也可直接在浏览器里点）：

```bash
POST /api/onboarding/users   {"client_id":"http://<IP>:8123/","name":"Pi",
                              "username":"pi","password":"<密码>","language":"zh-Hans"}
POST /api/onboarding/core_config
POST /api/onboarding/analytics  {"analytics": false}
```

---

## 四、验证结果

### 4.1 服务可用性

| 检查项 | 结果 |
| --- | --- |
| 8123 端口 | ✅ 可访问 |
| Web 首页 | ✅ HTTP 200，标题 `Home Assistant` |
| onboarding API | ✅ 返回 4 个待完成步骤，并成功完成 |
| HA 版本 | 2026.9.4 |
| 容器状态 | ✅ `Up`，`--restart=unless-stopped` 已设置 |
| 空闲资源占用 | CPU 约 1.4%；系统整体内存占用 853 MiB / 7.6 GiB |

### 4.2 MCP 能力验证

镜像内置两个 MCP 集成（均来自 HA Core，非 Add-on）：

| 集成 | 名称 | 作用 | 验证结果 |
| --- | --- | --- | --- |
| `mcp` | Model Context Protocol | HA 作为**客户端**连接外部 MCP 服务器 | ✅ 成功接入测试服务器，状态 `loaded` |
| `mcp_server` | Model Context Protocol Server | HA 作为**服务器**被外部调用 | ✅ 已安装，状态 `loaded`（SSE 端点 `/mcp_server/sse`） |

外接 MCP 端到端测试：

1. 在同一台树莓派上启动了一个演示用 MCP 服务器（容器 `mcp-demo`，FastMCP，端口 8765，暴露 3 个工具）。
2. 在 HA 里添加该 MCP 服务器（URL：`http://127.0.0.1:8765/mcp`），配置流直接创建成功，
   集成列表中显示 `mcp | raspberry-pi-demo | loaded`。
3. 用 MCP 客户端协议握手并列出工具，返回 3 个工具（`get_server_time`、`get_system_info`、`echo`），
   说明协议链路完整可用。

**结论：容器模式下，外接 MCP 功能可以正常运行。**

### 4.3 外接 MCP 的接入方式

在 HA 界面：`设置 → 设备与服务 → 添加集成 → 搜索 "Model Context Protocol"`，
填写外部 MCP 服务器的 **URL**（例如 `http://主机:端口/mcp`）即可。

该集成支持两种鉴权方式：

- 无鉴权（内网服务，直接填 URL）；
- OAuth（会自动探测 `/.well-known/oauth-protected-resource` 与
  `/.well-known/oauth-authorization-server`，按标准流程授权）。

---

## 五、常用运维命令

```bash
sudo docker ps                          # 查看容器
sudo docker logs -f homeassistant       # 查看日志
sudo docker restart homeassistant       # 重启
sudo docker stop homeassistant          # 停止
sudo docker rm -f mcp-demo              # 删除演示 MCP 服务器（测试用，可删）

# 升级 HA
sudo docker pull ghcr.nju.edu.cn/home-assistant/home-assistant:stable
sudo docker stop homeassistant && sudo docker rm homeassistant
# 然后重新执行 3.3 的 docker run（配置目录挂载不变，数据不丢）
```

备份：直接打包 `/home/pi/ha-config` 即可（`tar czf ha-backup.tgz -C ~ ha-config`）。

---

## 六、注意事项

1. **没有 Add-ons / Supervisor**：容器模式不支持 HA 的添加商店。需要 ESPHome、Mosquitto、
   Zigbee2MQTT 等同机服务时，用 `docker run` 单独起容器即可（这也是容器模式更灵活的地方）。
2. **与本地大模型共存**：同一台树莓派上还部署了 llama.cpp（Qwen3-0.6B / Qwen2.5-1.5B）。
   HA 空闲时很轻（约 1.4% CPU），但大模型推理会占满 4 个核，两者同时重度使用会互相拖慢。
3. **安全**：容器用 `--privileged` 运行，且 HA 目前只监听内网。若要暴露到公网，
   请改用反向代理 + HTTPS，并务必修改默认密码。
4. **首次启动约 1–3 分钟**：要初始化 SQLite 数据库与配置目录，属正常现象。

---

---

## 七、本地大模型接入为对话代理（2026-10-02 补充）

### 7.1 实施内容

1. **llama-server 做成 systemd 服务**：`/etc/systemd/system/llama-server.service`，开机自启、
   崩溃自动重启，服务 Qwen2.5-1.5B（`-c 8192 -n 512 -t 4 --jinja`，监听 8080）。
2. **HA 内置 `llama_cpp` 集成**（HA 2026.9.4 自带，无需 HACS）：Base URL 填
   `http://127.0.0.1:8080/v1`，模型名取自服务返回的模型路径。
3. **虚拟设备**：`configuration.yaml` 中加入两个 template 灯（客厅灯 / 卧室灯），
   底层由 `input_boolean` 维护状态，实体为 `light.ke_ting_deng`、`light.wo_shi_deng`。
4. **子条目（subentry）配置**：提示词加入"不要传空参数"约束，LLM HASS API 同时勾选
   `assist`（控制设备）与 `mcp-<entry_id>`（外部 MCP 工具）。

### 7.2 验证结果

| 项目 | 结果 |
| --- | --- |
| llama.cpp 函数调用（直接测试） | ✅ 返回 `HassTurnOn {"name":"客厅灯"}`，finish_reason=`tool_calls` |
| 流式 + 工具调用 | ✅ 流式响应中正确输出 tool_calls |
| HA 对话代理加载 | ✅ `llama_cpp` 集成 loaded，对话实体已创建 |
| HA 端识别意图 | ✅ 模型正确选择 `HassLightSet`，实体名"客厅灯"识别正确 |
| **实际控制设备** | ❌ 失败：模型额外传了 `floor: ""`（还有 `color: ""`、`temperature: 0`），
HA 返回 `InvalidSlotInfo`，模型随后回答"对不起，我无法打开客厅的灯" |
| 响应耗时 | 单次 LLM 调用 40–50 秒；含重试的完整命令耗时 7.5 分钟（超时） |

### 7.3 结论与限制

- 链路本身是通的：**模型能理解中文指令、能选出正确的工具、能生成正确的实体名**。
- 失败原因是**参数卫生问题**：Qwen2.5-1.5B 会把工具 schema 里的所有可选字段都填上，
  包括空字符串，而 HA 的意图校验不接受空字符串槽位。
- 硬件限制明显：Pi 4B 上提示词处理只有 7–8 token/s，一次 300 token 的提示就要 40 秒，
  多轮工具调用（决定工具 → 执行 → 总结）往往超过 1 分钟。

### 7.4 可选改进方向

1. **加一层参数清洗代理**：在 HA 与 llama.cpp 之间放一个小服务，把工具调用参数里的
   空字符串/null 字段剔除后再交给 HA（改动最小、见效最快）。
2. **换更强的模型**：Qwen2.5-7B 的 Q4 量化约 4.7 GB，8 GB 内存能装下，但 Pi 4B 上
   速度会降到约 1 token/s，交互基本不可用。
3. **分工使用**：设备控制交给 HA 内置的意图引擎（毫秒级、100% 可靠），
   本地大模型只负责闲聊、解释、生成文本。

### 7.5 接入 Assist 语音助手（2026-10-02 晚）

**已完成的配置**

1. 通过 WebSocket API（`assist_pipeline/pipeline/update`）把 Assist 管线的对话代理从
   `conversation.home_assistant` 切换成 `conversation.home_pi_models_qwen2_5_1_5b_instruct_q4_k_m_gguf_2`，
   对话语言设为 `zh-Hans`。
2. 开启 `prefer_local_intents = true`：简单命令先由 HA 内置意图引擎处理（毫秒级、可靠），
   复杂问题才交给大模型。
3. 脚本 `ha-ws.ps1` 封装了登录 + WebSocket 认证 + 管线列表/更新的完整流程。

**为什么在 Assist 里"没反应"**

排查日志后确认：请求确实送到了模型，但**提示词太长**，模型还在"读题"阶段请求就被取消了。

| 证据 | 内容 |
| --- | --- |
| HA 日志 | 系统提示词包含助手规则、设备静态上下文、**14 个工具定义**（其中 3 个来自 MCP 服务器），长度约两三千 token |
| llama-server 日志 | 22:50:18 开始处理 → 22:50:58 `stop: cancel task`（40 秒时被取消，仍在提示词处理阶段） |
| 实测速度 | Pi 4B 上提示词处理 7.7 token/s → 读完 2000–3000 token 需要 **4–6 分钟** |

**结论**

- 在这台 Pi 上，**自由对话走 Assist 面板不实用**（单次要等 3–6 分钟）；
  聊天建议直接用 llama.cpp 自带的 `http://<IP>:8080` 界面（提示词短、响应快）。
- **设备控制**因为已开启"本地意图优先"，简单命令（如"打开客厅的灯"）由内置引擎秒回，
  不受大模型速度影响。
- 尚未完成：把自定义提示词进一步缩短（配置子条目时模型正忙，请求超时），
  以及"参数清洗代理"（解决空参数导致 `InvalidSlotInfo` 的问题）。

---

## 附 A：本次部署涉及的文件

| 文件 | 说明 |
| --- | --- |
| `mcp-demo/server.py` | 演示用 MCP 服务器（FastMCP，暴露 3 个工具） |
| `mcp-demo/ha-style-request.json` | 模拟 HA 调用方式的请求样例（含 tools + stream） |
| 本文件 | 部署与验证记录 |

## 附 B：实验原始证据（2026-10-02）

### B.1 模型直接函数调用（llama.cpp，绕过 HA）

请求：`user="打开客厅的灯"`，`tools=[HassTurnOn, HassTurnOff, HassGetState]`，`stream=true`

流式响应末尾的统计：

```json
{"finish_reason":"tool_calls",
 "timings":{"prompt_n":313,"prompt_per_second":7.68,
            "predicted_n":23,"predicted_per_second":2.58}}
```

模型返回的工具调用：

```json
{"type":"function",
 "function":{"name":"HassTurnOn","arguments":"{\"name\": \"客厅灯\"}"}}
```

结论：**模型的工具选择与参数生成是正确的**；瓶颈在速度——提示词处理 7.68 token/s，
生成 2.58 token/s。

### B.2 HA 对话代理调用（第一次，默认提示词）

HA 调试日志（节选）：

```
[homeassistant.components.conversation.chat_log] Tool call: light__HassLightSet(
    {'name': '客厅灯', 'area': '客厅', 'floor': '', 'domain': ['light'], 'brightness': 100})
[homeassistant.components.conversation.chat_log] Tool response:
    {'error': 'InvalidSlotInfo', 'error_text': 'Received invalid slot info for HassLightSet'}
[homeassistant.components.conversation.chat_log] Adding assistant content:
    content='对不起，我无法打开客厅的灯。我目前没有找到相关信息。'
```

HA 端警告：

```
WARNING (MainThread) [homeassistant.helpers.intent]
    Received invalid slot info for HassLightSet: string value is empty at 'floor.value'
```

### B.3 HA 对话代理调用（第二次，自定义提示词 + 勾选 MCP 工具）

```
[conversation.chat_log] Tool call: assist__light__HassLightSet(
    {'name': '客厅灯', 'area': '客厅', 'floor': '', 'domain': ['light'],
     'color': '', 'temperature': 0, 'brightness': 100})
[conversation.chat_log] Tool response:
    {'error': 'InvalidSlotInfo', 'error_text': 'Received invalid slot info for HassLightSet'}
```

耗时 447 秒（客户端超时），期间模型仍在重试。

### B.4 设备状态变化记录

| 时间点 | `light.ke_ting_deng` |
| --- | --- |
| 沟通测试前 | off |
| 第一次测试后 | off |
| 第二次测试后（自定义提示词） | off |

### B.5 环境实测数据

| 项目 | 值 |
| --- | --- |
| 模型 | Qwen2.5-1.5B-Instruct Q4_K_M（1.04 GiB，1.78 B 参数） |
| 推理后端 | llama.cpp b11256，CPU armv8.0 后端，4 线程 |
| 启动参数 | `-c 8192 -n 512 -t 4 --jinja` |
| 提示词处理 | 7.7–8.1 token/s |
| 文本生成 | 1.9–3.8 token/s |
| HA 版本 | 2026.9.4（容器模式，host 网络） |
