<#
start_all.ps1

Purpose
    Idempotently bring up the full local chain, in dependency order:
        Docker / HA  ->  MQTT broker (amqtt)  ->  SimuHome (load home)  ->  publisher  ->  Bluetooth speaker bridge
    Safe to run repeatedly: every step skips whatever is already running. No admin required.

Usage
    powershell -NoProfile -ExecutionPolicy Bypass -File _work\start_all.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File _work\start_all.ps1 -ResetHome

Pinned paths (this machine)
    HA config          D:\homeassistant-sandbox        (container already exists; compose only used if missing)
    Python (host)      D:\Anaconda\python.exe          (broker / publisher / bridge)
    SimuHome           D:\Simuhome\SimuHome            (own venv: .venv\Scripts\python.exe)
    home_full.json     D:\Simuhome\SimuHome\home_full.json

Note
    Script body is ASCII only. PowerShell 5.1 reads a BOM-less .ps1 with the local
    code page, so non-ASCII inside the script can turn into garbage. The Chinese
    explanation lives in start_all.md next to this file.
#>

[CmdletBinding()]
param(
    [switch]$ResetHome
)

$ErrorActionPreference = 'Continue'

$Repo            = Split-Path -Parent $PSScriptRoot
$AnacondaPython  = 'D:\Anaconda\python.exe'
$BrokerScript    = Join-Path $PSScriptRoot 'broker\run_broker.py'
$BridgeDir       = Join-Path $PSScriptRoot 'bt_speaker'
$BridgeScript    = Join-Path $BridgeDir 'bridge.py'
$SimuHomeDir     = 'D:\Simuhome\SimuHome'
$SimuHomePython  = Join-Path $SimuHomeDir '.venv\Scripts\python.exe'
$HomeJson        = Join-Path $SimuHomeDir 'home_full.json'
$PublisherDir    = Join-Path $Repo 'simuhome_mqtt_publisher\publisher'
$PublisherScript = Join-Path $PublisherDir 'publisher.py'
$TokenFile       = Join-Path $Repo '_secrets\ha_token.txt'
$Compose         = Join-Path $Repo 'deploy\compose.yaml'
$DockerExe       = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$LogDir          = Join-Path $PSScriptRoot 'logs'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Find-Process {
    param([string]$Pattern)
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -like "*$Pattern*" } |
        Select-Object -First 1
}

function Wait-Http {
    param([string]$Url, [int]$Seconds = 180, [int]$Expect = 200)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq $Expect) { return $true }
        } catch { }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Wait-Tcp {
    param([int]$Port, [int]$Seconds = 60)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
            if ($async.AsyncWaitHandle.WaitOne(2000) -and $client.Connected) {
                $client.Close()
                return $true
            }
            $client.Close()
        } catch { }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Start-PythonBg {
    param([string]$Python, [string[]]$ArgList, [string]$WorkDir, [string]$Out, [string]$Err)
    Start-Process $Python -ArgumentList $ArgList -WorkingDirectory $WorkDir -WindowStyle Hidden `
        -RedirectStandardOutput $Out -RedirectStandardError $Err
}

function Get-RoomCount {
    try {
        $state = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/api/home/state' -TimeoutSec 10
        return @($state.data.rooms.PSObject.Properties).Count
    } catch {
        return 0
    }
}

# ---- 1. Docker + HA ----
if (-not (docker info --format '{{.ServerVersion}}' 2>$null)) {
    Write-Host '[1/6] starting Docker Desktop ...'
    if (Test-Path $DockerExe) { Start-Process $DockerExe -WindowStyle Hidden }
    $deadline = (Get-Date).AddSeconds(240)
    do {
        Start-Sleep -Seconds 5
    } until ((docker info --format '{{.ServerVersion}}' 2>$null) -or (Get-Date) -gt $deadline)
}

if (docker inspect homeassistant --format '{{.State.Status}}' 2>$null) {
    if ((docker inspect homeassistant --format '{{.State.Status}}') -ne 'running') {
        docker start homeassistant | Out-Null
    }
} else {
    $haDir = if ($env:HA_CONFIG_DIR) { $env:HA_CONFIG_DIR } else { 'D:\homeassistant-sandbox' }
    $env:HA_CONFIG_DIR = $haDir
    docker compose -f $Compose up -d | Out-Null
}
$haReady = Wait-Http 'http://127.0.0.1:8123/' -Seconds 300
Write-Host "[1/6] HA reachable: $haReady"

# ---- 2. MQTT broker ----
if (-not (Find-Process '_work\broker\run_broker.py')) {
    Write-Host '[2/6] starting amqtt broker ...'
    Start-PythonBg -Python $AnacondaPython -ArgList @($BrokerScript) -WorkDir (Split-Path $BrokerScript) `
        -Out (Join-Path $LogDir 'broker.out.log') -Err (Join-Path $LogDir 'broker.err.log')
}
$brokerReady = Wait-Tcp -Port 1883 -Seconds 60
Write-Host "[2/6] broker 1883 ready: $brokerReady"

