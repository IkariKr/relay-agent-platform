Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$sharedRoot = Join-Path $repoRoot "shared"
$backendRoot = Join-Path $repoRoot "backends"
$surfaceRoot = Join-Path $repoRoot "surfaces"
$platformRoot = Join-Path $repoRoot "platform"

function Assert-FileExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "Missing required file: $Path"
    }
}

function Assert-FileContentMatches {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $sourceContent = Get-Content -Raw -LiteralPath $SourcePath
    $destinationContent = Get-Content -Raw -LiteralPath $DestinationPath
    if ($sourceContent -ne $destinationContent) {
        Write-Error $Message
    }
}

function Get-SurfaceManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Get-SurfaceManifests {
    return @(
        Get-ChildItem -Path $surfaceRoot -Filter "surface.json" -Recurse -File |
            Sort-Object FullName |
            ForEach-Object { Get-SurfaceManifest -Path $_.FullName }
    )
}

function Get-BackendManifestRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    return [pscustomobject]@{
        Id = [string]$manifest.id
        Manifest = $manifest
        ManifestPath = $Path
        DirectoryPath = (Split-Path -Parent $Path)
    }
}

function Get-BackendManifestRecords {
    return @(
        Get-ChildItem -Path $backendRoot -Filter "backend.json" -Recurse -File |
            Sort-Object FullName |
            ForEach-Object { Get-BackendManifestRecord -Path $_.FullName }
    )
}

function Get-BackendManifestRecordById {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    $record = Get-BackendManifestRecords | Where-Object { $_.Id -eq $BackendId } | Select-Object -First 1
    if ($null -eq $record) {
        throw "Backend manifest not found for '$BackendId'."
    }

    return $record
}

function Resolve-RepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return (Join-Path $repoRoot $RelativePath)
}

function Get-SurfacePackageRoot {
    param([Parameter(Mandatory = $true)]$Surface)

    if ([string]$Surface.package_root -eq ".") {
        return $repoRoot.Path
    }

    return (Join-Path $repoRoot ([string]$Surface.package_root))
}

function Get-BackendRunnerSourcePath {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    $record = Get-BackendManifestRecordById -BackendId $BackendId
    return (Resolve-RepoRelativePath -RelativePath ([string]$record.Manifest.runner_script))
}

function Get-BackendRunnerDestinationPath {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPackageRoot,
        [Parameter(Mandatory = $true)][string]$BackendId
    )

    return (Join-Path $DestinationPackageRoot ("scripts\run_{0}_delegate.ps1" -f $BackendId))
}

function Get-RoutingReferencedBackendIds {
    param([Parameter(Mandatory = $true)][string]$RoutingConfigPath)

    $config = Get-Content -Raw -LiteralPath $RoutingConfigPath | ConvertFrom-Json
    $backendIds = New-Object System.Collections.Generic.List[string]

    if ($config.defaults.preferred_backend) {
        $backendIds.Add([string]$config.defaults.preferred_backend)
    }
    if ($config.defaults.PSObject.Properties.Name -contains "fallback_backend" -and $config.defaults.fallback_backend) {
        $backendIds.Add([string]$config.defaults.fallback_backend)
    }
    foreach ($backendId in @($config.defaults.fallback_backends)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$backendId)) {
            $backendIds.Add([string]$backendId)
        }
    }
    foreach ($rule in @($config.rules)) {
        if ($rule.backend) {
            $backendIds.Add([string]$rule.backend)
        }
    }

    return @($backendIds | Sort-Object -Unique)
}

function Assert-RunDelegateAgentUsesRuntimeBackendValidation {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    $source = Get-Content -Raw -LiteralPath $ScriptPath
    $match = [regex]::Match($source, '\[ValidateSet\((?<values>[^)]*)\)\]\s*\[string\]\$Backend')
    if ($match.Success) {
        Write-Error "run_delegate_agent.ps1 still hardcodes backend ValidateSet values. Phase 2+ expects runtime registry validation."
    }

    if ($source -notmatch 'Test-DelegateBackendRegistered' -and $source -notmatch 'Get-DelegateBackendManifest') {
        Write-Error "run_delegate_agent.ps1 does not appear to validate backend ids through the registry runtime."
    }

    $legacyParameters = @(
        "ClaudePermissionMode",
        "ClaudeOutputFormat",
        "ClaudeAllowedTools",
        "ClaudeDisallowedTools",
        "ClaudeAllowBash",
        "ClaudeMaxBudgetUsd",
        "OpencodeOutputFormat",
        "OpencodeModel",
        "OpencodeModelIntent",
        "OpencodeProviderPreference",
        "OpencodeAllowPaidFallback",
        "OpencodeRefreshModels",
        "OpencodeAgent",
        "OpencodeAttachFiles",
        "OpencodeAutoApprove",
        "OpencodePrintRawJsonTail"
    )
    foreach ($parameterName in $legacyParameters) {
        if ($source -match ('\${0}\b' -f [regex]::Escape($parameterName))) {
            Write-Error "run_delegate_agent.ps1 still exposes deprecated unified-surface backend-specific parameter '$parameterName'."
        }
    }

    if ($source -match 'prefer-claude' -or $source -match 'prefer-opencode') {
        Write-Error "run_delegate_agent.ps1 still exposes deprecated backend-specific AutoStrategy compatibility values."
    }
}

