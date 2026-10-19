[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$DeviceSerial = '',
    [int[]]$Threads = @(4, 6, 8),
    [int]$Repeats = 3,
    [int]$PromptLength = 128,
    [int]$GenerateLength = 64,
    [int]$CooldownSeconds = 0,
    [switch]$SkipDownload,
    [switch]$SkipBuild,
    [switch]$SkipPush,
    [switch]$SkipBench,
    [switch]$RunDemo
)

$ErrorActionPreference = 'Stop'

# 未显式传入根目录时，以脚本上一级目录作为项目根目录。
if (-not $Root) {
    $Root = Split-Path -Parent $PSScriptRoot
}

# 固定实验路径和版本，保证源码、NDK、模型与运行时来自同一套归档。
$MnnRoot = Join-Path $Root 'research\mnn-20261019'
$NdkZip = Join-Path $MnnRoot 'toolchain\android-ndk-r28b-windows.zip'
$NdkDir = Join-Path $MnnRoot 'toolchain\ndk\android-ndk-r28b'
$SourceZip = Join-Path $MnnRoot 'src\MNN-3.6.1.zip'
$SourceExtract = Join-Path $MnnRoot 'src\extracted'
$SourceDir = Join-Path $SourceExtract 'MNN-3.6.1'
$ModelDir = Join-Path $MnnRoot 'model\Qwen3.5-0.8B-MNN'
$BuildDir = Join-Path $MnnRoot 'build'
$TempDir = Join-Path $MnnRoot 'tmp'
$ResultDir = Join-Path $MnnRoot 'device-results'
$PromptFile = Join-Path $MnnRoot 'prompt-zh.txt'
$AdbLocal = Join-Path $Root 'tools\platform-tools\adb.exe'
$Adb = if (Test-Path -LiteralPath $AdbLocal) { $AdbLocal } else { 'adb' }
$DeviceRoot = '/data/local/tmp/mnn'
$DeviceModel = "$DeviceRoot/models/Qwen3.5-0.8B-MNN"
$ModelWeightSha256 = '4E25EF4CBFB49A33013D17300C2F68CD9C9CE8F2E3F7B947FD2C574EC297CA5E'

# 下载单个文件；已有且达到最小体积时直接复用，避免重复占用带宽。
function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [long]$MinBytes = 1
    )

    if (Test-Path -LiteralPath $OutFile) {
        $existing = (Get-Item -LiteralPath $OutFile).Length
        if ($existing -ge $MinBytes) {
            Write-Host "复用 $OutFile ($existing bytes)"
            return
        }
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    Write-Host "下载 $Uri"
    & curl.exe -L --fail --retry 3 -o $OutFile $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "下载失败：$Uri"
    }
    if ((Get-Item -LiteralPath $OutFile).Length -lt $MinBytes) {
        throw "下载文件体积异常：$OutFile"
    }
}