# ---- 3. SimuHome API + load home ----
if (-not (Find-Process 'src.simulator.api.app')) {
    Write-Host '[3/6] starting SimuHome API ...'
    Start-PythonBg -Python $SimuHomePython -ArgList @('-m', 'src.simulator.api.app') -WorkDir $SimuHomeDir `
        -Out (Join-Path $LogDir 'simuhome.out.log') -Err (Join-Path $LogDir 'simuhome.err.log')
}
$simuReady = Wait-Http 'http://127.0.0.1:8000/api/__health__' -Seconds 120
$rooms = Get-RoomCount
if ($simuReady -and ($ResetHome -or $rooms -eq 0)) {
    Write-Host "[3/6] loading home_full.json (rooms=$rooms) ..."
    if (Test-Path $HomeJson) {
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8000/api/simulation/reset' `
            -ContentType 'application/json' -Body (Get-Content $HomeJson -Raw) | Out-Null
        Start-Sleep -Seconds 2
        $rooms = Get-RoomCount
    }
}
Write-Host "[3/6] SimuHome ready: $simuReady  rooms=$rooms"

# ---- 4. publisher ----
if (-not (Find-Process 'publisher\publisher.py')) {
    Write-Host '[4/6] starting publisher ...'
    Start-PythonBg -Python $AnacondaPython -ArgList @($PublisherScript) -WorkDir $PublisherDir `
        -Out (Join-Path $LogDir 'publisher.out.log') -Err (Join-Path $LogDir 'publisher.err.log')
}
Start-Sleep -Seconds 8

# ---- 5. Bluetooth speaker bridge ----
if (-not (Find-Process 'bt_speaker\bridge.py')) {
    Write-Host '[5/6] starting bt_speaker bridge ...'
    Start-PythonBg -Python $AnacondaPython -ArgList @($BridgeScript) -WorkDir $BridgeDir `
        -Out (Join-Path $BridgeDir 'logs\bridge.out.log') -Err (Join-Path $BridgeDir 'logs\bridge.err.log')
}
Start-Sleep -Seconds 5

# ---- 6. summary ----
Write-Host '[6/6] summary:'
Write-Host "  rooms = $rooms"
foreach ($name in @('_work\broker\run_broker.py', 'src.simulator.api.app', 'publisher\publisher.py', 'bt_speaker\bridge.py')) {
    $proc = Find-Process $name
    Write-Host ("  {0,-28} {1}" -f $name, $(if ($proc) { "PID $($proc.ProcessId)" } else { 'NOT running' }))
}
if (Test-Path $TokenFile) {
    $token = (Get-Content $TokenFile -Raw).Trim()
    try {
        $states = Invoke-RestMethod -Uri 'http://127.0.0.1:8123/api/states' `
            -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20
        $bt = @($states | Where-Object { $_.entity_id -like '*bt_speaker*' })
        $sim = @($states | Where-Object { $_.entity_id -like '*simuhome*' })
        $simUnavailable = @($sim | Where-Object { $_.state -eq 'unavailable' }).Count
        Write-Host "  bt_speaker entities = $($bt.Count)"
        Write-Host "  simuhome entities = $($sim.Count), unavailable = $simUnavailable"
    } catch {
        Write-Host "  (read HA states failed: $($_.Exception.Message))"
    }
}