Assert-FileExists -Path (Join-Path $sharedRoot "scripts\DelegateCommon.psm1")
Assert-FileExists -Path (Join-Path $repoRoot "scripts\run_claude_delegate.ps1")

foreach ($contractFile in Get-ChildItem -Path (Join-Path $platformRoot "contracts") -Recurse -File) {
    Assert-FileExists -Path $contractFile.FullName
}

foreach ($backendRecord in @(Get-BackendManifestRecords)) {
    Assert-FileExists -Path $backendRecord.ManifestPath
    Assert-FileExists -Path (Resolve-RepoRelativePath -RelativePath ([string]$backendRecord.Manifest.runner_script))
    Assert-FileExists -Path (Resolve-RepoRelativePath -RelativePath ([string]$backendRecord.Manifest.docs_path))

    $defaultConfigPath = Join-Path $backendRecord.DirectoryPath "backend.defaults.json"
    if (Test-Path -LiteralPath $defaultConfigPath) {
        Assert-FileExists -Path $defaultConfigPath
    }
}

$backendIds = @(Get-BackendManifestRecords | ForEach-Object { $_.Id }) | Sort-Object -Unique
$surfaceManifests = @(Get-SurfaceManifests)

foreach ($surface in $surfaceManifests) {
    $packageRoot = Get-SurfacePackageRoot -Surface $surface

    Assert-FileExists -Path (Join-Path $packageRoot "SKILL.md")
    Assert-FileExists -Path (Join-Path $packageRoot "agents\openai.yaml")

    if ([string]$surface.package_root -ne ".") {
        Assert-FileContentMatches `
            -SourcePath (Join-Path $sharedRoot "scripts\DelegateCommon.psm1") `
            -DestinationPath (Join-Path $packageRoot "shared\scripts\DelegateCommon.psm1") `
            -Message "Shared module copy is out of sync for surface '$($surface.id)'. Run scripts/build-packages.ps1."
    }

    $surfaceBackendIds = switch ([string]$surface.mode) {
        "single-backend" { @([string]$surface.default_backend) }
        "router" { @($surface.allowed_backends | ForEach-Object { [string]$_ }) }
        default { Write-Error "Unsupported surface mode '$($surface.mode)' for '$($surface.id)'."; @() }
    }

    foreach ($backendId in $surfaceBackendIds) {
        if ($backendIds -notcontains $backendId) {
            Write-Error "Surface '$($surface.id)' references backend '$backendId', but no backend manifest exists."
            continue
        }

        $sourcePath = Get-BackendRunnerSourcePath -BackendId $backendId
        $destinationPath = Get-BackendRunnerDestinationPath -DestinationPackageRoot $packageRoot -BackendId $backendId
        if ([System.IO.Path]::GetFullPath($sourcePath) -ne [System.IO.Path]::GetFullPath($destinationPath)) {
            Assert-FileExists -Path $destinationPath
            Assert-FileContentMatches `
                -SourcePath $sourcePath `
                -DestinationPath $destinationPath `
                -Message "Backend runner copy is out of sync for surface '$($surface.id)' backend '$backendId'. Run scripts/build-packages.ps1."
        }
    }

    foreach ($scriptRelativePath in @($surface.public_scripts)) {
        $sourcePath = Resolve-RepoRelativePath -RelativePath ([string]$scriptRelativePath)
        $destinationPath = Join-Path $packageRoot ("scripts\" + [System.IO.Path]::GetFileName([string]$scriptRelativePath))
        Assert-FileExists -Path $destinationPath
        Assert-FileContentMatches `
            -SourcePath $sourcePath `
            -DestinationPath $destinationPath `
            -Message "Public script copy is out of sync for surface '$($surface.id)': $scriptRelativePath. Run scripts/build-packages.ps1."
    }

    foreach ($asset in @($surface.public_assets)) {
        $sourcePath = Resolve-RepoRelativePath -RelativePath ([string]$asset.source)
        $destinationPath = Join-Path $packageRoot ([string]$asset.target)
        Assert-FileExists -Path $destinationPath
        Assert-FileContentMatches `
            -SourcePath $sourcePath `
            -DestinationPath $destinationPath `
            -Message "Public asset copy is out of sync for surface '$($surface.id)': $($asset.source). Run scripts/build-packages.ps1."
    }

    if ([string]$surface.mode -eq "router") {
        foreach ($runtimeFile in Get-ChildItem -Path (Join-Path $platformRoot "runtime") -Recurse -File) {
            $relativeRuntimePath = [System.IO.Path]::GetRelativePath((Join-Path $platformRoot "runtime"), $runtimeFile.FullName)
            $destinationRuntimePath = Join-Path $packageRoot "platform\runtime\$relativeRuntimePath"
            Assert-FileExists -Path $destinationRuntimePath
            Assert-FileContentMatches `
                -SourcePath $runtimeFile.FullName `
                -DestinationPath $destinationRuntimePath `
                -Message "Platform runtime copy is out of sync for router surface '$($surface.id)': $relativeRuntimePath. Run scripts/build-packages.ps1."
        }

        foreach ($backendRecord in @(Get-BackendManifestRecords)) {
            $registryManifestPath = Join-Path $packageRoot "registry\backends\$($backendRecord.Id)\backend.json"
            Assert-FileExists -Path $registryManifestPath
            Assert-FileContentMatches `
                -SourcePath $backendRecord.ManifestPath `
                -DestinationPath $registryManifestPath `
                -Message "Router surface '$($surface.id)' backend registry manifest is out of sync for '$($backendRecord.Id)'. Run scripts/build-packages.ps1."

            $defaultConfigPath = Join-Path $backendRecord.DirectoryPath "backend.defaults.json"
            if (Test-Path -LiteralPath $defaultConfigPath) {
                $registryDefaultConfigPath = Join-Path $packageRoot "registry\backends\$($backendRecord.Id)\backend.defaults.json"
                Assert-FileExists -Path $registryDefaultConfigPath
                Assert-FileContentMatches `
                    -SourcePath $defaultConfigPath `
                    -DestinationPath $registryDefaultConfigPath `
                    -Message "Router surface '$($surface.id)' backend default config is out of sync for '$($backendRecord.Id)'. Run scripts/build-packages.ps1."
            }
        }

        foreach ($surfaceManifestFile in Get-ChildItem -Path $surfaceRoot -Filter "surface.json" -Recurse -File) {
            $surfaceId = Split-Path -Leaf (Split-Path -Parent $surfaceManifestFile.FullName)
            $registrySurfacePath = Join-Path $packageRoot "registry\surfaces\$surfaceId\surface.json"
            Assert-FileExists -Path $registrySurfacePath
            Assert-FileContentMatches `
                -SourcePath $surfaceManifestFile.FullName `
                -DestinationPath $registrySurfacePath `
                -Message "Router surface '$($surface.id)' surface registry manifest is out of sync for '$surfaceId'. Run scripts/build-packages.ps1."
        }

        $runDelegateScriptRelativePath = @($surface.public_scripts | Where-Object { ([System.IO.Path]::GetFileName([string]$_)) -eq "run_delegate_agent.ps1" } | Select-Object -First 1)
        if ($runDelegateScriptRelativePath.Count -gt 0) {
            Assert-RunDelegateAgentUsesRuntimeBackendValidation -ScriptPath (Resolve-RepoRelativePath -RelativePath ([string]$runDelegateScriptRelativePath[0]))
        }

        foreach ($asset in @($surface.public_assets)) {
            if ([System.IO.Path]::GetFileName([string]$asset.target) -ne "auto-routing.default.json") {
                continue
            }

            $sourcePath = Resolve-RepoRelativePath -RelativePath ([string]$asset.source)
            $destinationPath = Join-Path $packageRoot ([string]$asset.target)
            $routingBackendIds = @(
                (Get-RoutingReferencedBackendIds -RoutingConfigPath $sourcePath) +
                (Get-RoutingReferencedBackendIds -RoutingConfigPath $destinationPath)
            ) | Sort-Object -Unique

            foreach ($backendId in $routingBackendIds) {
                if ($backendIds -notcontains $backendId) {
                    Write-Error "Routing config for surface '$($surface.id)' references backend '$backendId', but no backend manifest exists."
                }

                $runnerPath = Get-BackendRunnerDestinationPath -DestinationPackageRoot $packageRoot -BackendId $backendId
                Assert-FileExists -Path $runnerPath
            }
        }
    }
}

Write-Host "Package validation passed."
