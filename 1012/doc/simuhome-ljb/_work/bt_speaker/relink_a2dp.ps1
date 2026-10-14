<#
relink_a2dp.ps1

Purpose
    Force Windows to tear down and re-establish the Bluetooth A2DP audio link to a
    speaker. Use it for the "speaker shows connected, Windows renders audio, but the
    speaker stays silent" case: the audio endpoint exists and receives samples, while
    the A2DP stream underneath it is stuck.

Why elevation is required
    pnputil /restart-device needs an elevated shell. Without admin the script only
    prints a hint and exits with code 1.

Usage (from an Administrator PowerShell)
    powershell -NoProfile -ExecutionPolicy Bypass -File _work\bt_speaker\relink_a2dp.ps1 -Match SAB6
    powershell -NoProfile -ExecutionPolicy Bypass -File _work\bt_speaker\relink_a2dp.ps1 -Match SAB6 -RestartAudio

What it does
    1. finds every BTHENUM MEDIA devnode (the A2DP source driver) whose name matches -Match
    2. restarts those devnodes, which closes and re-opens their audio stream
    3. optional -RestartAudio: also restarts the Windows Audio service (Audiosrv)
    4. waits, then prints the speaker's audio endpoints again so you can see they are back

Exit codes
    0 ok / 1 not elevated / 2 device not found

Note: comments and messages stay ASCII on purpose. PowerShell 5.1 reads a .ps1 without
a BOM using the local code page, so non-ASCII inside the script can turn into garbage.
The Chinese explanation lives in relink_a2dp.md next to this file.
#>

[CmdletBinding()]
param(
    [string]$Match = 'SAB6',
    [switch]$RestartAudio,
    [switch]$RestartBluetoothStack,
    [int]$WaitSeconds = 8,
    [string]$LogPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogPath = if ($LogPath) {
    $LogPath
} else {
    Join-Path $PSScriptRoot 'logs\relink.out.log'
}
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-Elevated)) {
    Write-Host "[ERROR] needs an Administrator shell." -ForegroundColor Red
    Write-Host "        Open PowerShell as Administrator and re-run this script." -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "== looking for A2DP source devnodes matching '$Match' =="
$targets = @(
    Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like 'BTHENUM*' -and $_.FriendlyName -match $Match }
)
if ($targets.Count -eq 0) {
    Write-Host "[ERROR] no BTHENUM MEDIA devnode matches '$Match'." -ForegroundColor Red
    Write-Host "        Check the paired device name (Get-PnpDevice -Class MEDIA)." -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 2
}
foreach ($device in $targets) {
    Write-Host ("  {0,-6} {1}" -f $device.Status, $device.InstanceId)
}

foreach ($device in $targets) {
    Write-Host "== restart-device: $($device.InstanceId)"
    & pnputil.exe /restart-device "$($device.InstanceId)"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  pnputil returned $LASTEXITCODE (continuing)" -ForegroundColor Yellow
    }
}

if ($RestartAudio) {
    Write-Host "== restarting Windows Audio service (Audiosrv) =="
    Restart-Service -Name Audiosrv -Force
}

if ($RestartBluetoothStack) {
    Write-Host "== restarting Bluetooth stack (bthserv + bthHFSrv) =="
    Restart-Service -Name bthserv -Force
    Restart-Service -Name bthHFSrv -Force -ErrorAction SilentlyContinue
}

Write-Host "== waiting $WaitSeconds s, then re-checking endpoints =="
Start-Sleep -Seconds $WaitSeconds
Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match $Match } |
    Select-Object Status, Present, FriendlyName |
    Format-Table -AutoSize | Out-String -Width 160

Write-Host "Next step: run the 2-beep test so you can hear whether the link came back:"
Write-Host "  python _work\bt_speaker\tone_test.py --name $Match --beeps 2 --volume 80"
Stop-Transcript | Out-Null
exit 0
