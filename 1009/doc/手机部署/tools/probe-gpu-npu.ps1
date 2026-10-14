#Requires -Version 5.1
<#
  手机部署 · GPU / NPU 探测（电脑侧驱动脚本）

  职责：
    把 gpu-npu-probe.sh 推进手机并执行，把原始输出抓回本地保存成带时间戳的报告。

  输入：
    -Serial    adb 设备序列号；不填则自动取唯一在线设备
    -OutDir    报告输出目录，默认 .\probe-reports
    -Tail      终端里回显的输出行数上限，默认 200（完整内容永远写进文件）

  输出：
    <OutDir>\probe-<序列号>-<时间戳>.log    完整原始输出

  不负责：
    不安装 Termux、不推送模型、不改手机任何状态（脚本内全是只读命令）

  用法：
    powershell -ExecutionPolicy Bypass -File tools\probe-gpu-npu.ps1
#>

param(
  [string]$Serial,
  [string]$OutDir,
  [int]$Tail = 200
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$adb   = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
$probe = Join-Path $PSScriptRoot 'gpu-npu-probe.sh'

function Say($m)  { Write-Host "==> $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

if (-not $OutDir) { $OutDir = Join-Path $root 'probe-reports' }
if (-not (Test-Path $adb))   { Fail "找不到 adb：$adb" }
if (-not (Test-Path $probe)) { Fail "找不到探测脚本：$probe" }

& $adb start-server 2>&1 | Out-Null

# adb 会把提示写 stderr，统一包一层取字符串，避免被 ErrorActionPreference 当成终止错误
function Invoke-AdbOnce([string[]]$AdbArgs) {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return (& $adb @AdbArgs 2>&1 | Out-String) } finally { $ErrorActionPreference = $prev }
}

if (-not $Serial) {
  $lines = (Invoke-AdbOnce @('devices')) -split '\r?\n' | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
  $ready = $lines | Where-Object { $_ -match '\sdevice$' }
  if (-not $ready) {
    if ($lines | Where-Object { $_ -match 'unauthorized' }) {
      Fail "手机在线但未授权 USB 调试：解锁手机，点掉「允许 USB 调试」弹窗后重跑。"
    }
    Fail "没有在线设备。检查 USB 调试开关、数据线，或改用无线调试。"
  }
  $Serial = ($ready | Select-Object -First 1).Split()[0]
}
Say "目标设备：$Serial"

Say "推送探测脚本到 /data/local/tmp"
$pushOut = Invoke-AdbOnce @('-s', $Serial, 'push', $probe, '/data/local/tmp/gpu-npu-probe.sh')
if ($pushOut -notmatch '\d+ file') { Write-Host $pushOut.Trim() -ForegroundColor Yellow }

Say "执行探测（只读，不改系统状态）"
$out = Invoke-AdbOnce @('-s', $Serial, 'shell', 'sh', '/data/local/tmp/gpu-npu-probe.sh')

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# 序列号里可能有非法文件名字符，统一替换成下划线
$safe  = ($Serial -replace '[^\w\-]', '_')
$file  = Join-Path $OutDir "probe-$safe-$stamp.log"
$out | Set-Content -LiteralPath $file -Encoding UTF8

Say "完整报告已保存：$file"
$lineCount = ($out -split '\r?\n').Count
Say "共 $lineCount 行，下面回显末尾 $Tail 行"

$show = ($out -split '\r?\n')
if ($show.Count -gt $Tail) { $show = $show[($show.Count - $Tail)..($show.Count - 1)] }
$show | ForEach-Object { Write-Host $_ }
