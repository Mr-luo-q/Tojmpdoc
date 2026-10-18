# 往 Windows hosts 加一条 homeassistant.local → 127.0.0.1（需要管理员，会弹 UAC）。
#
# 这是"全局且永久"的做法：加完之后任何浏览器、任何程序访问 homeassistant.local
# 都会到本机 8123，小米登录的回跳自动完成，重启也不丢。
# 如果不想提权，用 ha_login.cmd（Chrome 方案，不需要管理员）。

$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host '需要管理员权限，正在请求提权（请在弹窗里点"是"）...'
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    )
    exit 0
}

$content = Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue
if ($content -match 'homeassistant\.local') {
    Write-Host 'hosts 里已经有 homeassistant.local，无需修改。'
} else {
    Add-Content -LiteralPath $hostsPath -Value "`r`n127.0.0.1 homeassistant.local"
    Write-Host '已添加：127.0.0.1 homeassistant.local'
}

Start-Sleep -Seconds 1
$resolved = try { (Resolve-DnsName homeassistant.local -ErrorAction Stop).IPAddress } catch { $null }
if ($resolved) {
    Write-Host ('解析结果：' + ($resolved -join ', '))
} else {
    Write-Host '解析测试没通过，等几秒再试，或执行 ipconfig /flushdns。'
}

Write-Host ''
Write-Host '撤销：用管理员权限编辑 C:\Windows\System32\drivers\etc\hosts，删掉那一行。'
