param(
    [Parameter(Mandatory = $true)]
    [string]$Prompt,

    [string]$Backend = "auto",

    [ValidateSet("config")]
    [string]$AutoStrategy = "config",

    [string]$AutoConfigPath = "",

    [string]$Workdir = (Get-Location).Path,

    [ValidateRange(1, 20)]
    [int]$MaxTurns = 3,

    [ValidateRange(0, 604800)]
    [int]$TimeoutSeconds = 0,

    [ValidateRange(30, 86400)]
    [int]$IdleTimeoutSeconds = 600,

    [ValidateRange(1, 300)]
    [int]$PollSeconds = 30,

    [ValidateRange(1, 3600)]
    [int]$StatusSeconds = 180,

    [ValidateRange(1, 10000)]
    [int]$TailLines = 200,

    [switch]$FullLog,

    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "AutoRoutingCommon.psm1"
Import-Module $modulePath -Force -DisableNameChecking

function Get-PlatformRuntimeModulePath {
    param([Parameter(Mandatory = $true)][string]$ModuleName)

    $candidates = @(
        (Join-Path $PSScriptRoot "..\platform\runtime\$ModuleName"),
        (Join-Path $PSScriptRoot "..\..\platform\runtime\$ModuleName")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to locate platform runtime module '$ModuleName' from '$PSScriptRoot'."
}

$backendRegistryModulePath = Get-PlatformRuntimeModulePath -ModuleName "BackendRegistry.psm1"
$script:BackendRegistryModule = Import-Module $backendRegistryModulePath -Force -DisableNameChecking -PassThru

$backendConfigModulePath = Get-PlatformRuntimeModulePath -ModuleName "BackendConfig.psm1"
Import-Module $backendConfigModulePath -Force -DisableNameChecking

function Get-RegisteredDelegateBackendIdsLocal {
    & $script:BackendRegistryModule {
        Get-RegisteredDelegateBackendIds
    }
}

function Get-RegisteredBackendError {
    $knownBackends = @(Get-RegisteredDelegateBackendIdsLocal)
    return "Known backends: $($knownBackends -join ', ')."
}

function Get-DelegateRegistryContextLocal {
    & $script:BackendRegistryModule {
        Get-DelegateRegistryContext
    }
}

function Get-DelegateBackendManifestLocal {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    & $script:BackendRegistryModule {
        param($InnerBackendId)
        Get-DelegateBackendManifest -BackendId $InnerBackendId
    } $BackendId
}

function Test-DelegateBackendRegisteredLocal {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    & $script:BackendRegistryModule {
        param($InnerBackendId)
        Test-DelegateBackendRegistered -BackendId $InnerBackendId
    } $BackendId
}

function Get-DelegateBackendScriptPath {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    $manifest = Get-DelegateBackendManifestLocal -BackendId $BackendId
    $context = Get-DelegateRegistryContextLocal
    $scriptName = "run_{0}_delegate.ps1" -f $BackendId
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($context.Mode -eq "package") {
        $candidates.Add((Join-Path $context.RootPath "scripts\$scriptName"))
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$manifest.runner_script)) {
        $candidates.Add((Join-Path $context.RootPath ([string]$manifest.runner_script)))
    }

    $candidates.Add((Join-Path $PSScriptRoot $scriptName))
    $candidates.Add((Join-Path (Join-Path $PSScriptRoot "..\$BackendId") $scriptName))
    $candidates.Add((Join-Path (Join-Path $PSScriptRoot "..\..\scripts") $scriptName))

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to locate backend runner script '$scriptName' for backend '$BackendId'."
}

function Resolve-DelegateBackend {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedBackend,
        [Parameter(Mandatory = $true)][string]$AutoStrategy,
        [string]$AutoConfigPath,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )

    $availability = Get-RoutingBackendAvailabilityMap

    if ($RequestedBackend -ne "auto") {
        if (-not (Test-DelegateBackendRegisteredLocal -BackendId $RequestedBackend)) {
            throw "Backend '$RequestedBackend' is not registered. $(Get-RegisteredBackendError)"
        }

        $manifest = Get-DelegateBackendManifestLocal -BackendId $RequestedBackend
        if (-not ($availability.Contains($RequestedBackend) -and $availability[$RequestedBackend])) {
            throw "$($manifest.display_name) was explicitly requested, but '$($manifest.command)' was not found on PATH."
        }

        return [pscustomobject]@{
            Backend = $RequestedBackend
            Reason = "explicit backend requested"
            Rule = ""
            ConfigPath = ""
        }
    }

    $routingConfig = Load-AutoRoutingConfig -AutoConfigPath $AutoConfigPath -PackageRoot $PackageRoot -Workdir $Workdir
    return (Resolve-AutoConfiguredBackend `
        -RoutingConfig $routingConfig `
        -Prompt $Prompt `
        -Workdir $Workdir `
        -BackendAvailability $availability)
}

