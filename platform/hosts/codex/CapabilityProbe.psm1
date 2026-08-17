Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CodeX Capability Probe：行为证据优先于版本号（roadmap §3）。
# 结构探测只证明配置/CLI 存在；运行时行为（spawn/isolation/hook/callback/plaintext）
# 离线一律 fail closed 为 unknown，不得冒充 supported。
# Behavior evidence over version numbers; structural probes only prove config/CLI
# presence; live-host behaviors fail closed as unknown offline and never fake supported.
Import-Module (Join-Path $PSScriptRoot "CodexHostAdapter.psm1") -Force

function New-CapabilityStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string[]]$Evidence = @()
    )

    return [pscustomobject]@{ status = $Status; detail = $Detail; evidence = @($Evidence) }
}

function Test-CodexConfigStructure {
    $configPath = Get-CodexConfigPath
    if (-not (Test-Path -LiteralPath $configPath)) {
        return [pscustomobject]@{ exists = $false; agents = $false; model_providers = $false; hooks = $false; path = $configPath }
    }
    $content = Get-Content -Raw -LiteralPath $configPath
    return [pscustomobject]@{
        exists = $true
        agents = ($content -match '(?m)^\s*\[agents(\.|\])')
        model_providers = ($content -match '(?m)^\s*\[model_providers(\.|\])')
        hooks = ($content -match '(?m)^\s*\[hooks(\.|\])')
        path = $configPath
    }
}

