Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Worker Runtime Registry：跨 runtime 的统一 worker 视图。
# external-cli 由 legacy Backend Registry 经 adapter 归一化；native-provider 由
# NativeProviderWorkerLoader 直接加载。worker id 是后续 install/doctor/dispatch/audit 的稳定主键。
# Unified worker view across runtimes. external-cli workers are normalized from the
# legacy Backend Registry via the adapter; native-provider manifests load directly.
# worker id is the stable key for install/doctor/dispatch/audit.
Import-Module (Join-Path $PSScriptRoot "NativeProviderWorkerLoader.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "ExternalCliWorkerAdapter.psm1") -Force

function Get-WorkerRegistryRoot {
    $platformDir = Split-Path -Parent $PSScriptRoot
    return (Split-Path -Parent $platformDir)
}

function Get-NativeProviderWorkerPaths {
    param([string]$NativeProviderRoot = "")

    if ([string]::IsNullOrWhiteSpace($NativeProviderRoot)) {
        $NativeProviderRoot = Join-Path (Get-WorkerRegistryRoot) "workers\native-providers"
    }
    if (-not (Test-Path -LiteralPath $NativeProviderRoot)) { return @() }
    return @(Get-ChildItem -Path $NativeProviderRoot -Filter "worker.json" -Recurse -File | ForEach-Object { $_.FullName })
}

function Get-ExternalCliBackendManifestPaths {
    param([string]$BackendRoot = "")

    if ([string]::IsNullOrWhiteSpace($BackendRoot)) {
        $BackendRoot = Join-Path (Get-WorkerRegistryRoot) "backends"
    }
    if (-not (Test-Path -LiteralPath $BackendRoot)) { return @() }
    return @(Get-ChildItem -Path $BackendRoot -Filter "backend.json" -Recurse -File | ForEach-Object { $_.FullName })
}

function Get-WorkerDescriptors {
    param(
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    # 使用普通数组而非 List[object]：PS 7.6 中 @() 作用于 List[object] 会抛
    # "Argument types do not match"。Plain array avoids a PS 7.6 binding quirk
    # where @() over List[object] throws "Argument types do not match".
    $workers = @()

    foreach ($path in (Get-NativeProviderWorkerPaths -NativeProviderRoot $NativeProviderRoot)) {
        $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        if (-not (Test-WorkerManifest -Manifest $manifest)) {
            throw "invalid native-provider worker manifest: $path"
        }
        $workers += [pscustomobject]@{
                runtime_type = "native-provider"
                id = $manifest.id
                descriptor = $manifest
                source_path = $path
            }
    }

    foreach ($path in (Get-ExternalCliBackendManifestPaths -BackendRoot $BackendRoot)) {
        $manifest = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $descriptor = ConvertFrom-BackendManifest -BackendManifest $manifest
        $workers += [pscustomobject]@{
                runtime_type = "external-cli"
                id = $descriptor.id
                descriptor = $descriptor
                source_path = $path
            }
    }

    return $workers
}

function Get-WorkerDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    foreach ($item in (Get-WorkerDescriptors -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot)) {
        if ($item.id -eq $WorkerId) { return $item.descriptor }
    }
    throw "worker '$WorkerId' is not registered"
}

function Get-WorkerRuntimeType {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    foreach ($item in (Get-WorkerDescriptors -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot)) {
        if ($item.id -eq $WorkerId) { return $item.runtime_type }
    }
    throw "worker '$WorkerId' is not registered"
}

function Assert-WorkerRegistered {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    $null = Get-WorkerRuntimeType -WorkerId $WorkerId -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot
}

Export-ModuleMember -Function Get-WorkerRegistryRoot, Get-NativeProviderWorkerPaths, Get-ExternalCliBackendManifestPaths, Get-WorkerDescriptors, Get-WorkerDescriptor, Get-WorkerRuntimeType, Assert-WorkerRegistered, Test-WorkerManifest, Load-NativeProviderWorkerManifest, ConvertFrom-BackendManifest
