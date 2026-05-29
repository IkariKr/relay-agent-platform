param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Workdir = (Get-Location).Path,

    [ValidateRange(1, 20)]
    [int]$MaxTurns = 3,

    [ValidateSet("acceptEdits", "bypassPermissions", "default", "delegate", "dontAsk", "plan")]
    [string]$PermissionMode = "acceptEdits",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Resolve-CommandPath {
    param([string]$CommandName)

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$CommandName' was not found on PATH."
    }

    return $command.Source
}

$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$claudePath = Resolve-CommandPath -CommandName "claude"
$gitPath = Get-Command git -ErrorAction SilentlyContinue
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-delegate-claude"
$stdoutLog = Join-Path $logRoot "claude-$timestamp.stdout.log"
$stderrLog = Join-Path $logRoot "claude-$timestamp.stderr.log"

$claudeArgs = @(
    "-p",
    "--permission-mode", $PermissionMode,
    "--output-format", "json",
    $Prompt
)

Write-Host "Workdir: $resolvedWorkdir"
Write-Host "Claude: $claudePath"
Write-Host "PermissionMode: $PermissionMode"
Write-Host "MaxTurns: $MaxTurns"
Write-Host "StdoutLog: $stdoutLog"
Write-Host "StderrLog: $stderrLog"

if ($WhatIf) {
    Write-Host "WhatIf: would run claude with arguments:"
    $claudeArgs | ForEach-Object { Write-Host "  $_" }
    exit 0
}

if (-not (Test-Path -LiteralPath $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot | Out-Null
}

Push-Location -LiteralPath $resolvedWorkdir
try {
    $attempt = 1
    $exitCode = 1

    while ($attempt -le $MaxTurns) {
        Write-Host "Claude attempt $attempt of $MaxTurns"

        & $claudePath @claudeArgs 1>> $stdoutLog 2>> $stderrLog
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            break
        }

        Write-Warning "Claude exited with code $exitCode."
        if ($attempt -lt $MaxTurns) {
            Write-Host "Retrying the same bounded prompt. Codex should prefer targeted correction prompts for semantic failures."
        }

        $attempt++
    }

    Write-Host ""
    Write-Host "Claude stdout:"
    if (Test-Path -LiteralPath $stdoutLog) {
        Get-Content -LiteralPath $stdoutLog
    }

    Write-Host ""
    Write-Host "Claude stderr:"
    if (Test-Path -LiteralPath $stderrLog) {
        Get-Content -LiteralPath $stderrLog
    }

    Write-Host ""
    Write-Host "Post-run git status:"
    if ($gitPath) {
        & $gitPath.Source status --short
    } else {
        Write-Host "git not found on PATH."
    }

    exit $exitCode
}
finally {
    Pop-Location
}
