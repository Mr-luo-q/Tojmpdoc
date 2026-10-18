# Clear the target USB disk and write a raw image to it (run elevated)
# Example:
#   powershell -ExecutionPolicy Bypass -File write-image.ps1 -Image C:\img.img.xz -DiskNumber 2 -Python D:\Anaconda\python.exe -PyScript D:\path\raw-write.py

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][int]$DiskNumber,
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$PyScript,
    [string]$Log = "$env:TEMP\raw-write.log"
)

Start-Transcript -Path $Log -Force | Out-Null
"== start $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') =="
"image      : $Image"
"disk number: $DiskNumber"

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
"disk       : $($disk.FriendlyName) | $([math]::Round($disk.Size/1GB,2)) GB | $($disk.BusType) | $($disk.PartitionStyle)"

if ($disk.BusType -ne 'USB') {
    throw "Refusing to write: disk $DiskNumber is not a USB device (BusType=$($disk.BusType))"
}
if ($disk.Size -lt 40GB) {
    throw "Refusing to write: disk $DiskNumber is only $([math]::Round($disk.Size/1GB,2)) GB"
}

"clearing partition table..."
Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false -ErrorAction Continue
Get-Disk -Number $DiskNumber | Select-Object Number, PartitionStyle, OperationalStatus | Format-List | Out-String

"writing image..."
$device = "\\.\PhysicalDrive$DiskNumber"
& $Python $PyScript $Image $device
"python exit code: $LASTEXITCODE"

"== end $(Get-Date -Format 'yyyy/MM/dd HH:mm:ss') =="
Stop-Transcript | Out-Null
