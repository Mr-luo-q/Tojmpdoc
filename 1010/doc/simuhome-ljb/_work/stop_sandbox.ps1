# 停掉本机沙盒。
# 默认只停我们自己起的：发布器、broker、HA 容器（保留 SimuHome API，方便下次直接重启链路）。
# 加 -StopSimuHome 连 SimuHome API 一起停。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _work\stop_sandbox.ps1 [-StopSimuHome]

param([switch]$StopSimuHome)

foreach ($pattern in @('*publisher.py*', '*run_broker.py*')) {
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like $pattern } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Output "已停 $pattern（PID $($_.ProcessId)）"
        }
}

$env:HA_CONFIG_DIR = 'D:\homeassistant-sandbox'
docker compose -f (Join-Path $PSScriptRoot 'ha\compose.yaml') stop

if ($StopSimuHome) {
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like '*src.simulator.api.app*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Output "已停 SimuHome（PID $($_.ProcessId)）"
        }
}
