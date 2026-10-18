# 后台启动蓝牙音箱 MQTT 桥（日志落在 _work\bt_speaker\logs\）。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _work\bt_speaker\start_bridge.ps1
#
# 注意：本脚本不要接管道——子进程会继承管道写端，接了会挂住（仓库自己的脚本也踩过）。

$here = $PSScriptRoot
$logDir = Join-Path $here 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { Write-Error '找不到 python'; exit 1 }

$running = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -like '*bt_speaker\bridge.py*' } |
    Select-Object -First 1

if (-not $running) {
    Start-Process $python -ArgumentList (Join-Path $here 'bridge.py') `
        -WorkingDirectory $here -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDir 'bridge.out.log') `
        -RedirectStandardError  (Join-Path $logDir 'bridge.err.log')
    Start-Sleep -Seconds 4
}

$proc = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -like '*bt_speaker\bridge.py*' } |
    Select-Object -First 1

if ($proc) {
    Write-Output "桥运行中：PID $($proc.ProcessId)，日志 $logDir\bridge.err.log"
} else {
    Write-Error "桥未启动，看 $logDir\bridge.err.log"
}
