# 一键拉起 SimuHome 全链路（HA 容器 → SimuHome API → 载入 home → broker → 发布器）
#
# 顺序有依赖：发布器读 SimuHome、写 MQTT；HA 靠 MQTT discovery 建实体。
# 每一步都是幂等的：已在跑就跳过，只在"没装 home"时才需要载入 home_full.json。
#
# 前置（克隆 SimuHome、装 Mosquitto、生成 MQTT 账号、HA 加 MQTT 集成）见 deploy\03_沙盒全链路部署.md。
# 首次使用且 HA 容器还不存在时，先设 HA 配置目录：$env:HA_CONFIG_DIR = "D:\homeassistant\config"
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _tools\start_simuhome_stack.ps1
#      -ResetHome 强制把 SimuHome 重置回 home_full.json 的初始状态

param(
    [switch]$ResetHome
)

$root = Split-Path -Parent $PSScriptRoot
$compose = Join-Path $root "deploy\compose.yaml"
$homeJson = Join-Path $root "simuprocject\Simuhome_experiment\home_full.json"
$tokenFile = Join-Path $root "_secrets\ha_token.txt"

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) {
    Write-Error "找不到 python，请安装 Python 3.11+ 并加入 PATH"
    exit 1
}

if (-not (Test-Path $homeJson)) {
    Write-Error "未找到 SimuHome 仿真：$homeJson"
    Write-Error "请先按 deploy\03_沙盒全链路部署.md 克隆上游源码到 simuprocject\Simuhome_experiment"
    exit 1
}

function Wait-Http {
    param([string]$Url, [int]$Seconds = 180, [int]$Expect = 200)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq $Expect) { return $true }
        } catch {
            Start-Sleep -Seconds 3
        }
    }
    return $false
}

function Get-SimuHomeRoomCount {
    # 读 /api/home/state 的房间数：0 说明 API 起来了但没装 home（此时设备读写全 404）
    try {
        $state = Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/home/state" -TimeoutSec 10
        return @($state.data.rooms.PSObject.Properties).Count
    } catch {
        return 0
    }
}

# 1 HA 容器：Docker 引擎没起就先起 Docker Desktop
if (-not (docker info --format '{{.ServerVersion}}' 2>$null)) {
    Write-Output "启动 Docker Desktop ..."
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(240)
    do { Start-Sleep -Seconds 5 } until ((docker info --format '{{.ServerVersion}}' 2>$null) -or (Get-Date) -gt $deadline)
}

if (docker inspect homeassistant --format '{{.State.Status}}' 2>$null) {
    if ((docker inspect homeassistant --format '{{.State.Status}}') -ne "running") {
        docker start homeassistant | Out-Null
    }
} else {
    if (-not $env:HA_CONFIG_DIR) {
        Write-Error "HA 容器不存在，且未设置 HA_CONFIG_DIR（HA 配置目录）"
        Write-Error '示例：$env:HA_CONFIG_DIR = "D:\homeassistant\config"；见 deploy\03_沙盒全链路部署.md'
        exit 1
    }
    docker compose -f $compose up -d | Out-Null
}
Wait-Http -Url "http://127.0.0.1:8123/" -Seconds 300 | Out-Null

# 2 SimuHome API
$simuRunning = Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -like "*src.simulator.api.app*" } |
    Select-Object -First 1
if (-not $simuRunning) {
    Start-Process $python -ArgumentList "-m", "src.simulator.api.app" `
        -WorkingDirectory "$root\simuprocject\Simuhome_experiment" -WindowStyle Hidden
}
$simuReady = Wait-Http -Url "http://127.0.0.1:8000/api/__health__" -Seconds 120

# 3 载入 home：房间数为 0（或 -ResetHome）时 POST home_full.json
$rooms = Get-SimuHomeRoomCount
if ($simuReady -and ($ResetHome -or $rooms -eq 0)) {
    Write-Output "载入 home_full.json（当前房间数 $rooms）..."
    Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/api/simulation/reset" `
        -ContentType "application/json" -Body (Get-Content $homeJson -Raw) | Out-Null
    Start-Sleep -Seconds 2
    $rooms = Get-SimuHomeRoomCount
}

# 4 MQTT broker（脚本内部会跑 health_check）
#    这两个脚本会留下长命子进程，子进程会继承管道写端——所以不能接管道（接了会挂住）
if (-not (Test-Path "$root\simuhome_mqtt_publisher\broker\mosquitto.passwd")) {
    Write-Error "未找到 MQTT 账号文件 mosquitto.passwd，先跑 broker\make_credentials.ps1（见 deploy\03）"
    exit 1
}
& "$root\simuhome_mqtt_publisher\broker\start_mosquitto.ps1"

# 5 发布器（脚本内部等 5 秒；已在跑会跳过）
& "$root\simuhome_mqtt_publisher\publisher\start_publisher.ps1"
Start-Sleep -Seconds 5

# 6 汇总
$publisher = Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -like "*publisher\publisher.py*" } |
    Select-Object -First 1
$entities = 0
$unavailable = 0
if (Test-Path $tokenFile) {
    $token = (Get-Content $tokenFile -Raw).Trim()
    try {
        $states = Invoke-RestMethod -Uri "http://127.0.0.1:8123/api/states" `
            -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20
        $mine = $states | Where-Object { $_.entity_id -like "*.simuhome*" }
        $entities = @($mine).Count
        $unavailable = @($mine | Where-Object { $_.state -eq "unavailable" }).Count
    } catch {
        Write-Output "读 HA 实体失败：$($_.Exception.Message)"
    }
}

Write-Output ""
Write-Output "SimuHome 房间数   $rooms（应为 3）"
Write-Output "SimuHome 进程     $(if ($simuRunning) { '运行中' } else { '本次启动' })"
Write-Output "broker 进程       $(if (Get-CimInstance Win32_Process -Filter "Name='mosquitto.exe'") { '运行中' } else { '未运行' })"
Write-Output "发布器进程        $(if ($publisher) { "运行中 PID $($publisher.ProcessId)" } else { '未运行' })"
Write-Output "HA 实体           $entities 个（应为 25），其中 unavailable $unavailable 个"
