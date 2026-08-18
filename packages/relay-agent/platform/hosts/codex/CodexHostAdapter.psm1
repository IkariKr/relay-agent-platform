Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CodeX Host Adapter：报告宿主身份与 codex CLI 信息；全部为本地操作，无第三方付费调用。
# Reports host identity and codex CLI info; all local, no third-party paid calls.
function Get-CodexCliVersion {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return "" }
    $versionLine = (& $cmd.Source --version 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($versionLine)) { return "" }
    return (($versionLine -replace "^codex-cli\s+", "").Trim())
}

function Get-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Get-CodexConfigPath {
    return (Join-Path (Get-CodexHome) "config.toml")
}

function Get-CodexHostInfo {
    $osVersion = ""
    try {
        $osVersion = [string](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -ExpandProperty Version)
    }
    catch {
        $osVersion = [System.Environment]::OSVersion.Version.ToString()
    }
    $name = if ($IsWindows) { "win32" } elseif ($IsLinux) { "linux" } elseif ($IsMacOS) { "macos" } else { "unknown" }

    return [pscustomobject]@{
        name = $name
        os_version = $osVersion
        pwsh_version = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-CodexCliInfo {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        cli_version = Get-CodexCliVersion
        cli_source = if ($null -ne $cmd) { [string]$cmd.Source } else { "" }
    }
}

# ---- 统一 host 契约（roadmap Phase E）----
function Get-HostIdentity {
    $hostInfo = Get-CodexHostInfo
    $cliInfo = Get-CodexCliInfo
    return [pscustomobject]@{
        name = $hostInfo.name
        os_version = $hostInfo.os_version
        pwsh_version = $hostInfo.pwsh_version
        codex_cli_version = $cliInfo.cli_version
    }
}

function Test-HostNativeProviderCapability {
    # 读取 capability evidence；任一 live-host 行为非 supported 即 fail closed。
    # EvidenceDir 可注入（默认仓库 evidence 目录），保证测试确定性。
    # Reads capability evidence; any live-host behavior not 'supported' fails closed.
    # EvidenceDir is injectable (defaults to the repo evidence dir) for deterministic tests.
    param(
        [string]$CapabilityName = "native-provider-child",
        [string]$EvidenceDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
        $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $EvidenceDir = Join-Path $repoRoot "docs\evidence\codex-capability"
    }
    if (-not (Test-Path -LiteralPath $EvidenceDir)) { return $false }
    $latest = Get-ChildItem -LiteralPath $EvidenceDir -Filter "*.json" -File | Sort-Object Name | Select-Object -Last 1
    if ($null -eq $latest) { return $false }
    $probe = Get-Content -Raw -LiteralPath $latest.FullName | ConvertFrom-Json
    foreach ($key in @("custom_agent_spawn", "fork_isolation", "native_wait_callback", "native_cancel", "plaintext_initial_message")) {
        if ($probe.capabilities.$key.status -ne "supported") { return $false }
    }
    return $true
}

function Get-HostInstalledWorkerRuntimeTypes {
    return @("external-cli", "native-provider")
}

Export-ModuleMember -Function Get-CodexCliVersion, Get-CodexHome, Get-CodexConfigPath, Get-CodexHostInfo, Get-CodexCliInfo, Get-HostIdentity, Test-HostNativeProviderCapability, Get-HostInstalledWorkerRuntimeTypes
