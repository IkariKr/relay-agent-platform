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

    # 运行时行为需要活宿主验证（B2 transport spike）；离线一律 unknown，fail closed。
    $liveHostDetail = "requires live Codex host; scheduled for B2 transport spike; fail-closed offline"
    $capabilities["custom_agent_spawn"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["fork_isolation"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["hook_additional_context"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["native_wait_callback"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["native_cancel"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["plaintext_initial_message"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail
    $capabilities["plaintext_followup_message"] = New-CapabilityStatus -Status "unknown" -Detail $liveHostDetail

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
    param([string]$OutputPath = "")

    $result = Get-CodexCapabilityProbeResult
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        ($result | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $OutputPath -Encoding utf8
    }
    return $result
}

Export-ModuleMember -Function New-CapabilityStatus, Test-CodexConfigStructure, Get-CodexCapabilityProbeResult, Invoke-CapabilityProbe, Get-CodexCliVersion, Get-CodexHome, Get-CodexConfigPath, Get-CodexHostInfo, Get-CodexCliInfo
