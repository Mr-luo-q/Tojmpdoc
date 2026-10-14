<#
  手机部署 · 把 Termux、模型和安装脚本推送到安卓手机（走 USB + ADB）

  前置条件：
    1. 手机已打开「开发者选项 → USB 调试」
    2. 数据线连到电脑，手机上弹出「允许 USB 调试吗？」时点允许

  用法：
    powershell -ExecutionPolicy Bypass -File tools\deploy-to-phone.ps1
    powershell -ExecutionPolicy Bypass -File tools\deploy-to-phone.ps1 -SkipModel
#>

param(
  [switch]$SkipModel,
  [switch]$SkipInstall,
  [string]$ModelPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$adb  = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
$apk  = Join-Path $PSScriptRoot 'termux-universal.apk'
$setup = Join-Path $root 'termux-llama-setup.sh'

$modelNames = @('qwen2.5-1.5b-instruct-q4_k_m.gguf')
$modelCandidates = @()
if ($ModelPath) { $modelCandidates += $ModelPath }
foreach ($n in $modelNames) {
  $modelCandidates += (Join-Path (Join-Path $root 'models') $n)
  $modelCandidates += (Join-Path $env:USERPROFILE "Downloads\$n")
}
$model = $modelCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "[x] $msg" -ForegroundColor Red; exit 1 }

# adb 会把进度和部分提示写到 stderr，在 ErrorActionPreference=Stop 下会被当成
# 终止性错误，所以统一包一层，把 stderr 收进返回值里再处理。
function Invoke-Adb {
  param([string[]]$AdbArgs, [switch]$Show)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $adb @AdbArgs 2>&1 | Out-String
  } finally {
    $ErrorActionPreference = $prev
  }
  if ($Show -and $out.Trim()) { Write-Host $out.Trim() }
  return $out
}

if (-not (Test-Path $adb)) { Fail "找不到 adb：$adb" }
if (-not (Test-Path $setup)) { Fail "找不到安装脚本：$setup" }

Say "启动 adb 服务"
& $adb start-server | Out-Null

$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
$ready = $devices | Where-Object { $_ -match '\sdevice$' }
$unauthorized = $devices | Where-Object { $_ -match 'unauthorized' }

if (-not $ready) {
  if ($unauthorized) {
    Fail "手机已连上，但还没授权 USB 调试。解锁手机，点掉屏幕上的「允许 USB 调试」弹窗后重跑。"
  }

  $mtpName = $null
  try {
    $mtp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
      Where-Object { $_.Class -in @('WPD', 'PortableDevice', 'AndroidUsbDeviceClass') -and $_.Status -eq 'OK' }
    if ($mtp) { $mtpName = ($mtp | Select-Object -First 1).FriendlyName }
  } catch { }

  if ($mtpName) {
    Fail @"
电脑能看到手机（$mtpName），说明数据线和 USB 口没问题，但 adb 没有识别到设备。

USB 调试还没生效，按顺序检查：
  1. 开发者选项是否真的打开了（设置 → 系统 → 开发者选项）
  2. 「USB 调试」开关是否处于打开状态
  3. 下拉通知栏，把 USB 用途从「仅充电」改成「传输文件 / MTP」
  4. 手机上有没有弹出「允许 USB 调试吗」，要勾「一律允许」再点允许

然后重跑本脚本。
"@
  }

  Fail @"
电脑完全没检测到手机，先排除物理连接问题：

  1. 换一根数据线，很多线只能充电不能传数据
  2. 换一个 USB 口，优先直连主板口，别用前置面板和扩展坞
  3. 插上后手机通知栏应该出现「正在充电」，没有就是线或口的问题
  4. 确认连接无误后，再依次打开：开发者选项 → USB 调试 → 手机点「允许」

如果手边没有数据线，也可以走无线调试（安卓 11 及以上）：
  手机：设置 → 开发者选项 → 无线调试 → 使用配对码配对设备
  把屏幕上的 IP、配对端口和 6 位配对码发我，我用 adb 帮你配对。
"@
}

