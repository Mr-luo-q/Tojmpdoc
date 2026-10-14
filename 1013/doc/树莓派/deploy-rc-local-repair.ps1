# Deploy the repair payload through /etc/rc.local (installed by cloud-init bootcmd).
# Two payloads, both stored base64 on bootfs:
#   pi-repair.b64      -> /etc/rc.local            (repair script, runs late in boot)
#   install-repair.b64 -> /boot/firmware/install-repair.sh (small installer, run by bootcmd)
# The bootcmd is a single short line so the YAML can never be broken by newlines.
# ASCII only on purpose: PowerShell 5.1 reads .ps1 as GBK when there is no BOM.

$ErrorActionPreference = 'Stop'
$LF        = [char]10
$bootfs    = 'F:\'
$userData  = Join-Path $bootfs 'user-data'
$repairSh  = 'D:\项目\树莓派\bootfs-user-data-patch\pi-repair.sh'
$installSh = 'D:\项目\树莓派\bootfs-user-data-patch\install-repair.sh'

foreach ($p in @($userData, $repairSh, $installSh)) { if (-not (Test-Path $p)) { throw "not found: $p" } }

# 0) Roll back a previous injection so re-running is safe.
$old = [System.IO.File]::ReadAllText($userData, [System.Text.UTF8Encoding]::new($false))
if ($old -match 'DSH-PI-REPAIR') {
    $bak = Get-ChildItem $bootfs -Filter 'user-data.bak-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $bak) { throw 'already injected but no backup found' }
    Copy-Item $bak.FullName $userData -Force
    Write-Output "rolled back from $($bak.Name)"
    $old = [System.IO.File]::ReadAllText($userData, [System.Text.UTF8Encoding]::new($false))
}

# 1) Backup
$bakName = 'user-data.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item $userData (Join-Path $bootfs $bakName) -Force
Write-Output "backup created: $bakName"

# 2) Encode both payloads
function Write-B64([string]$src, [string]$dst) {
    $text  = [System.IO.File]::ReadAllText($src, [System.Text.UTF8Encoding]::new($false)).Replace("`r`n", [string]$LF)
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
    [System.IO.File]::WriteAllText($dst, [Convert]::ToBase64String($bytes), [System.Text.UTF8Encoding]::new($false))
    Write-Output ("  {0} -> {1} ({2} bytes)" -f (Split-Path $src -Leaf), (Split-Path $dst -Leaf), $bytes.Length)
}
Write-B64 $repairSh  (Join-Path $bootfs 'pi-repair.b64')
Write-B64 $installSh (Join-Path $bootfs 'install-repair.b64')

# 3) Clean stale outputs so the next boot is unambiguous
foreach ($f in 'pi-repair.sh', 'pi-repair.log') {
    $p = Join-Path $bootfs $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Output "removed stale $f" }
}

# 4) Inject the single-line bootcmd
if (-not $old.EndsWith([string]$LF)) { $old += $LF }
$inner = 'base64 -d /boot/firmware/install-repair.b64 > /boot/firmware/install-repair.sh; timeout 60 bash /boot/firmware/install-repair.sh'
$lines = @(
    '# ==== DSH-PI-REPAIR v3 START ====',
    '# Decode the installer from bootfs and run it: it installs the repair script as /etc/rc.local.',
    'bootcmd:',
    '  - [ bash, -c, "' + $inner + '" ]',
    '# ==== DSH-PI-REPAIR v3 END ===='
)
$patch = ($lines -join [string]$LF) + $LF
[System.IO.File]::WriteAllText($userData, $old + $patch, [System.Text.UTF8Encoding]::new($false))
Write-Output "patched $userData"

Write-Output ''
Write-Output '=== user-data tail ==='
Get-Content $userData -Tail 6
Write-Output ''
Write-Output '=== bootfs repair files ==='
Get-ChildItem $bootfs | Where-Object { $_.Name -match 'repair|user-data' } | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

# 5) Sanity check the YAML we just wrote using Python
$py = @'
import yaml
d = yaml.safe_load(open(r"F:\user-data", encoding="utf-8").read())
print("YAML OK. top keys:", list(d.keys()))
print("bootcmd:", d.get("bootcmd"))
print("runcmd:", d.get("runcmd"))
print("user:", (d.get("user") or {}).get("name"))
'@
$py | Set-Content -Path 'D:\项目\树莓派\_yamlcheck.py' -Encoding UTF8
& 'D:\Anaconda\python.exe' -u 'D:\项目\树莓派\_yamlcheck.py' 2>&1
