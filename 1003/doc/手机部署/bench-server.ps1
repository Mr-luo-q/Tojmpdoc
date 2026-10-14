# 调用手机上的 llama-server，把 prefill / decode 的分段耗时展开显示
#
# 用法：
#   .\bench-server.ps1                                        # 默认打 127.0.0.1:8080
#   .\bench-server.ps1 -ServerHost 172.18.209.84              # 打局域网里的手机
#   .\bench-server.ps1 -Prompt "写一首五言绝句" -MaxTokens 128
#   .\bench-server.ps1 -Repeat 3                              # 重复取平均
#   .\bench-server.ps1 -RawJson                               # 附带打印原始 JSON
#
# 设计说明：
#   llama-server 的 HTTP 响应里已经带了分阶段计时（timings 字段），
#   但它是嵌在完整 JSON 里的，人眼看很费劲。这个脚本只把它拎出来做对比表。
#   TTFT（首 token 时间）是脚本自己算的，服务端不直接给：
#     TTFT ≈ prompt_ms + predicted_per_token_ms
#   也就是「处理完提示词」再「生成第一个 token」的时间。
#
# 注意：本文件必须以 UTF-8 BOM 保存。Windows PowerShell 5.1 读取无 BOM 的
#       .ps1 时会按系统 ANSI（中文系统为 GBK）解码，中文注释会被解成乱码，
#       进而让行尾注释吞掉后面的参数，报出莫名其妙的语法错误。

[CmdletBinding()]
param(
    [string]$ServerHost = '127.0.0.1',   # 服务器地址，手机场景传手机 IP
    [int]$Port = 8080,                   # 端口
    [string]$Prompt = '用一句话说明什么是模型量化',   # 测试用提示词
    [int]$MaxTokens = 64,                # 最多生成多少 token
    [int]$Repeat = 1,                    # 重复次数，大于 1 时输出平均值
    [switch]$RawJson                     # 加上则额外打印完整原始响应
)

$ErrorActionPreference = 'Stop'
$base = "http://${ServerHost}:${Port}"

# 小工具：安全地取 JSON 里的数值，字段不存在或为 null 时返回 $null
function Get-Num($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return [double]$p.Value
}

Write-Host "==> 目标服务 $base" -ForegroundColor Green

# 1. 先确认服务活着，否则后面的请求都会失败
try {
    $health = Invoke-RestMethod -Uri "$base/health" -TimeoutSec 10
} catch {
    Write-Host "[x] 连不上服务：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    确认手机上已运行 bash ~/start-server.sh，且手机与电脑在同一网段。" -ForegroundColor Yellow
    exit 1
}
Write-Host "    健康检查：$($health.status)" -ForegroundColor Green

# 2. 取模型元信息，这样报告里能标明被测对象是什么
try {
    $models = Invoke-RestMethod -Uri "$base/v1/models" -TimeoutSec 10
    $meta = $models.data[0].meta
    Write-Host ""
    Write-Host "模型信息" -ForegroundColor Cyan
    Write-Host ("  ftype      : {0}" -f $meta.ftype)
    Write-Host ("  参数量     : {0:N0}" -f (Get-Num $meta 'n_params'))
    Write-Host ("  上下文     : {0}" -f (Get-Num $meta 'n_ctx'))
    Write-Host ("  词表大小   : {0:N0}" -f (Get-Num $meta 'n_vocab'))
} catch {
    Write-Host "    （/v1/models 取元信息失败，继续跑计时）" -ForegroundColor Yellow
}

# 3. 构造请求体。走 OpenAI 兼容接口，temperature 设 0 让重复测试更可比
$body = @{
    messages    = @(@{ role = 'user'; content = $Prompt })
    max_tokens  = $MaxTokens
    temperature = 0
} | ConvertTo-Json -Depth 5 -Compress

Write-Host ""
Write-Host "请求参数" -ForegroundColor Cyan
Write-Host ("  提示词     : {0}" -f $Prompt)
Write-Host ("  max_tokens : {0}" -f $MaxTokens)
Write-Host ("  重复次数   : {0}" -f $Repeat)

# 4. 逐个采样。服务端每次响应都带 timings，直接读它，不做本地估算
$samples = @()
$lastContent = ''
$lastRaw = $null