$serial = ($ready | Select-Object -First 1).Split()[0]
Say "已连接设备：$serial"

if (-not $SkipInstall) {
  if (-not (Test-Path $apk)) { Warn "找不到 $apk，跳过安装" }
  else {
    Say "安装 Termux（手机上如弹窗请点允许）"
    $out = Invoke-Adb @('-s', $serial, 'install', '-r', '-g', $apk)
    if ($out -match 'Success') {
      Say "Termux 安装成功"
    } elseif ($out -match 'INSTALL_FAILED_ABORTED|User rejected') {
      Warn "手机端拒绝了安装。华为等机型会在屏幕上弹确认框，需要手动点「继续安装 / 允许」。"
      Warn "请在手机上解锁并盯着屏幕，然后重新运行本脚本。"
      Warn "如果根本没有弹窗，去 设置 → 安全 → 更多安全设置，打开「外部来源应用下载」和「USB 安装」。"
    } elseif ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match') {
      Warn "手机上已装过签名不同的 Termux（多半是 F-Droid 版）。"
      Warn "已装版本可以直接用，跳过安装即可；要装这一份的话先卸载旧的。"
    } elseif ($out -match 'INSTALL_FAILED_ALREADY_EXISTS') {
      Warn "Termux 已存在，跳过安装"
    } else {
      Warn "安装返回：$($out.Trim())"
    }
  }
}

Say "创建手机目录 /sdcard/Download/termux-deploy"
Invoke-Adb @('-s', $serial, 'shell', 'mkdir', '-p', '/sdcard/Download/termux-deploy/models') | Out-Null

Say "推送安装脚本"
# 注意：源路径含中文时，用目录做目标会让 adb 把文件名截断，必须写全目标文件名
$pushScript = Invoke-Adb @('-s', $serial, 'push', $setup, '/sdcard/Download/termux-deploy/termux-llama-setup.sh')
if ($pushScript -match '(\d+) file') { Say "安装脚本已就位" } else { Warn "推送安装脚本返回：$($pushScript.Trim())" }

if (-not $SkipModel) {
  if (-not $model) {
    Warn "没找到 1.5B 模型文件，跳过推送。找过这些位置："
    $modelCandidates | ForEach-Object { Warn "  $_" }
    Warn "下载地址: https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF"
    Warn "也可以用 -ModelPath <完整路径> 指定别的模型"
  } else {
    Say "使用模型：$model"
    $sizeMB = [math]::Round((Get-Item $model).Length / 1MB, 1)
    Say "推送模型（$sizeMB MB，USB 2.0 约 1~3 分钟，请勿拔线）"
    $pushModel = Invoke-Adb @('-s', $serial, 'push', $model, '/sdcard/Download/termux-deploy/models/qwen2.5-1.5b-instruct-q4_k_m.gguf')
    if ($pushModel -match '(\d+) file') { Say "模型已推送到手机" } else { Warn "推送模型返回：$($pushModel.Trim())" }
  }
}

Say "在手机上打开 Termux"
Invoke-Adb @('-s', $serial, 'shell', 'am', 'start', '-n', 'com.termux/com.termux.app.TermuxActivity') | Out-Null

$cmd = 'cp /sdcard/Download/termux-deploy/termux-llama-setup.sh ~/ && cp -r /sdcard/Download/termux-deploy/models ~/ && bash ~/termux-llama-setup.sh'

Write-Host ""
Say "推送完成"
Write-Host @"

现在只剩一件事：在手机上的 Termux 里粘贴这一行并回车（长按屏幕 → Paste）：

$cmd

因为模型已经在手机上，脚本不会再下载，只会装依赖 + 编译 llama.cpp，
大约 10~30 分钟。

编译完成后运行：
  llama-cli -m ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf -c 4096 -t 4 -cnv
"@
