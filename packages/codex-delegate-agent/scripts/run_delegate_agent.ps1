param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [ValidateSet("auto", "claude", "opencode")]
    [string]$Backend = "auto",

    [ValidateSet("config", "prefer-claude", "prefer-opencode")]
    [string]$AutoStrategy = "config",

    [string]$AutoConfigPath = "",

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

function Get-DelegateAgentPackageRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-DefaultAutoConfigSearchPaths {
    param([Parameter(Mandatory = $true)][string]$PackageRoot, [Parameter(Mandatory = $true)][string]$Workdir)

    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add((Join-Path $Workdir ".codex-delegate-agent\routing.json"))
    $paths.Add((Join-Path $Workdir ".codex-delegate-agent.json"))
    $paths.Add((Join-Path $PackageRoot "auto-routing.json"))
    $paths.Add((Join-Path $PackageRoot "auto-routing.default.json"))
    return $paths
}

function Load-AutoRoutingConfig {
    param(
        [string]$AutoConfigPath,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $candidatePaths = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($AutoConfigPath)) {
        $candidatePaths.Add($AutoConfigPath)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_DELEGATE_AGENT_CONFIG)) {
        $candidatePaths.Add($env:CODEX_DELEGATE_AGENT_CONFIG)
    }

    foreach ($path in (Get-DefaultAutoConfigSearchPaths -PackageRoot $PackageRoot -Workdir $Workdir)) {
        $candidatePaths.Add($path)
    }

    foreach ($candidate in $candidatePaths) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [pscustomobject]@{
                Path = (Resolve-Path -LiteralPath $candidate).Path
                Config = (Get-Content -Raw -LiteralPath $candidate | ConvertFrom-Json)
            }
        }
    }

    throw "No auto-routing config file was found."
}