function Get-EffectiveBackendConfig {
    param(
        [Parameter(Mandatory = $true)][string]$BackendId,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    return (Load-DelegateBackendConfig -BackendId $BackendId -Workdir $Workdir)
}

function Write-TemporaryBackendConfigFile {
    param(
        [Parameter(Mandatory = $true)][string]$BackendId,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BackendConfig
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "relay-agent"
    if (-not (Test-Path -LiteralPath $tempRoot)) {
        New-Item -ItemType Directory -Path $tempRoot | Out-Null
    }

    $configPath = Join-Path $tempRoot ("{0}-{1}.json" -f $BackendId, [System.Guid]::NewGuid().ToString("N"))
    $json = $BackendConfig | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $configPath -Value $json
    return $configPath
}

function Invoke-RegisteredBackend {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$BackendId,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$BackendConfig,
        [Parameter(Mandatory = $true)][string]$ResolvedWorkdir
    )

    $tempConfigPath = Write-TemporaryBackendConfigFile -BackendId $BackendId -BackendConfig $BackendConfig
    try {
        $backendParams = @{
            Prompt = $Prompt
            Workdir = $ResolvedWorkdir
            MaxTurns = $MaxTurns
            TimeoutSeconds = $TimeoutSeconds
            IdleTimeoutSeconds = $IdleTimeoutSeconds
            PollSeconds = $PollSeconds
            StatusSeconds = $StatusSeconds
            TailLines = $TailLines
            FullLog = $FullLog
            BackendConfigPath = $tempConfigPath
            WhatIf = $WhatIf
        }

        & $ScriptPath @backendParams
        return $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $tempConfigPath -Force -ErrorAction SilentlyContinue
    }
}

$packageRoot = Get-DelegateAgentPackageRoot
$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$resolution = Resolve-DelegateBackend `
    -RequestedBackend $Backend `
    -AutoStrategy $AutoStrategy `
    -AutoConfigPath $AutoConfigPath `
    -Prompt $Prompt `
    -Workdir $resolvedWorkdir `
    -PackageRoot $packageRoot
$backendScript = Get-DelegateBackendScriptPath -BackendId $resolution.Backend
$backendConfig = Get-EffectiveBackendConfig -BackendId $resolution.Backend -Workdir $resolvedWorkdir

Write-Host "Resolved backend: $($resolution.Backend)"
Write-Host "AutoStrategy: $AutoStrategy"
Write-Host "RoutingReason: $($resolution.Reason)"
if (-not [string]::IsNullOrWhiteSpace($resolution.Rule)) {
    Write-Host "RoutingRule: $($resolution.Rule)"
}
if (-not [string]::IsNullOrWhiteSpace($resolution.ConfigPath)) {
    Write-Host "RoutingConfig: $($resolution.ConfigPath)"
}
if (-not [string]::IsNullOrWhiteSpace($backendConfig.DefaultPath)) {
    Write-Host "BackendConfigDefault: $($backendConfig.DefaultPath)"
}
if (-not [string]::IsNullOrWhiteSpace($backendConfig.OverridePath)) {
    Write-Host "BackendConfigOverride: $($backendConfig.OverridePath)"
}

$exitCode = Invoke-RegisteredBackend `
    -ScriptPath $backendScript `
    -BackendId $resolution.Backend `
    -BackendConfig $backendConfig.Config `
    -ResolvedWorkdir $resolvedWorkdir
exit $exitCode
