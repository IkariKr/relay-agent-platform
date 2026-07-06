param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Workdir = (Get-Location).Path,

    [ValidateRange(1, 20)]
    [int]$MaxTurns = 3,

    [ValidateSet("acceptEdits", "bypassPermissions", "default", "delegate", "dontAsk", "plan")]
    [string]$PermissionMode = "acceptEdits",

    [ValidateSet("json", "stream-json")]
    [string]$OutputFormat = "json",

    [AllowEmptyCollection()]
    [string[]]$AllowedTools = @(),

    [AllowEmptyCollection()]
    [string[]]$DisallowedTools = @("Bash"),

    [switch]$AllowBash,

    [double]$MaxBudgetUsd = 0,

    [ValidateRange(0, 604800)]
    [int]$TimeoutSeconds = 0,

    [ValidateRange(30, 86400)]
    [int]$IdleTimeoutSeconds = 600,

    [ValidateRange(1, 300)]
    [int]$PollSeconds = 30,

    [ValidateRange(1, 3600)]
    [int]$StatusSeconds = 180,

    [ValidateRange(1, 10000)]
    [int]$TailLines = 200,

    [switch]$FullLog,

    [string]$BackendConfigPath = "",

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "..\shared\scripts\DelegateCommon.psm1"
Import-Module $modulePath -Force

function Get-RunnerBackendConfig {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Backend config file not found: $Path"
    }

    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

$runnerBackendConfig = Get-RunnerBackendConfig -Path $BackendConfigPath
if ($null -ne $runnerBackendConfig) {
    if (-not $PSBoundParameters.ContainsKey("PermissionMode") -and $runnerBackendConfig.permission_mode) {
        $PermissionMode = [string]$runnerBackendConfig.permission_mode
    }
    if (-not $PSBoundParameters.ContainsKey("OutputFormat") -and $runnerBackendConfig.output_format) {
        $OutputFormat = [string]$runnerBackendConfig.output_format
    }
    if (-not $PSBoundParameters.ContainsKey("AllowedTools") -and $null -ne $runnerBackendConfig.allowed_tools) {
        $AllowedTools = @($runnerBackendConfig.allowed_tools | ForEach-Object { [string]$_ })
    }
    if (-not $PSBoundParameters.ContainsKey("DisallowedTools") -and $null -ne $runnerBackendConfig.disallowed_tools) {
        $DisallowedTools = @($runnerBackendConfig.disallowed_tools | ForEach-Object { [string]$_ })
    }
    if (-not $PSBoundParameters.ContainsKey("AllowBash") -and $null -ne $runnerBackendConfig.allow_bash) {
        $AllowBash = if ([bool]$runnerBackendConfig.allow_bash) { [switch]::Present } else { $false }
    }
    if (-not $PSBoundParameters.ContainsKey("MaxBudgetUsd") -and $null -ne $runnerBackendConfig.max_budget_usd) {
        $MaxBudgetUsd = [double]$runnerBackendConfig.max_budget_usd
    }
}

$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$claudePath = Resolve-DelegateCommandPath -CommandName "claude"
$runContext = New-DelegateRunContext -BackendName "codex-delegate-claude"
$stdoutLog = Join-Path $runContext.LogRoot "claude-$($runContext.Timestamp)-$($runContext.RunId).stdout.log"
$stderrLog = Join-Path $runContext.LogRoot "claude-$($runContext.Timestamp)-$($runContext.RunId).stderr.log"

$effectiveDisallowedTools = @($DisallowedTools | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($AllowBash) {
    $effectiveDisallowedTools = @($effectiveDisallowedTools | Where-Object { $_ -ne "Bash" })
}

$claudeArgs = @(
    "-p",
    "--permission-mode", $PermissionMode,
    "--output-format", $OutputFormat
)

if ($OutputFormat -eq "stream-json") {
    $claudeArgs += "--verbose"
    $claudeArgs += "--include-partial-messages"
}

if ($AllowedTools.Count -gt 0) {
    $claudeArgs += "--tools=$($AllowedTools -join ',')"
}

if ($effectiveDisallowedTools.Count -gt 0) {
    $claudeArgs += "--disallowedTools=$($effectiveDisallowedTools -join ',')"
}

if ($MaxBudgetUsd -gt 0) {
    $claudeArgs += "--max-budget-usd"
    $claudeArgs += ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $MaxBudgetUsd))
}

$claudeArgs += $Prompt

Write-Host "Workdir: $resolvedWorkdir"
Write-Host "Claude: $claudePath"
Write-Host "RunId: $($runContext.RunId)"
Write-Host "PermissionMode: $PermissionMode"
Write-Host "OutputFormat: $OutputFormat"
Write-Host "AllowedTools: $(if ($AllowedTools.Count -gt 0) { $AllowedTools -join ',' } else { 'default' })"
Write-Host "DisallowedTools: $(if ($effectiveDisallowedTools.Count -gt 0) { $effectiveDisallowedTools -join ',' } else { 'none' })"
Write-Host "MaxBudgetUsd: $(if ($MaxBudgetUsd -gt 0) { [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $MaxBudgetUsd) } else { 'disabled' })"
Write-Host "MaxTurns: $MaxTurns"
if ($TimeoutSeconds -gt 0) {
    Write-Host "TimeoutSeconds: $TimeoutSeconds"
} else {
    Write-Host "TimeoutSeconds: disabled"
}
Write-Host "IdleTimeoutSeconds: $IdleTimeoutSeconds"
Write-Host "PollSeconds: $PollSeconds"
Write-Host "StatusSeconds: $StatusSeconds"
Write-Host "TailLines: $TailLines"
Write-Host "FullLog: $FullLog"
Write-Host "StdoutLog: $stdoutLog"
Write-Host "StderrLog: $stderrLog"

if ($WhatIf) {
    Write-Host "WhatIf: would run claude with arguments:"
    $claudeArgs | ForEach-Object { Write-Host "  $_" }
    exit 0
}

Push-Location -LiteralPath $resolvedWorkdir
try {
    $attempt = 1
    $exitCode = 1

    while ($attempt -le $MaxTurns) {
        Write-Host "Claude attempt $attempt of $MaxTurns"

        $exitCode = Invoke-DelegateAttempt `
            -Label "Claude" `
            -FilePath $claudePath `
            -Arguments $claudeArgs `
            -StdoutPath $stdoutLog `
            -StderrPath $stderrLog `
            -Timeout $TimeoutSeconds `
            -IdleTimeout $IdleTimeoutSeconds `
            -Poll $PollSeconds `
            -StatusInterval $StatusSeconds

        if ($exitCode -eq 0) {
            break
        }

        if ($exitCode -eq 124 -or $exitCode -eq 125) {
            Write-Warning "Claude was stopped due to timeout/idle detection. Codex should inspect the diff before deciding whether to continue."
            break
        }

        Write-Warning "Claude exited with code $exitCode."
        if ($attempt -lt $MaxTurns) {
            Write-Host "Retrying the same bounded prompt. Codex should prefer targeted correction prompts for semantic failures."
        }

        $attempt++
    }

    Write-DelegateLogs -Label "Claude" -StdoutPath $stdoutLog -StderrPath $stderrLog -TailLines $TailLines -FullLog ([bool]$FullLog)
    Write-DelegatePostRunStatus -Workdir $resolvedWorkdir

    exit $exitCode
}
finally {
    Pop-Location
}
