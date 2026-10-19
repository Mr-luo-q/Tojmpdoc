# deploy-mnn-bench.ps1

职责：
把固定版本的 MNN 3.6.1、Android NDK r28b 和 Qwen3.5-0.8B-MNN 模型准备到本机，交叉编译 Android arm64 的 `llm_bench` / `llm_demo`，推到手机并运行 CPU 基准。

输入：

| 参数 | 默认值 | 作用 |
|---|---|---|
| `-Root` | 脚本上一级目录 | 项目根目录 |
| `-DeviceSerial` | 空 | 指定 ADB 设备序列号 |
| `-Threads` | `4,6,8` | 要测试的 CPU 线程数 |
| `-Repeats` | `3` | 每个线程组的重复次数 |
| `-PromptLength` | `128` | 基准提示 token 数 |
| `-GenerateLength` | `64` | 基准生成 token 数 |
| `-CooldownSeconds` | `0` | 两组测试之间的等待时间 |
| `-SkipDownload` | 关闭 | 复用已有的源码、NDK、模型 |
| `-SkipBuild` | 关闭 | 复用已有的 `llm_bench` / `llm_demo` |
| `-SkipPush` | 关闭 | 不再把文件推到手机 |
| `-SkipBench` | 关闭 | 只准备部署，不跑基准 |
| `-RunDemo` | 关闭 | 跑一次固定中文提示词的端到端生成 |

输出：

```text
research/mnn-20261019/
  build/llm_bench
  build/llm_demo
  device-results/mnn-t<线程>-r<重复数>.json
  控制台线程汇总表
```

读取：

```text
MNN 源码压缩包
Android NDK 压缩包
ModelScope 上的 Qwen3.5-0.8B-MNN 模型文件
prompt-zh.txt
手机端 /data/local/tmp/mnn/results/*.json
```

环境依赖：

```text
ADB       优先用 <项目根>\tools\platform-tools\adb.exe，找不到时回退到 PATH 里的 adb
CMake     3.20 以上，当前实测为 4.4.4
Ninja     当前实测为 1.13.2
curl.exe  用于下载 NDK、MNN 源码和模型
tar.exe   用于解压 NDK 和源码包
```

写入：

```text
research/mnn-20261019/ 下的源码、模型、构建产物和结果
手机的 /data/local/tmp/mnn/ 目录
```

不负责：

```text
安装 MNN Chat APK
开关 HyperOS 的 USB 安装权限
OpenCL、NPU、GPU 后端
持续热负载和温控曲线
OpenAI 兼容 HTTP 服务
```

对应文件：

```text
tools/deploy-mnn-bench.ps1
MNN部署实测报告.md
research/mnn-20261019/README.md
```

## 调用流程

```text
参数解析
   │
   ├─ 下载并校验 NDK、MNN 源码、模型
   │       │
   │       └─ 模型 SHA-256 必须匹配
   │
   ├─ CMake 配置：Android arm64、c++_static、CPU、ARM82
   │
   ├─ Ninja 编译：llm_bench、llm_demo
   │       │
   │       └─ 临时目录固定到项目内，避开受限 TEMP
   │
   ├─ ADB 推送二进制、10 个模型文件、中文提示词
   │       │
   │       └─ 手机端再次校验 llm.mnn.weight
   │
   ├─ 按线程数跑 llm_bench
   │       │
   │       └─ JSON 拉回 device-results/
   │
   └─ 可选：跑 llm_demo 中文生成
```

## 关键实现细节

模型目录包含点号，ADB 把本地目录直接推到目标目录时可能截断路径。脚本改为逐个文件推送完整目标文件名，避免出现 `/models/Qwen3.5` 这样的截断目录。

Android 汇编编译阶段会创建临时文件。脚本在构建期间把 `TMP` 和 `TEMP` 指向 `research/mnn-20261019/tmp`，避免系统临时目录不可写导致 `unable to make temporary file: Permission denied`。

`llm_bench` 使用 MNN 自己的参数协议，不能套用 `llama-bench` 的 `-pg`、`-ngl`、`-fa`。当前脚本固定 CPU、低精度、低内存策略，测试长度通过 `-p` 和 `-n` 分别给出。

## 失败时的判断

| 现象 | 处理 |
|---|---|
| `INSTALL_FAILED_USER_RESTRICTED` | 这是 HyperOS 的 USB 安装授权拦截，脚本不处理 APK 安装 |
| `unable to make temporary file` | 检查项目内 `tmp` 是否可写，保持脚本设置的 `TMP` / `TEMP` |
| 模型 SHA-256 不一致 | 停止执行，重新下载权重，不带错误模型继续跑 |
| 手机端 `llm_bench` 无法执行 | 检查 ABI 是否为 arm64-v8a，以及 `chmod 755` 是否生效 |
| 速度突然降到三分之一 | 先查电池温度、CPU 当前频率；不要把热降频结果当作模型性能 |

## 示例

完整准备、编译、推送并跑 4/6/8 线程：

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy-mnn-bench.ps1 `
  -Threads 4,6,8 -Repeats 3
```

复用已有构建和手机文件，只跑 4 线程并做中文生成：

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy-mnn-bench.ps1 `
  -SkipDownload -SkipBuild -SkipPush -Threads 4 -Repeats 3 -RunDemo
```

两组测试之间等待 120 秒，降低前一组热状态的影响：

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy-mnn-bench.ps1 `
  -SkipDownload -SkipBuild -SkipPush -Threads 4,6,8 -Repeats 3 -CooldownSeconds 120
```
