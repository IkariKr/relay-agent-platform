Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-DelegateRegistryContext {
    $rootCandidate = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $packageBackendRoot = Join-Path $rootCandidate "registry\backends"
    $packageSurfaceRoot = Join-Path $rootCandidate "registry\surfaces"
    if ((Test-Path -LiteralPath $packageBackendRoot) -and (Test-Path -LiteralPath $packageSurfaceRoot)) {
        return [pscustomobject]@{
            RootPath = $rootCandidate
            BackendRoot = $packageBackendRoot
            SurfaceRoot = $packageSurfaceRoot
            Mode = "package"
        }
    }

    $repoBackendRoot = Join-Path $rootCandidate "backends"
    $repoSurfaceRoot = Join-Path $rootCandidate "surfaces"
    if ((Test-Path -LiteralPath $repoBackendRoot) -and (Test-Path -LiteralPath $repoSurfaceRoot)) {
        return [pscustomobject]@{
            RootPath = $rootCandidate
            BackendRoot = $repoBackendRoot
            SurfaceRoot = $repoSurfaceRoot
            Mode = "repo"
        }
    }

    throw "Unable to locate backend/surface registry roots from '$PSScriptRoot'."
}

function Get-ManifestFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    @(Get-ChildItem -Path $RootPath -Filter $FileName -Recurse -File | Sort-Object FullName)
}

function Read-DelegateManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    Add-Member -InputObject $manifest -NotePropertyName "__manifest_path" -NotePropertyValue $Path -Force
    return $manifest
}

function Get-DelegateBackendRegistry {
    $context = Get-DelegateRegistryContext
    $files = Get-ManifestFiles -RootPath $context.BackendRoot -FileName "backend.json"
    return @($files | ForEach-Object { Read-DelegateManifest -Path $_.FullName })
}

function Get-DelegateSurfaceRegistry {
    $context = Get-DelegateRegistryContext
    $files = Get-ManifestFiles -RootPath $context.SurfaceRoot -FileName "surface.json"
    return @($files | ForEach-Object { Read-DelegateManifest -Path $_.FullName })
}

function Get-RegisteredDelegateBackendIds {
    return @((Get-DelegateBackendRegistry | ForEach-Object { [string]$_.id }) | Sort-Object -Unique)
}

function Get-RegisteredDelegateSurfaceIds {
    return @((Get-DelegateSurfaceRegistry | ForEach-Object { [string]$_.id }) | Sort-Object -Unique)
}

function Get-DelegateBackendManifest {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    $manifest = Get-DelegateBackendRegistry | Where-Object { [string]$_.id -eq $BackendId } | Select-Object -First 1
    if ($null -eq $manifest) {
        throw "Backend '$BackendId' is not registered."
    }

    return $manifest
}

function Get-DelegateSurfaceManifest {
    param([Parameter(Mandatory = $true)][string]$SurfaceId)

    $manifest = Get-DelegateSurfaceRegistry | Where-Object { [string]$_.id -eq $SurfaceId } | Select-Object -First 1
    if ($null -eq $manifest) {
        throw "Surface '$SurfaceId' is not registered."
    }

    return $manifest
}

function Test-DelegateBackendRegistered {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    return $null -ne (Get-DelegateBackendRegistry | Where-Object { [string]$_.id -eq $BackendId } | Select-Object -First 1)
}

function Get-DelegateBackendAvailabilityMap {
    param([string[]]$BackendIds = @())

    $selectedIds = if (@($BackendIds).Count -gt 0) { @($BackendIds) } else { @(Get-RegisteredDelegateBackendIds) }
    $availability = [ordered]@{}
    foreach ($backendId in $selectedIds) {
        $manifest = Get-DelegateBackendManifest -BackendId $backendId
        $availability[$backendId] = ($null -ne (Get-Command ([string]$manifest.command) -ErrorAction SilentlyContinue))
    }

    return $availability
}

Export-ModuleMember -Function `
    Get-DelegateRegistryContext, `
    Get-DelegateBackendRegistry, `
    Get-DelegateSurfaceRegistry, `
    Get-RegisteredDelegateBackendIds, `
    Get-RegisteredDelegateSurfaceIds, `
    Get-DelegateBackendManifest, `
    Get-DelegateSurfaceManifest, `
    Test-DelegateBackendRegistered, `
    Get-DelegateBackendAvailabilityMap
