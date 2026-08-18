Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Host Adapter 契约与 capability detector（roadmap Phase E）。
# 每个宿主模块导出统一接口：Get-HostIdentity / Test-HostNativeProviderCapability /
# Get-HostInstalledWorkerRuntimeTypes；detector 据此决定可安装的 runtime。
# Each host module exports a uniform interface; the detector derives installable runtimes.
function Get-HostCapabilityReport {
    param(
        [Parameter(Mandatory = $true)][string]$HostModulePath,
        # 可注入 evidence 目录，便于确定性测试；空值表示宿主默认。
        # Optional injected evidence dir for deterministic tests; empty = host default.
        [string]$EvidenceDir = ""
    )

    Import-Module $HostModulePath -Force
    $hostModule = Get-Module ([System.IO.Path]::GetFileNameWithoutExtension($HostModulePath))

    return [pscustomobject]@{
        identity = (& $hostModule Get-HostIdentity)
        native_provider_capable = (& $hostModule Test-HostNativeProviderCapability -EvidenceDir $EvidenceDir)
        installable_runtime_types = @(& $hostModule Get-HostInstalledWorkerRuntimeTypes)
    }
}

function Get-InstallableWorkerDescriptorsForHost {
    param(
        [Parameter(Mandatory = $true)][string]$HostModulePath,
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "registry\WorkerRegistry.psm1") -Force
    $report = Get-HostCapabilityReport -HostModulePath $HostModulePath
    $installable = @($report.installable_runtime_types)

    return @(
        Get-WorkerDescriptors -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot |
            Where-Object { $installable -contains $_.runtime_type }
    )
}

Export-ModuleMember -Function Get-HostCapabilityReport, Get-InstallableWorkerDescriptorsForHost
