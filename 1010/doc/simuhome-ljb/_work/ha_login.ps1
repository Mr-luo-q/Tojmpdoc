# 用一个带 DNS 映射的浏览器专用窗口打开沙盒 HA（不需要管理员权限）。
#
# 为什么需要：XiaoMi/ha_xiaomi_home 把 OAuth 回跳地址写死在源码里
# （custom_components\xiaomi_home\const.py 里的 OAUTH_REDIRECT_URL =
#  'http://homeassistant.local:8123'，下拉框也只给这一个选项）。
# 而 Docker Desktop 不会把容器名注册到宿主 DNS，浏览器解析不了这个域名，
# 于是登录最后一步的回跳断掉。
#
# Edge 和 Chrome 都是 Chromium 内核，同一个 --host-resolver-rules 参数都支持，
# 两个都实测过。默认优先 Edge，找不到再退到 Chrome。
#
# 必须用独立 profile：浏览器已经在运行时，新起的进程只是把 URL 转给已有进程，
# 命令行参数会被丢掉。

$candidates = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
)
$browser = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) {
    Write-Host '既找不到 Edge 也找不到 Chrome。请改用 fix_hosts.cmd（点一次 UAC，全局生效）。'
    exit 1
}

$profileName = if ($browser -like '*msedge*') { 'edge-ha-profile' } else { 'chrome-ha-profile' }
$profile = Join-Path $PSScriptRoot $profileName
$argLine = '--user-data-dir="' + $profile + '" ' +
           '--host-resolver-rules="MAP homeassistant.local 127.0.0.1" ' +
           '--no-first-run --no-default-browser-check ' +
           'http://homeassistant.local:8123'

Start-Process -FilePath $browser -ArgumentList $argLine

Write-Host ('已用「' + (Split-Path $browser -Leaf) + '」打开专用窗口' +
            '（这个窗口里 homeassistant.local 解析到 127.0.0.1）。')
Write-Host ''
Write-Host '接下来：'
Write-Host '  1. 用 sandbox 账号登录 HA（密码在 _secrets\ha_sandbox_credentials.txt）'
Write-Host '  2. 设置 → 设备与服务 → 添加集成 → 搜 Xiaomi Home'
Write-Host '  3. 同意 EULA → 区域选中国大陆 → 点链接登录小米账号'
Write-Host '  4. 回跳会自动完成，然后弹出"选择家庭与设备"'
Write-Host ''
Write-Host '注意：这台专用窗口有独立 profile，和你平时的浏览器互不影响。'
