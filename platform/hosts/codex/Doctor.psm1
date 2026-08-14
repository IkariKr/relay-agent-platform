Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CodeX Doctor：把 capability probe 结果转成人类可读报告，明确"哪些能力可用、
# 哪些能力阻止 native-provider"。不调用付费模型。
# Converts capability probe results into a human-readable report that states which
# capabilities are available and which block native-provider. No paid model calls.
Import-Module (Join-Path $PSScriptRoot "CapabilityProbe.psm1") -Force

function Get-CodexCapabilityReport {
    param([Parameter(Mandatory = $true)]$ProbeResult)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("CodeX capability probe (schema $($ProbeResult.probe_schema_version), run $($ProbeResult.probe_run_id))")
    $lines.Add("  host: $($ProbeResult.host.name) / os $($ProbeResult.host.os_version) / pwsh $($ProbeResult.host.pwsh_version)")
    $lines.Add("  codex cli: $($ProbeResult.codex.cli_version) @ $($ProbeResult.codex.cli_source)")

    $blocking = New-Object System.Collections.Generic.List[string]
    foreach ($key in $ProbeResult.capabilities.Keys) {
        $cap = $ProbeResult.capabilities[$key]
        $lines.Add("  - $key = $($cap.status): $($cap.detail)")
        if ($cap.status -ne "supported") { $blocking.Add($key) }
    }

    if ($blocking.Count -gt 0) {
        $lines.Add("  VERDICT: native-provider NOT ready; blocking/unknown capabilities: $($blocking -join ', '). No third-party paid call was made.")
    }
    else {
        $lines.Add("  VERDICT: all probed capabilities supported (structural evidence).")
    }

    return ($lines -join "`n")
}

function Get-CodexCapabilityEvidencePath {
    param([string]$Root = "")

    if ([string]::IsNullOrWhiteSpace($Root)) {
        # platform/hosts/codex -> platform -> repo root
        $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $Root = Join-Path $repoRoot "docs\evidence\codex-capability"
    }

    $hostInfo = Get-CodexHostInfo
    $cliInfo = Get-CodexCliInfo
    $date = Get-Date -Format "yyyy-MM-dd"
    $version = if ($cliInfo.cli_version) { ($cliInfo.cli_version -replace "[^A-Za-z0-9._-]", "-") } else { "unknown" }

    return (Join-Path $Root "$date-codex-$version-$($hostInfo.name).json")
}

Export-ModuleMember -Function Get-CodexCapabilityReport, Get-CodexCapabilityEvidencePath, New-CapabilityStatus, Test-CodexConfigStructure, Get-CodexCapabilityProbeResult, Invoke-CapabilityProbe, Get-CodexCliVersion, Get-CodexHome, Get-CodexConfigPath, Get-CodexHostInfo, Get-CodexCliInfo
