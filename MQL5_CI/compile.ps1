# ============================================================
# MQL5 CI Compiler (Full / Changed Mode)
# Requires: PowerShell 7+
# ============================================================

[CmdletBinding()]
param(
    [ValidateSet("All", "Changed")]
    [string]$Mode = "Changed",

    # Changed 模式下，比較基準
    # 本地常用: HEAD~1
    # GitHub Actions 可考慮用 origin/main 或 github.event.before
    [string]$BaseRef = "HEAD~1",

    # 平行數量
    [int]$ThrottleLimit = 4
)

# ------------------------------------------------------------
# 1️⃣ MetaEditor 路徑
# ------------------------------------------------------------
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"

# ------------------------------------------------------------
# 2️⃣ 路徑設定
# ------------------------------------------------------------
$scriptRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptRoot
$mainLog = Join-Path $scriptRoot "compile_all.log"

# ------------------------------------------------------------
# 3️⃣ 基本檢查
# ------------------------------------------------------------
if (-not (Test-Path $metaeditor)) {
    Write-Error "MetaEditor not found: $metaeditor"
    exit 2
}

if (-not (Test-Path $projectRoot)) {
    Write-Error "Project root not found: $projectRoot"
    exit 2
}

Write-Host "===================================="
Write-Host "MQL5 CI Compiler"
Write-Host "Mode         : $Mode"
Write-Host "BaseRef      : $BaseRef"
Write-Host "Project Root : $projectRoot"
Write-Host "MetaEditor   : $metaeditor"
Write-Host "===================================="

# ------------------------------------------------------------
# 4️⃣ 取得編譯清單
# ------------------------------------------------------------
function Get-AllMq5Files {
    param(
        [string]$Root
    )

    Get-ChildItem -Path $Root -Recurse -Filter *.mq5 -File |
        Select-Object -ExpandProperty FullName
}

function Get-ChangedMq5Files {
    param(
        [string]$Root,
        [string]$BaseRefValue
    )

    # 確認是不是 git repo
    git -C $Root rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Current project is not a git repository. No changed files can be detected."
        return @()
    }

    # 確認 BaseRef 是否存在；不存在就退回 HEAD~1，再不行就回傳空
    git -C $Root rev-parse --verify $BaseRefValue *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "BaseRef '$BaseRefValue' not found. Trying HEAD~1 ..."
        $BaseRefValue = "HEAD~1"

        git -C $Root rev-parse --verify $BaseRefValue *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "HEAD~1 also not found. No changed files can be detected."
            return @()
        }
    }

    # 只抓新增/修改/重新命名的 mq5
    $changed = git -C $Root diff --name-only --diff-filter=AMR $BaseRefValue HEAD |
        Where-Object { $_ -match '\.mq5$' }

    if (-not $changed) {
        return @()
    }

    $fullPaths = foreach ($relPath in $changed) {
        Join-Path $Root $relPath
    }

    # 過濾不存在的檔案 + 去重
    $fullPaths |
        Where-Object { Test-Path $_ } |
        Select-Object -Unique
}

switch ($Mode) {
    "All" {
        Write-Host "📦 Full mode: compiling all .mq5 files..."
        $mq5Files = Get-AllMq5Files -Root $projectRoot
    }
    "Changed" {
        Write-Host "🔍 Changed mode: compiling changed .mq5 files..."
        $mq5Files = Get-ChangedMq5Files -Root $projectRoot -BaseRefValue $BaseRef
    }
    default {
        Write-Error "Unknown Mode: $Mode"
        exit 2
    }
}

# 統一轉陣列
$mq5Files = @($mq5Files | Select-Object -Unique)

if (-not $mq5Files -or $mq5Files.Count -eq 0) {
    Write-Host "✅ No mq5 files to compile."
    "" | Out-File $mainLog -Encoding utf8
    Add-Content $mainLog "No mq5 files to compile."
    exit 0
}

Write-Host "Found $($mq5Files.Count) file(s) to compile:"
$mq5Files | ForEach-Object { Write-Host " - $_" }

# ------------------------------------------------------------
# 5️⃣ 清空主 Log
# ------------------------------------------------------------
"" | Out-File $mainLog -Encoding utf8

# ------------------------------------------------------------
# 6️⃣ 平行編譯
# ------------------------------------------------------------
$results = $mq5Files | ForEach-Object -Parallel {

    $fullPath = $_
    $tempLog = Join-Path $env:TEMP ("mql5_" + [Guid]::NewGuid().ToString() + ".log")
    $arguments = "/compile:`"$fullPath`" /log:`"$tempLog`""

    try {
        $process = Start-Process $using:metaeditor `
            -ArgumentList $arguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -ErrorAction Stop

        if (Test-Path $tempLog) {
            $logContent = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
            Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
        }
        else {
            $logContent = "ERROR: No log generated"
        }

        $errors = 0
        $warnings = 0
        $lines = $logContent -split "`r?`n"

        foreach ($line in $lines) {
            if ($line -match "Total Errors:\s*(\d+)") {
                $errors = [int]$matches[1]
            }

            if ($line -match "Total Warnings:\s*(\d+)") {
                $warnings = [int]$matches[1]
            }
        }

        [PSCustomObject]@{
            File      = $fullPath
            Errors    = $errors
            Warnings  = $warnings
            ExitCode  = $process.ExitCode
            Log       = $logContent
        }
    }
    catch {
        [PSCustomObject]@{
            File      = $fullPath
            Errors    = 1
            Warnings  = 0
            ExitCode  = -1
            Log       = "EXCEPTION: $($_.Exception.Message)"
        }
    }

} -ThrottleLimit $ThrottleLimit

# ------------------------------------------------------------
# 7️⃣ 主執行緒統一寫入 Log
# ------------------------------------------------------------
$totalErrors = 0
$totalWarnings = 0

foreach ($r in $results) {

    Add-Content $mainLog "===================================="
    Add-Content $mainLog "File: $($r.File)"
    Add-Content $mainLog "ExitCode: $($r.ExitCode)"
    Add-Content $mainLog "Errors: $($r.Errors)"
    Add-Content $mainLog "Warnings: $($r.Warnings)"
    Add-Content $mainLog "------------------------------------"
    Add-Content $mainLog $r.Log

    $totalErrors += [int]$r.Errors
    $totalWarnings += [int]$r.Warnings
}

Add-Content $mainLog "===================================="
Add-Content $mainLog "SUMMARY"
Add-Content $mainLog "Mode: $Mode"
Add-Content $mainLog "BaseRef: $BaseRef"
Add-Content $mainLog "Compiled Files: $($mq5Files.Count)"
Add-Content $mainLog "Total Errors: $totalErrors"
Add-Content $mainLog "Total Warnings: $totalWarnings"
Add-Content $mainLog "===================================="

# ------------------------------------------------------------
# 8️⃣ Console summary
# ------------------------------------------------------------
Write-Host "===================================="
Write-Host "SUMMARY"
Write-Host "Mode: $Mode"
Write-Host "BaseRef: $BaseRef"
Write-Host "Compiled Files: $($mq5Files.Count)"
Write-Host "Total Errors: $totalErrors"
Write-Host "Total Warnings: $totalWarnings"
Write-Host "Log: $mainLog"
Write-Host "===================================="

# ------------------------------------------------------------
# 9️⃣ CI exit code
# ------------------------------------------------------------
if ($totalErrors -gt 0) {
    Write-Host "❌ CI FAILED"
    exit 1
}
else {
    Write-Host "🎉 CI PASSED"
    exit 0
}