Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Worker Pack Manager：按 install_contract/uninstall_contract 执行 pack 生命周期。
# 只写 pack 声明拥有的文件，绝不修改主 config.toml 的 provider/model；secret 只查存在性。
# Executes pack lifecycle per install_contract/uninstall_contract. Writes only
# pack-owned files, never touches the main config provider/model; secrets are
# presence-checked only (value never read or printed).
Import-Module (Join-Path $PSScriptRoot "WorkerRegistry.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\hosts\codex\CodexHostAdapter.psm1") -Force

function Get-WorkerPackDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$RepoRoot = ""
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Get-WorkerRegistryRoot }
    return (Join-Path $RepoRoot "workers\native-providers\$WorkerId")
}

function Test-WorkerSecretPreflight {
    param([Parameter(Mandatory = $true)][string]$CredentialSource)

    # 只确认 credential 是否存在，绝不打印值。
    # Presence check only; the value is never read or printed.
    if ($CredentialSource -match "^env:([A-Za-z_][A-Za-z0-9_]*)$") {
        $envName = $matches[1]
        $present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($envName))
        return [pscustomobject]@{
            present = $present
            detail = "env:$envName presence checked (value never read)"
            source = $CredentialSource
        }
    }
    return [pscustomobject]@{
        present = $false
        detail = "unsupported credential source '$CredentialSource'"
        source = $CredentialSource
    }
}

function Resolve-InstallOwnedPaths {
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][string]$DestinationCodexHome
    )

    $paths = @()
    foreach ($relative in @($Descriptor.install_contract.owned_paths)) {
        $paths += (Join-Path $DestinationCodexHome ([string]$relative))
    }
    return $paths
}

function Install-WorkerPack {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$DestinationCodexHome = "",
        [string]$RepoRoot = ""
    )

    if ([string]::IsNullOrWhiteSpace($DestinationCodexHome)) { $DestinationCodexHome = Get-CodexHome }
    $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId
    if ($descriptor.runtime_type -ne "native-provider") {
        throw "worker '$WorkerId' is not a native-provider pack (install is pack-scoped)"
    }

    $packDir = Get-WorkerPackDirectory -WorkerId $WorkerId -RepoRoot $RepoRoot
    $sourceFile = Join-Path $packDir ([string]$descriptor.install_contract.config_file)
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        throw "pack source file missing for install: $sourceFile"
    }

    $written = @()
    foreach ($target in (Resolve-InstallOwnedPaths -Descriptor $descriptor -DestinationCodexHome $DestinationCodexHome)) {
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $sourceFile -Destination $target -Force
        $written += $target
    }

    return [pscustomobject]@{ worker_id = $WorkerId; written = @($written); codex_home = $DestinationCodexHome }
}

function Uninstall-WorkerPack {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$DestinationCodexHome = "",
        [string]$RepoRoot = ""
    )

    if ([string]::IsNullOrWhiteSpace($DestinationCodexHome)) { $DestinationCodexHome = Get-CodexHome }
    $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId

    $removed = @()
    foreach ($target in (Resolve-InstallOwnedPaths -Descriptor $descriptor -DestinationCodexHome $DestinationCodexHome)) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
            $removed += $target
        }
    }

    return [pscustomobject]@{ worker_id = $WorkerId; removed = @($removed) }
}

function Test-WorkerProviderAlignment {
    # 检查宿主 config.toml 的 [model_providers.*] 名称是否与 pack 的 provider_id / 别名对齐。
    # 只读 provider 段名称，不读取任何 secret 值。
    # Checks whether host config [model_providers.*] names align with the pack's
    # provider_id or declared aliases; reads section names only, never secret values.
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$CodexConfigPath = "",
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot
    $expected = [string]$descriptor.provider.provider_id
    $aliases = @()
    if ($descriptor.provider.PSObject.Properties.Name -contains "provider_aliases") {
        $aliases = @($descriptor.provider.provider_aliases | ForEach-Object { [string]$_ })
    }

    if ([string]::IsNullOrWhiteSpace($CodexConfigPath)) { $CodexConfigPath = Get-CodexConfigPath }
    $actual = @()
    if (Test-Path -LiteralPath $CodexConfigPath) {
        $content = Get-Content -Raw -LiteralPath $CodexConfigPath
        $actual = @([regex]::Matches($content, "(?m)^\s*\[model_providers\.([^\]]+)\]") | ForEach-Object { $_.Groups[1].Value.Trim() })
    }

    $matched = @($actual | Where-Object { $_ -eq $expected -or $aliases -contains $_ })
    return [pscustomobject]@{
        worker_id = $WorkerId
        expected_provider = $expected
        provider_aliases = $aliases
        actual_providers = $actual
        status = if ($matched.Count -gt 0) { "aligned" } else { "misaligned" }
    }
}

Export-ModuleMember -Function Get-WorkerPackDirectory, Test-WorkerSecretPreflight, Test-WorkerProviderAlignment, Resolve-InstallOwnedPaths, Install-WorkerPack, Uninstall-WorkerPack, Test-WorkerManifest, Load-NativeProviderWorkerManifest, ConvertFrom-BackendManifest, Get-WorkerRegistryRoot, Get-WorkerDescriptors, Get-WorkerDescriptor, Get-WorkerRuntimeType, Assert-WorkerRegistered
