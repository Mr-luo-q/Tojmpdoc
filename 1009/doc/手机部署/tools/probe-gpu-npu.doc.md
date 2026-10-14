# probe-gpu-npu.ps1 说明

## 这是什么

电脑侧的 GPU / NPU 探测驱动脚本。它做三件事：把 `gpu-npu-probe.sh` 推进手机、用 adb 执行、把完整输出抓回本地存成带时间戳的报告文件。

存在的意义是解决两个实际麻烦：一是 `adb shell` 跑长输出时中文与换行容易被 PowerShell 管道破坏；二是探测结果需要留档，方便和后续轮次对照。

## 输入

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `-Serial` | 否 | 自动取唯一在线设备 | adb 序列号 |
| `-OutDir` | 否 | `<项目根>\probe-reports` | 报告输出目录 |
| `-Tail` | 否 | `200` | 终端回显的行数上限（完整内容永远写文件） |

## 输出

```text
<OutDir>\probe-<序列号>-<yyyyMMdd-HHmmss>.log     完整原始输出，UTF-8
```

序列号里的非法文件名字符会被替换成下划线，避免路径出错。

## 执行流程

```text
1. adb start-server
2. 确定目标设备：-Serial 优先，否则取 devices 里状态为 device 的第一条
      unauthorized → 明确提示去手机上点「允许 USB 调试」后退出
      无设备       → 明确提示检查 USB 调试开关与数据线后退出
3. adb push tools/gpu-npu-probe.sh → /data/local/tmp/gpu-npu-probe.sh
4. adb shell sh /data/local/tmp/gpu-npu-probe.sh
5. 输出写入报告文件，终端回显末尾 -Tail 行
```

## 用法

```powershell
# 默认：自动找设备，报告写到 .\probe-reports
powershell -ExecutionPolicy Bypass -File tools\probe-gpu-npu.ps1

# 指定设备，只回显末尾 400 行
powershell -ExecutionPolicy Bypass -File tools\probe-gpu-npu.ps1 -Serial 7LPRYTBYU8NRY5SC -Tail 400
```

## 两个容易踩的坑

**1. 脚本必须存成 UTF-8 with BOM。** PowerShell 5.1 按系统 ANSI 代码页解析 `.ps1`，无 BOM 的中文会被解析成乱码，报 `The string is missing the terminator` 这种莫名其妙的语法错误。`deploy-to-phone.ps1` 已经带了 BOM，本脚本也已补上。

**2. `-split "`r?`n"` 这种写法会破坏解析。** 反引号在双引号字符串里是转义引导符，`r` 不是合法转义序列，解析器会吃掉后面的引号导致整个文件语法崩掉。正确写法是 `-split '\r?\n'`（单引号正则）。

## 不负责

不装 Termux、不推模型、不改手机任何状态。推送的探测脚本内部全是只读命令。

## 对应文件

- `tools/probe-gpu-npu.ps1` 本脚本
- `tools/gpu-npu-probe.sh` 手机端执行的探测脚本
- `tools/gpu-npu-probe.doc.md` 探测脚本的说明
