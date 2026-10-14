# 用 Raspberry Pi Imager 的命令行模式把镜像写入存储卡
# 用法示例：
#   powershell -ExecutionPolicy Bypass -File flash-sd.ps1 -Image D:\xx.img.xz -Drive \\.\PhysicalDrive2
# 可选：-UserData user-data  -NetworkConfig network-config  （cloud-init 配置，新版树莓派 OS 需要）

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$Drive,
    [string]$UserData = '',
    [string]$NetworkConfig = '',
    [string]$Log = "$env:TEMP\rpi-imager-flash.log"
)

$imager = 'C:\Program Files\Raspberry Pi Ltd\Imager\rpi-imager.exe'

Start-Transcript -Path $Log -Force | Out-Null
"== 开始 $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') =="
"镜像   : $Image"
"目标   : $Drive"
"user-data      : $UserData"
"network-config : $NetworkConfig"

$imagerArgs = @('--cli', '--debug')
if ($UserData) { $imagerArgs += @('--cloudinit-userdata', $UserData) }
if ($NetworkConfig) { $imagerArgs += @('--cloudinit-networkconfig', $NetworkConfig) }
$imagerArgs += @($Image, $Drive)

"命令   : $imager $($imagerArgs -join ' ')"

& $imager @imagerArgs 2>&1 | ForEach-Object { $_ }

"退出码 : $LASTEXITCODE"
"== 结束 $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') =="
Stop-Transcript | Out-Null
