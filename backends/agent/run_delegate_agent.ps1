param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [ValidateSet("auto", "claude", "opencode")]
    [string]$Backend = "auto",

    [ValidateSet("prefer-claude", "prefer-opencode")]
    [string]$AutoStrategy = "prefer-claude",

    [string]$Workdir = (Get-Location).Path,

    [ValidateRange(1, 20)]
    [int]$MaxTurns = 3,

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

    [switch]$WhatIf,

    [ValidateSet("acceptEdits", "bypassPermissions", "default", "delegate", "dontAsk", "plan")]
    [string]$ClaudePermissionMode = "acceptEdits",

    [ValidateSet("json", "stream-json")]
    [string]$ClaudeOutputFormat = "json",

    [string[]]$ClaudeAllowedTools = @(),

    [string[]]$ClaudeDisallowedTools = @("Bash"),

    [switch]$ClaudeAllowBash,

    [double]$ClaudeMaxBudgetUsd = 0,

    [ValidateSet("default", "json")]
    [string]$OpencodeOutputFormat = "json",

    [string]$OpencodeModel = "",

    [ValidateSet("auto", "small", "coding", "hard", "review", "docs")]
    [string]$OpencodeModelIntent = "coding",

    [string[]]$OpencodeProviderPreference = @("opencode"),

    [switch]$OpencodeAllowPaidFallback,

    [switch]$OpencodeRefreshModels,

    [string]$OpencodeAgent = "",

    [string[]]$OpencodeAttachFiles = @(),

    [bool]$OpencodeAutoApprove = $true,

    [switch]$OpencodePrintRawJsonTail
)

$ErrorActionPreference = "Stop"

function Test-AvailableCommand {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Resolve-DelegateBackend {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedBackend,
        [Parameter(Mandatory = $true)][string]$AutoStrategy
    )

    if ($RequestedBackend -ne "auto") {
        return $RequestedBackend
    }

    $hasClaude = Test-AvailableCommand -CommandName "claude"
    $hasOpenCode = Test-AvailableCommand -CommandName "opencode"

    switch ($AutoStrategy) {
        "prefer-opencode" {
            if ($hasOpenCode) { return "opencode" }
            if ($hasClaude) { return "claude" }
        }
        default {
            if ($hasClaude) { return "claude" }
            if ($hasOpenCode) { return "opencode" }
        }
    }

    throw "Neither Claude nor OpenCode was found on PATH."
}

$resolvedBackend = Resolve-DelegateBackend -RequestedBackend $Backend -AutoStrategy $AutoStrategy
$scriptRoot = $PSScriptRoot
$claudeScript = Join-Path $scriptRoot "run_claude_delegate.ps1"
$opencodeScript = Join-Path $scriptRoot "run_opencode_delegate.ps1"

Write-Host "Resolved backend: $resolvedBackend"
Write-Host "AutoStrategy: $AutoStrategy"

if ($resolvedBackend -eq "claude") {
    $claudeParams = @{
        Prompt = $Prompt
        Workdir = $Workdir
        MaxTurns = $MaxTurns
        PermissionMode = $ClaudePermissionMode
        OutputFormat = $ClaudeOutputFormat
        AllowedTools = $ClaudeAllowedTools
        DisallowedTools = $ClaudeDisallowedTools
        MaxBudgetUsd = $ClaudeMaxBudgetUsd
        TimeoutSeconds = $TimeoutSeconds
        IdleTimeoutSeconds = $IdleTimeoutSeconds
        PollSeconds = $PollSeconds
        StatusSeconds = $StatusSeconds
        TailLines = $TailLines
        FullLog = $FullLog
        WhatIf = $WhatIf
    }

    if ($ClaudeAllowBash) {
        $claudeParams.AllowBash = $true
    }

    & $claudeScript @claudeParams
    exit $LASTEXITCODE
}

$opencodeParams = @{
    Prompt = $Prompt
    Workdir = $Workdir
    MaxTurns = $MaxTurns
    OutputFormat = $OpencodeOutputFormat
    Model = $OpencodeModel
    ModelIntent = $OpencodeModelIntent
    ProviderPreference = $OpencodeProviderPreference
    Agent = $OpencodeAgent
    AttachFiles = $OpencodeAttachFiles
    AutoApprove = $OpencodeAutoApprove
    TimeoutSeconds = $TimeoutSeconds
    IdleTimeoutSeconds = $IdleTimeoutSeconds
    PollSeconds = $PollSeconds
    StatusSeconds = $StatusSeconds
    TailLines = $TailLines
    FullLog = $FullLog
    WhatIf = $WhatIf
    PrintRawJsonTail = $OpencodePrintRawJsonTail
}

if ($OpencodeAllowPaidFallback) {
    $opencodeParams.AllowPaidFallback = $true
}

if ($OpencodeRefreshModels) {
    $opencodeParams.RefreshModels = $true
}

& $opencodeScript @opencodeParams
exit $LASTEXITCODE
