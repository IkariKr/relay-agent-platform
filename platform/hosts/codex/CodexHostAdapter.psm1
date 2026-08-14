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

Export-ModuleMember -Function Get-CodexCliVersion, Get-CodexHome, Get-CodexConfigPath, Get-CodexHostInfo, Get-CodexCliInfo
