# 一次跑完：把 pearcat 临时设为手动 → 连到设备配网热点 → 深度探测 → 恢复原样。
#
# 为什么先把 pearcat 设成手动：设备热点没有外网，Windows 会自动切回有外网的 pearcat，
# 上一轮就是这么被打断的。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _work\xiaomi\switch_and_probe.ps1

$ap = 'hzsj-light-wyra02_mibtF3E6'
# 注意：变量名不能叫 $home —— 那是 PowerShell 的只读内置变量，赋值会失败，
# 导致"恢复网络"那步静默不执行。第一次跑就踩了这个坑。
$homeSsid = 'pearcat'
$probe = Join-Path $PSScriptRoot 'probe_ap_deep.py'

try {
    Write-Output ('[1/4] 把 ' + $homeSsid + ' 暂时设为手动连接 ...')
    netsh wlan set profileparameter name="$homeSsid" connectionmode=manual | Out-Null

    Write-Output ('[2/4] 连接到设备热点 ' + $ap + ' ...')
    netsh wlan connect name="$ap" | Out-Null
    Start-Sleep -Seconds 10
    netsh wlan show interfaces | Select-String -Pattern '^\s+SSID'

    Write-Output '[3/4] 开始深度探测 ...'
    python $probe
}
finally {
    Write-Output ''
    Write-Output '[4/4] 恢复网络 ...'
    netsh wlan connect name="$homeSsid" | Out-Null
    Start-Sleep -Seconds 6
    netsh wlan set profileparameter name="$homeSsid" connectionmode=auto | Out-Null
    netsh wlan show interfaces | Select-String -Pattern '^\s+SSID'
}