# 准备 MNN 源码、Android NDK 和官方已经导出的 Qwen3.5-0.8B MNN 模型。
function Prepare-MnnDependencies {
    if (-not (Test-Path -LiteralPath $AdbLocal) -and -not (Get-Command adb -ErrorAction SilentlyContinue)) {
        throw "找不到 ADB：请安装 Android platform-tools，或把 adb.exe 放到 $AdbLocal"
    }

    Invoke-Download -Uri 'https://dl.google.com/android/repository/android-ndk-r28b-windows.zip' `
        -OutFile $NdkZip -MinBytes 700000000
    Invoke-Download -Uri 'https://codeload.github.com/alibaba/MNN/zip/refs/tags/3.6.1' `
        -OutFile $SourceZip -MinBytes 90000000

    if (-not (Test-Path -LiteralPath (Join-Path $NdkDir 'build\cmake\android.toolchain.cmake'))) {
        New-Item -ItemType Directory -Force -Path (Join-Path $NdkDir '..') | Out-Null
        Write-Host '解压 Android NDK'
        & tar.exe -xf $NdkZip -C (Join-Path $NdkDir '..')
        if ($LASTEXITCODE -ne 0) {
            throw 'Android NDK 解压失败'
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'CMakeLists.txt'))) {
        New-Item -ItemType Directory -Force -Path $SourceExtract | Out-Null
        Write-Host '解压 MNN 源码'
        & tar.exe -xf $SourceZip -C $SourceExtract
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'CMakeLists.txt'))) {
            throw 'MNN 源码解压失败'
        }
    }

    New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null
    $modelFiles = @(
        'config.json',
        'configuration.json',
        'export_args.json',
        'llm.mnn',
        'llm.mnn.json',
        'llm.mnn.weight',
        'llm_config.json',
        'tokenizer.txt',
        'visual.mnn',
        'visual.mnn.weight'
    )
    foreach ($name in $modelFiles) {
        $minBytes = 1
        if ($name -eq 'llm.mnn.weight') {
            $minBytes = 470000000
        }
        Invoke-Download -Uri "https://modelscope.cn/models/MNN/Qwen3.5-0.8B-MNN/resolve/master/$name" `
            -OutFile (Join-Path $ModelDir $name) -MinBytes $minBytes
    }

    $actualHash = (Get-FileHash -LiteralPath (Join-Path $ModelDir 'llm.mnn.weight') -Algorithm SHA256).Hash
    if ($actualHash -ne $ModelWeightSha256) {
        throw "模型权重 SHA-256 不匹配：$actualHash"
    }
}

# 用 NDK 交叉编译 Android arm64 CPU 版 llm_bench 与 llm_demo。
function Build-MnnAndroid {
    $bench = Join-Path $BuildDir 'llm_bench'
    $demo = Join-Path $BuildDir 'llm_demo'
    if ((Test-Path -LiteralPath $bench) -and (Test-Path -LiteralPath $demo)) {
        Write-Host '复用已编译的 llm_bench 与 llm_demo'
        return
    }

    New-Item -ItemType Directory -Force -Path $BuildDir, $TempDir | Out-Null
    $toolchain = (Join-Path $NdkDir 'build\cmake\android.toolchain.cmake') -replace '\\', '/'

    if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt'))) {
        & cmake -S $SourceDir -B $BuildDir -G Ninja `
            "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
            -DANDROID_ABI=arm64-v8a `
            -DANDROID_PLATFORM=android-28 `
            -DANDROID_STL=c++_static `
            -DCMAKE_BUILD_TYPE=Release `
            -DMNN_BUILD_SHARED_LIBS=OFF `
            -DMNN_SEP_BUILD=OFF `
            -DMNN_BUILD_LLM=ON `
            -DMNN_LLM_BUILD_DEMO=ON `
            -DMNN_LOW_MEMORY=ON `
            -DMNN_SUPPORT_TRANSFORMER_FUSE=ON `
            -DMNN_ARM82=ON `
            -DMNN_OPENCL=OFF `
            -DMNN_VULKAN=OFF `
            -DMNN_KLEIDIAI=OFF `
            -DMNN_BUILD_TOOLS=OFF `
            -DMNN_BUILD_TEST=OFF `
            -DMNN_BUILD_BENCHMARK=OFF `
            -DMNN_USE_LOGCAT=OFF `
            -DMNN_BUILD_FOR_ANDROID_COMMAND=ON
        if ($LASTEXITCODE -ne 0) {
            throw 'MNN CMake 配置失败'
        }
    }

    # 汇编步骤会写临时文件，固定到仓库内目录可避免受限环境下的 TEMP 写入失败。
    $oldTmp = $env:TMP
    $oldTemp = $env:TEMP
    try {
        $env:TMP = $TempDir
        $env:TEMP = $TempDir
        & cmake --build $BuildDir --target llm_bench llm_demo -j 12
        if ($LASTEXITCODE -ne 0) {
            throw 'MNN Android 编译失败'
        }
    }
    finally {
        $env:TMP = $oldTmp
        $env:TEMP = $oldTemp
    }
}

