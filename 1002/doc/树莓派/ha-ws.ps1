# Switch the Home Assistant Assist pipeline conversation agent to the local LLM
# via the WebSocket API.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ha-ws.ps1 -Base http://192.168.43.33:8123 -Username pi -Password <HA登录口令已脱敏> -Action list
#   powershell -ExecutionPolicy Bypass -File ha-ws.ps1 -Base http://192.168.43.33:8123 -Username pi -Password <HA登录口令已脱敏> -Action set

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [ValidateSet('list', 'set')][string]$Action = 'list'
)

$ErrorActionPreference = 'Stop'
$clientId = "$Base/"

function Post-Json($url, $obj) {
    $json = $obj | ConvertTo-Json -Depth 12
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    Invoke-RestMethod $url -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 120
}

function Receive-Message($ws) {
    $buffer = New-Object byte[] 65536
    $sb = [System.Text.StringBuilder]::new()
    do {
        $segment = [ArraySegment[byte]]::new($buffer)
        $result = $ws.ReceiveAsync($segment, [Threading.CancellationToken]::None).Result
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
    } while (-not $result.EndOfMessage)
    return $sb.ToString()
}

function Send-Message($ws, $text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $segment = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
}

# 1. login and get an access token
$login = Post-Json "$Base/auth/login_flow" @{ client_id = $clientId; handler = @('homeassistant', $null); redirect_uri = $clientId }
$step = Post-Json "$Base/auth/login_flow/$($login.flow_id)" @{ client_id = $clientId; username = $Username; password = $Password }
if ($step.type -ne 'create_entry') { throw "login failed: $($step.errors | ConvertTo-Json -Compress)" }
$tok = Invoke-RestMethod "$Base/auth/token" -Method Post -Body @{ grant_type = 'authorization_code'; code = $step.result; client_id = $clientId } -TimeoutSec 60
$hdr = @{ Authorization = "Bearer $($tok.access_token)" }

# 2. find the conversation entity backed by the local model
$states = Invoke-RestMethod "$Base/api/states" -Headers $hdr -TimeoutSec 60
$engine = ($states | Where-Object { $_.entity_id -like 'conversation.*' -and $_.entity_id -notlike '*home_assistant*' } |
    Select-Object -ExpandProperty entity_id | Select-Object -Last 1)
if (-not $engine) { throw 'no local conversation agent found' }
Write-Host "target conversation agent: $engine"

# 3. connect websocket and authenticate
$wsUri = $Base -replace '^http', 'ws'
$ws = [System.Net.WebSockets.ClientWebSocket]::new()
$ws.ConnectAsync([Uri]"$wsUri/api/websocket", [Threading.CancellationToken]::None).Wait()
$null = Receive-Message $ws
Send-Message $ws (@{ type = 'auth'; access_token = $tok.access_token } | ConvertTo-Json -Compress)
$authResult = Receive-Message $ws
if ($authResult -notmatch 'auth_ok') { throw "websocket auth failed: $authResult" }
Write-Host 'websocket connected'

# 4. list pipelines
Send-Message $ws (@{ id = 1; type = 'assist_pipeline/pipeline/list' } | ConvertTo-Json -Compress)
$list = (Receive-Message $ws) | ConvertFrom-Json
$pipelines = $list.result.pipelines
$pipelines | Select-Object id, name, conversation_engine, preferred | Format-Table -AutoSize

if ($Action -eq 'list') { $ws.Dispose(); return }

# 5. update the preferred pipeline
$target = $pipelines | Where-Object { $_.preferred } | Select-Object -First 1
if (-not $target) { $target = $pipelines | Select-Object -First 1 }
Write-Host "updating pipeline: $($target.name) ($($target.id))"
$payload = @{
    id                    = 2
    type                  = 'assist_pipeline/pipeline/update'
    pipeline_id           = $target.id
    name                  = $target.name
    language              = $target.language
    conversation_engine   = $engine
    conversation_language = 'zh-Hans'
    stt_engine            = $target.stt_engine
    stt_language          = $target.stt_language
    tts_engine            = $target.tts_engine
    tts_language          = $target.tts_language
    tts_voice             = $target.tts_voice
    wake_word_entity      = $target.wake_word_entity
    wake_word_id          = $target.wake_word_id
    prefer_local_intents  = $true
}
Send-Message $ws ($payload | ConvertTo-Json -Compress -Depth 6)
Write-Host "update result: $(Receive-Message $ws)"

# 6. verify
Send-Message $ws (@{ id = 3; type = 'assist_pipeline/pipeline/list' } | ConvertTo-Json -Compress)
$verify = (Receive-Message $ws) | ConvertFrom-Json
$verify.result.pipelines | Select-Object name, conversation_engine, preferred | Format-Table -AutoSize
$ws.Dispose()