for ($i = 1; $i -le $Repeat; $i++) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-RestMethod -Uri "$base/v1/chat/completions" `
            -Method Post -ContentType 'application/json' `
            -Body $body -TimeoutSec 300
    } catch {
        Write-Host "[x] 第 $i 次请求失败：$($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    $sw.Stop()
    $lastRaw = $resp
    $lastContent = $resp.choices[0].message.content

    $t  = $resp.timings
    $pn = Get-Num $t 'prompt_n'
    $pm = Get-Num $t 'prompt_ms'
    $pp = Get-Num $t 'prompt_per_second'
    $dn = Get-Num $t 'predicted_n'
    $dm = Get-Num $t 'predicted_ms'
    $dp = Get-Num $t 'predicted_per_second'
    $cn = Get-Num $t 'cache_n'

    # 首 token 时间 = 提示词处理完 + 生成一个 token 的耗时
    $ttft = $null
    if ($null -ne $pm -and $null -ne $dm -and $null -ne $dn -and $dn -gt 0) {
        $ttft = $pm + ($dm / $dn)
    }

    $samples += [pscustomobject]@{
        轮次        = $i
        墙钟耗时_ms = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        prefill_tok = $pn
        prefill_ms  = $pm
        prefill_tps = $pp
        decode_tok  = $dn
        decode_ms   = $dm
        decode_tps  = $dp
        TTFT_ms     = $ttft
        缓存命中tok = $cn
    }
}

if ($samples.Count -eq 0) {
    Write-Host "[x] 没有成功的采样。" -ForegroundColor Red
    exit 1
}

# 5. 先给模型回复内容，人最关心这个
Write-Host ""
Write-Host "回复内容" -ForegroundColor Cyan
Write-Host ("  " + ($lastContent -replace "`r?`n", "`n  "))

# 6. 分段计时表：prefill 与 decode 的 token 数、耗时、速度并列
Write-Host ""
Write-Host "分段计时" -ForegroundColor Cyan
$samples | Format-Table -AutoSize

# 7. 指标含义。表格里数字多，不给解释容易看不懂
Write-Host "指标含义" -ForegroundColor Cyan
Write-Host "  prefill（提示词处理，服务端字段 prompt_*）"
Write-Host "    把输入提示词编码进 KV 缓存的速度。计算受限，受矩阵乘算力影响。"
Write-Host "    按下发送到开始吐字之间的等待，主要由它决定。"
Write-Host "  decode（逐 token 生成，服务端字段 predicted_*）"
Write-Host "    内存带宽受限：每生成一个 token 都要把全部模型权重从内存读一遍，"
Write-Host "    所以模型越大越慢，换算力更强的硬件也改不了这一点。"
Write-Host "  TTFT（首 token 时间，本脚本计算得出）"
Write-Host "    从发出请求到屏幕出现第一个字的延迟，体感流畅度看这个。"
Write-Host "  cache_n（命中缓存的 token 数）"
Write-Host "    多轮对话时之前轮次的 KV 会被复用，这部分不计入 prefill。"

# 8. 多轮采样时给出平均值
if ($samples.Count -gt 1) {
    Write-Host ""
    Write-Host "平均值" -ForegroundColor Cyan
    [pscustomobject]@{
        prefill_tps = [math]::Round(($samples.prefill_tps  | Measure-Object -Average).Average, 2)
        decode_tps  = [math]::Round(($samples.decode_tps   | Measure-Object -Average).Average, 2)
        TTFT_ms     = [math]::Round(($samples.TTFT_ms      | Measure-Object -Average).Average, 1)
        墙钟耗时_ms = [math]::Round(($samples.墙钟耗时_ms  | Measure-Object -Average).Average, 1)
    } | Format-List
}

# 9. 顺带看一眼服务端 Prometheus 指标（需启动时加 --metrics，没有则跳过）
Write-Host "服务端指标 /metrics" -ForegroundColor Cyan
try {
    $metrics = Invoke-WebRequest -Uri "$base/metrics" -TimeoutSec 8 -UseBasicParsing
    $metrics.Content -split "`n" |
        Where-Object { $_ -match '^llamacpp:' -and $_ -notmatch '^#' } |
        Select-Object -First 12 |
        ForEach-Object { Write-Host ("  " + $_.TrimEnd()) }
} catch {
    Write-Host "  未启用（启动时加 --metrics 才有）" -ForegroundColor DarkGray
}

# 10. 需要排查问题时打印完整原始响应
if ($RawJson) {
    Write-Host ""
    Write-Host "原始响应 JSON" -ForegroundColor Cyan
    $lastRaw | ConvertTo-Json -Depth 8
}