function Test-AvailableCommand {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-RegexListMatch {
    param(
        [string]$Value,
        [object[]]$Patterns,
        [string]$Mode = "any"
    )

    if ($null -eq $Patterns -or $Patterns.Count -eq 0) {
        return $true
    }

    $matched = @($Patterns | Where-Object { $Value -match $_ })
    if ($Mode -eq "all") {
        return $matched.Count -eq $Patterns.Count
    }

    return $matched.Count -gt 0
}

function Test-RuleMatches {
    param(
        $Rule,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $when = $Rule.when
    if ($null -eq $when) {
        return $true
    }

    if ($when.prompt_any_regex -and -not (Test-RegexListMatch -Value $Prompt -Patterns $when.prompt_any_regex -Mode "any")) {
        return $false
    }

    if ($when.prompt_all_regex -and -not (Test-RegexListMatch -Value $Prompt -Patterns $when.prompt_all_regex -Mode "all")) {
        return $false
    }

    if ($when.workdir_any_regex -and -not (Test-RegexListMatch -Value $Workdir -Patterns $when.workdir_any_regex -Mode "any")) {
        return $false
    }

    if ($when.workdir_all_regex -and -not (Test-RegexListMatch -Value $Workdir -Patterns $when.workdir_all_regex -Mode "all")) {
        return $false
    }

    return $true
}

function Resolve-AutoConfiguredBackend {
    param(
        [Parameter(Mandatory = $true)]$RoutingConfig,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [Parameter(Mandatory = $true)][bool]$HasClaude,
        [Parameter(Mandatory = $true)][bool]$HasOpenCode
    )

    $ruleHit = $null
    foreach ($rule in @($RoutingConfig.Config.rules)) {
        if (Test-RuleMatches -Rule $rule -Prompt $Prompt -Workdir $Workdir) {
            $ruleHit = $rule
            break
        }
    }

    $preferredBackend = $RoutingConfig.Config.defaults.preferred_backend
    $fallbackBackend = $RoutingConfig.Config.defaults.fallback_backend
    $noMatchAction = $RoutingConfig.Config.defaults.on_no_match

    $selectedBackend = $null
    $reason = $null
    if ($ruleHit) {
        $selectedBackend = $ruleHit.backend
        $reason = if ($ruleHit.reason) { [string]$ruleHit.reason } else { "matched rule '$($ruleHit.name)'" }
    }
    else {
        switch ($noMatchAction) {
            "fallback_backend" {
                $selectedBackend = $fallbackBackend
                $reason = "no rule matched; using configured fallback backend"
            }
            default {
                $selectedBackend = $preferredBackend
                $reason = "no rule matched; using configured preferred backend"
            }
        }
    }

    $available = @{
        claude = $HasClaude
        opencode = $HasOpenCode
    }

    if ($available[$selectedBackend]) {
        return [pscustomobject]@{
            Backend = $selectedBackend
            Reason = $reason
            Rule = if ($ruleHit) { $ruleHit.name } else { "" }
        }
    }

    $fallbackCandidate = if ($selectedBackend -eq "claude") { "opencode" } else { "claude" }
    if ($available[$fallbackCandidate]) {
        return [pscustomobject]@{
            Backend = $fallbackCandidate
            Reason = "$reason; selected backend unavailable, fell back to $fallbackCandidate"
            Rule = if ($ruleHit) { $ruleHit.name } else { "" }
        }
    }

    throw "Neither Claude nor OpenCode was found on PATH."
}

function Resolve-DelegateBackend {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedBackend,
        [Parameter(Mandatory = $true)][string]$AutoStrategy,
        [string]$AutoConfigPath,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )

    $hasClaude = Test-AvailableCommand -CommandName "claude"
    $hasOpenCode = Test-AvailableCommand -CommandName "opencode"

    if ($RequestedBackend -ne "auto") {
        if ($RequestedBackend -eq "claude" -and -not $hasClaude) {
            throw "Claude was explicitly requested, but 'claude' was not found on PATH."
        }
        if ($RequestedBackend -eq "opencode" -and -not $hasOpenCode) {
            throw "OpenCode was explicitly requested, but 'opencode' was not found on PATH."
        }

        return [pscustomobject]@{
            Backend = $RequestedBackend
            Reason = "explicit backend requested"
            Rule = ""
            ConfigPath = ""
        }
    }

    if ($AutoStrategy -eq "config") {
        $routingConfig = Load-AutoRoutingConfig -AutoConfigPath $AutoConfigPath -PackageRoot $PackageRoot -Workdir $Workdir
        $resolved = Resolve-AutoConfiguredBackend `
            -RoutingConfig $routingConfig `
            -Prompt $Prompt `
            -Workdir $Workdir `
            -HasClaude $hasClaude `
            -HasOpenCode $hasOpenCode
        $resolved | Add-Member -NotePropertyName ConfigPath -NotePropertyValue $routingConfig.Path
        return $resolved
    }

    switch ($AutoStrategy) {
        "prefer-opencode" {
            if ($hasOpenCode) {
                return [pscustomobject]@{
                    Backend = "opencode"
                    Reason = "auto strategy prefer-opencode"
                    Rule = ""
                    ConfigPath = ""
                }
            }
            if ($hasClaude) {
                return [pscustomobject]@{
                    Backend = "claude"
                    Reason = "auto strategy prefer-opencode fell back to Claude"
                    Rule = ""
                    ConfigPath = ""
                }
            }
        }
        default {
            if ($hasClaude) {
                return [pscustomobject]@{
                    Backend = "claude"
                    Reason = "auto strategy prefer-claude"
                    Rule = ""
                    ConfigPath = ""
                }
            }
            if ($hasOpenCode) {
                return [pscustomobject]@{
                    Backend = "opencode"
                    Reason = "auto strategy prefer-claude fell back to OpenCode"
                    Rule = ""
                    ConfigPath = ""
                }
            }
        }
    }

    throw "Neither Claude nor OpenCode was found on PATH."
}

$packageRoot = Get-DelegateAgentPackageRoot
$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$resolution = Resolve-DelegateBackend `
    -RequestedBackend $Backend `
    -AutoStrategy $AutoStrategy `
    -AutoConfigPath $AutoConfigPath `
    -Prompt $Prompt `
    -Workdir $resolvedWorkdir `
    -PackageRoot $packageRoot
$scriptRoot = $PSScriptRoot
$claudeScript = Join-Path $scriptRoot "run_claude_delegate.ps1"
$opencodeScript = Join-Path $scriptRoot "run_opencode_delegate.ps1"

Write-Host "Resolved backend: $($resolution.Backend)"
Write-Host "AutoStrategy: $AutoStrategy"
Write-Host "RoutingReason: $($resolution.Reason)"
if (-not [string]::IsNullOrWhiteSpace($resolution.Rule)) {
    Write-Host "RoutingRule: $($resolution.Rule)"
}
if (-not [string]::IsNullOrWhiteSpace($resolution.ConfigPath)) {
    Write-Host "RoutingConfig: $($resolution.ConfigPath)"
}

if ($resolution.Backend -eq "claude") {
    $claudeParams = @{
        Prompt = $Prompt
        Workdir = $resolvedWorkdir
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
    Workdir = $resolvedWorkdir
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
