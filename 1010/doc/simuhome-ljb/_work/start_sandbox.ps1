# 一键拉起本机沙盒（本机版）。
#
# 为什么另起一份：仓库的 _tools\start_simuhome_stack.ps1 写死了 simuprocject\Simuhome_experiment
# 和原生 Mosquitto，这台机器两条都对不上。这里按实际路径来，并且不动仓库里的任何原有文件。
# 每一步幂等：已经在跑的就跳过。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _work\start_sandbox.ps1
#
# 注意：发布器的启动脚本会留下长命子进程，子进程会继承管道写端，所以本脚本不要接管道，
#       否则会挂住（仓库自己的脚本里也记了这条）。

$simuHome   = 'D:\Simuhome\SimuHome'
$simuPython = Join-Path $simuHome '.venv\Scripts\python.exe'
$homeJson   = Join-Path $simuHome 'home_full.json'
$haConfig   = 'D:\homeassistant-sandbox'
$root       = Split-Path -Parent $PSScriptRoot
$logs       = Join-Path $PSScriptRoot 'logs'

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { Write-Error '找不到 python，请确认它在 PATH 里'; exit 1 }
New-Item -ItemType Directory -Force -Path $logs | Out-Null

function Test-Port([int]$Port) {
    [bool](Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue)
}

function Wait-Http([string]$Url, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            if ((Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) { return $true }
        } catch { Start-Sleep -Seconds 5 }
    }
    return $false
}

# 1 Docker 引擎 + HA 容器
if (-not (docker info --format '{{.ServerVersion}}' 2>$null)) {
    Write-Output '启动 Docker Desktop ...'
    Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(300)
    while (-not (docker info --format '{{.ServerVersion}}' 2>$null) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
    }
}

$env:HA_CONFIG_DIR = $haConfig
New-Item -ItemType Directory -Force -Path $haConfig | Out-Null
docker compose -f (Join-Path $PSScriptRoot 'ha\compose.yaml') up -d | Out-Null
Write-Output '等待 HA 就绪 ...'
Wait-Http 'http://127.0.0.1:8123/' 300 | Out-Null

# 2 SimuHome API
if (-not (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*src.simulator.api.app*' })) {
    Start-Process $simuPython -ArgumentList '-m', 'src.simulator.api.app' -WorkingDirectory $simuHome -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logs 'simuhome-api.out.log') `
        -RedirectStandardError  (Join-Path $logs 'simuhome-api.err.log')
}
Wait-Http 'http://127.0.0.1:8000/api/__health__' 120 | Out-Null

# 3 房间数为 0 时载入 home_full.json
function Get-RoomCount {
    try {
        $state = Invoke-RestMethod 'http://127.0.0.1:8000/api/home/state' -TimeoutSec 10
        return @($state.data.rooms.PSObject.Properties).Count
    } catch { return 0 }
}

$rooms = Get-RoomCount
if ($rooms -eq 0) {
    Write-Output '载入 home_full.json ...'
    Invoke-RestMethod -Method Post 'http://127.0.0.1:8000/api/simulation/reset' `
        -ContentType 'application/json' -Body (Get-Content $homeJson -Raw) | Out-Null
    Start-Sleep -Seconds 2
    $rooms = Get-RoomCount
}

# 4 MQTT broker（amqtt）
if (-not (Test-Port 1883)) {
    Start-Process $python -ArgumentList (Join-Path $PSScriptRoot 'broker\run_broker.py') `
        -WorkingDirectory (Join-Path $PSScriptRoot 'broker') -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logs 'broker.out.log') `
        -RedirectStandardError  (Join-Path $logs 'broker.err.log')
    Start-Sleep -Seconds 5
}

# 5 发布器（用仓库自己的脚本）
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'simuhome_mqtt_publisher\publisher\start_publisher.ps1')
Start-Sleep -Seconds 5

# 6 汇总
$tokenFile = Join-Path $root '_secrets\ha_token.txt'
$entities = 0
$unavailable = 0
if (Test-Path $tokenFile) {
    $token = (Get-Content $tokenFile -Raw).Trim()
    try {
        $states = Invoke-RestMethod 'http://127.0.0.1:8123/api/states' `
            -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20
        $mine = @($states | Where-Object { $_.entity_id -like '*simuhome*' })
        $entities = $mine.Count
        $unavailable = @($mine | Where-Object { $_.state -eq 'unavailable' }).Count
    } catch { Write-Output "读 HA 实体失败：$($_.Exception.Message)" }
}

$publisherUp = [bool](Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*publisher.py*' })
Write-Output ''
Write-Output "SimuHome 房间数   $rooms（应为 3）"
Write-Output "broker 端口 1883  $(Test-Port 1883)"
Write-Output "发布器进程        $(if ($publisherUp) { '运行中' } else { '未运行' })"
Write-Output "HA 实体           $entities 个（应为 25），其中 unavailable $unavailable 个"