function Get-CodexCapabilityProbeResult {
    param([string]$LiveEvidenceDir = "")

    $hostInfo = Get-CodexHostInfo
    $cliInfo = Get-CodexCliInfo
    $config = Test-CodexConfigStructure

    $capabilities = [ordered]@{}

    if (-not [string]::IsNullOrWhiteSpace($cliInfo.cli_version)) {
        $capabilities["host_identity"] = New-CapabilityStatus -Status "supported" -Detail "codex cli $($cliInfo.cli_version) on PATH" -Evidence @($cliInfo.cli_source)
    }
    else {
        $capabilities["host_identity"] = New-CapabilityStatus -Status "blocked" -Detail "codex CLI not found on PATH"
    }

    if ($config.exists) {
        $detail = "config.toml present: agents=$($config.agents) model_providers=$($config.model_providers) hooks=$($config.hooks)"
        $capabilities["custom_agent_discovery"] = if ($config.agents) {
            New-CapabilityStatus -Status "supported" -Detail $detail -Evidence @($config.path)
        }
        else {
            New-CapabilityStatus -Status "unknown" -Detail "$detail; [agents] section absent (Codex may still support agent discovery)"
        }
        $capabilities["custom_provider_load"] = if ($config.model_providers) {
            New-CapabilityStatus -Status "supported" -Detail $detail -Evidence @($config.path)
        }
        else {
            New-CapabilityStatus -Status "unknown" -Detail "$detail; [model_providers] section absent (Codex may still support custom providers)"
        }
        $capabilities["hook"] = if ($config.hooks) {
            New-CapabilityStatus -Status "supported" -Detail $detail -Evidence @($config.path)
        }
        else {
            New-CapabilityStatus -Status "unknown" -Detail "$detail; [hooks] section absent (Codex may still support hooks)"
        }
    }
    else {
        $capabilities["custom_agent_discovery"] = New-CapabilityStatus -Status "unknown" -Detail "no config.toml at $($config.path)"
        $capabilities["custom_provider_load"] = New-CapabilityStatus -Status "unknown" -Detail "no config.toml at $($config.path)"
        $capabilities["hook"] = New-CapabilityStatus -Status "unknown" -Detail "no config.toml at $($config.path)"
    }

    # 运行时行为必须同时有 B4 transport 日志和与当前宿主/Codex 版本匹配的 capability report。
    # 仅有历史 JSONL 不能证明当前版本仍可用，必须 fail closed（roadmap §8.3）。
    # Runtime behaviors require both B4 transport logs and a capability report matching the
    # current host/Codex version. Historical JSONL alone cannot prove current support.
    $liveTransportEvidence = @()
    $matchingCapabilityReports = @()
    if (-not [string]::IsNullOrWhiteSpace($LiveEvidenceDir) -and (Test-Path -LiteralPath $LiveEvidenceDir)) {
        $liveTransportEvidence = @(Get-ChildItem -LiteralPath $LiveEvidenceDir -Filter "b4-native-child-*.jsonl" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $capabilityEvidenceDir = Join-Path (Split-Path -Parent $LiveEvidenceDir) "codex-capability"
        $requiredLiveCapabilities = @(
            "custom_agent_spawn",
            "fork_isolation",
            "native_wait_callback",
            "native_cancel",
            "plaintext_initial_message",
            "plaintext_followup_message"
        )

        if ($liveTransportEvidence.Count -gt 0 -and (Test-Path -LiteralPath $capabilityEvidenceDir)) {
            foreach ($reportFile in @(Get-ChildItem -LiteralPath $capabilityEvidenceDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
                try {
                    $report = Get-Content -Raw -LiteralPath $reportFile.FullName | ConvertFrom-Json
                    $hostMatches = $null -ne $report.host -and [string]$report.host.name -eq [string]$hostInfo.name
                    $versionMatches = $null -ne $report.codex -and [string]$report.codex.cli_version -eq [string]$cliInfo.cli_version
                    $allRequiredSupported = $null -ne $report.capabilities
                    foreach ($key in $requiredLiveCapabilities) {
                        if (-not $allRequiredSupported -or
                            -not ($report.capabilities.PSObject.Properties.Name -contains $key) -or
                            [string]$report.capabilities.$key.status -ne "supported") {
                            $allRequiredSupported = $false
                            break
                        }
                    }
                    if ($hostMatches -and $versionMatches -and $allRequiredSupported) {
                        $matchingCapabilityReports += $reportFile.FullName
                    }
                }
                catch {
                    # 损坏或非预期的报告不能影响 doctor；继续检查其余证据文件。
                    # A malformed report cannot affect doctor; continue checking other evidence.
                    continue
                }
            }
        }
    }
    $liveVerified = @($liveTransportEvidence + $matchingCapabilityReports)
    $liveHostDetail = "requires live Codex host; scheduled for B2 transport spike; fail-closed offline"
    $verifiedDetail = if ($matchingCapabilityReports.Count -gt 0) { "live-verified: $($liveVerified -join '; ')" } else { $liveHostDetail }
    $liveStatus = if ($matchingCapabilityReports.Count -gt 0) { "supported" } else { "unknown" }

    $capabilities["custom_agent_spawn"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    $capabilities["fork_isolation"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    $capabilities["native_wait_callback"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    $capabilities["native_cancel"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    $capabilities["plaintext_initial_message"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    $capabilities["plaintext_followup_message"] = New-CapabilityStatus -Status $liveStatus -Detail $verifiedDetail -Evidence @($liveVerified)
    # hook 为可拔除兼容层：native plaintext transport 已验证时无需 hook（roadmap 首选路径）。
    $hookDetail = if ($matchingCapabilityReports.Count -gt 0) { "hook not used; native plaintext transport verified (preferred path)" } else { $liveHostDetail }
    $capabilities["hook_additional_context"] = New-CapabilityStatus -Status $liveStatus -Detail $hookDetail -Evidence @($liveVerified)

    return [pscustomobject]@{
        probe_schema_version = "1.0"
        probe_run_id = [guid]::NewGuid().ToString("N")
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        host = $hostInfo
        codex = $cliInfo
        capabilities = $capabilities
    }
}

function Invoke-CapabilityProbe {
    param(
        [string]$OutputPath = "",
        [string]$LiveEvidenceDir = ""
    )

    $result = Get-CodexCapabilityProbeResult -LiveEvidenceDir $LiveEvidenceDir
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        ($result | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $OutputPath -Encoding utf8
    }
    return $result
}

Export-ModuleMember -Function New-CapabilityStatus, Test-CodexConfigStructure, Get-CodexCapabilityProbeResult, Invoke-CapabilityProbe, Get-CodexCliVersion, Get-CodexHome, Get-CodexConfigPath, Get-CodexHostInfo, Get-CodexCliInfo