# 统一封装 ADB 调用，确保所有命令都落到指定设备。
function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $prefix = @()
    if ($DeviceSerial) {
        $prefix = @('-s', $DeviceSerial)
    }
    & $Adb @prefix @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ADB 命令失败：$($Arguments -join ' ')"
    }
}

# 将可执行文件、模型和提示词推到手机，并用 SHA-256 校验关键权重。
function Push-MnnToDevice {
    Invoke-Adb shell "mkdir -p $DeviceRoot/bin $DeviceRoot/results $DeviceModel"
    Invoke-Adb push (Join-Path $BuildDir 'llm_bench') "$DeviceRoot/bin/llm_bench"
    Invoke-Adb push (Join-Path $BuildDir 'llm_demo') "$DeviceRoot/bin/llm_demo"
    Invoke-Adb shell "chmod 755 $DeviceRoot/bin/llm_bench $DeviceRoot/bin/llm_demo"

    foreach ($file in Get-ChildItem -LiteralPath $ModelDir -File) {
        Invoke-Adb push $file.FullName "$DeviceModel/$($file.Name)"
    }
    Invoke-Adb push $PromptFile "$DeviceRoot/prompt-zh.txt"

    $remoteHashLine = (& $Adb @(if ($DeviceSerial) { '-s'; $DeviceSerial }) shell `
        "sha256sum $DeviceModel/llm.mnn.weight") -join "`n"
    $remoteHash = ($remoteHashLine -split '\s+')[0].ToUpperInvariant()
    if ($remoteHash -ne $ModelWeightSha256) {
        throw "手机端模型权重 SHA-256 不匹配：$remoteHash"
    }
}

# 按线程数逐一跑 MNN 原生基准，并把 JSON 结果取回电脑。
function Invoke-MnnBench {
    New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null
    $rows = @()

    foreach ($thread in $Threads) {
        if ($CooldownSeconds -gt 0) {
            Write-Host "等待 $CooldownSeconds 秒，降低热状态对下一组的影响"
            Start-Sleep -Seconds $CooldownSeconds
        }

        $remoteName = "mnn-t$thread-r$Repeats.json"
        $localPath = Join-Path $ResultDir $remoteName
        $command = "cd $DeviceRoot && ./bin/llm_bench -m ./models/Qwen3.5-0.8B-MNN/config.json " +
            "-a cpu -t $thread -p $PromptLength -n $GenerateLength -rep $Repeats " +
            "-load true -j ./results/$remoteName"
        Invoke-Adb shell $command
        Invoke-Adb pull "$DeviceRoot/results/$remoteName" $localPath

        $data = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json
        $pp = $data.results | Where-Object { $_.type -eq 'prefill' } | Select-Object -First 1
        $tg = $data.results | Where-Object { $_.type -eq 'decode' } | Select-Object -First 1
        $rows += [pscustomobject]@{
            Threads = $thread
            PrefillTps = if ($pp) { [math]::Round($pp.tps, 2) } else { $null }
            DecodeTps = if ($tg) { [math]::Round($tg.tps, 2) } else { $null }
            LoadingSeconds = if ($tg) { [math]::Round($tg.loading_time, 2) } else { $null }
            Json = $localPath
        }
    }

    $rows | Format-Table -AutoSize
}

# 用固定中文提示词跑一次端到端生成，验证 tokenizer、模板和输出链路。
function Invoke-MnnDemo {
    $command = "cd $DeviceRoot && ./bin/llm_demo ./models/Qwen3.5-0.8B-MNN/config.json " +
        "./prompt-zh.txt 96 1"
    Invoke-Adb shell $command
}

if (-not $SkipDownload) {
    Prepare-MnnDependencies
}
if (-not $SkipBuild) {
    Build-MnnAndroid
}
if (-not $SkipPush) {
    Push-MnnToDevice
}
if (-not $SkipBench) {
    Invoke-MnnBench
}
if ($RunDemo) {
    Invoke-MnnDemo
}
