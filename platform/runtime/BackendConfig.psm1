Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-BackendRegistryModulePath {
    $candidate = Join-Path $PSScriptRoot "BackendRegistry.psm1"
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "Unable to locate BackendRegistry.psm1 from '$PSScriptRoot'."
}

$backendRegistryModulePath = Get-BackendRegistryModulePath
Import-Module $backendRegistryModulePath -Force -DisableNameChecking

function Write-BackendConfigValue {
    param($Value)

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary])) {
        Write-Output -NoEnumerate @($Value)
        return
    }

    $Value
}

function ConvertTo-OrderedBackendConfigValue {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $ordered[$key] = ConvertTo-OrderedBackendConfigValue $InputObject[$key]
        }
        return $ordered
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$items.Add((ConvertTo-OrderedBackendConfigValue $item))
        }
        Write-BackendConfigValue -Value $items
        return
    }

    if ($InputObject -is [psobject] -and @($InputObject.PSObject.Properties).Count -gt 0) {
        $ordered = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $ordered[$property.Name] = ConvertTo-OrderedBackendConfigValue $property.Value
        }
        return $ordered
    }

    return $InputObject
}

function Merge-BackendConfigValue {
    param(
        $BaseValue,
        $OverrideValue
    )

    if ($null -eq $BaseValue) {
        Write-BackendConfigValue -Value (ConvertTo-OrderedBackendConfigValue $OverrideValue)
        return
    }

    if ($null -eq $OverrideValue) {
        Write-BackendConfigValue -Value (ConvertTo-OrderedBackendConfigValue $BaseValue)
        return
    }

    $baseOrdered = ConvertTo-OrderedBackendConfigValue $BaseValue
    $overrideOrdered = ConvertTo-OrderedBackendConfigValue $OverrideValue

    if (($baseOrdered -is [System.Collections.IDictionary]) -and ($overrideOrdered -is [System.Collections.IDictionary])) {
        $merged = [ordered]@{}
        foreach ($key in $baseOrdered.Keys) {
            if ($overrideOrdered.Contains($key)) {
                $merged[$key] = Merge-BackendConfigValue -BaseValue $baseOrdered[$key] -OverrideValue $overrideOrdered[$key]
            }
            else {
                $merged[$key] = ConvertTo-OrderedBackendConfigValue $baseOrdered[$key]
            }
        }

        foreach ($key in $overrideOrdered.Keys) {
            if (-not $merged.Contains($key)) {
                $merged[$key] = ConvertTo-OrderedBackendConfigValue $overrideOrdered[$key]
            }
        }

        return $merged
    }

    Write-BackendConfigValue -Value $overrideOrdered
    return
}

function Get-DefaultBackendConfigPath {
    param([Parameter(Mandatory = $true)][string]$BackendId)

    $context = Get-DelegateRegistryContext
    $defaultPath = if ($context.Mode -eq "package") {
        Join-Path $context.RootPath "registry\backends\$BackendId\backend.defaults.json"
    }
    else {
        Join-Path $context.RootPath "backends\$BackendId\backend.defaults.json"
    }

    if (Test-Path -LiteralPath $defaultPath) {
        return (Resolve-Path -LiteralPath $defaultPath).Path
    }

    return ""
}

function Get-BackendConfigOverridePaths {
    param(
        [Parameter(Mandatory = $true)][string]$BackendId,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    return @(
        (Join-Path $Workdir ".codex-delegate-agent\backends\$BackendId.json")
    )
}

function Load-DelegateBackendConfig {
    param(
        [Parameter(Mandatory = $true)][string]$BackendId,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    if (-not (Test-DelegateBackendRegistered -BackendId $BackendId)) {
        throw "Backend '$BackendId' is not registered."
    }

    $defaultPath = Get-DefaultBackendConfigPath -BackendId $BackendId
    $defaultConfig = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($defaultPath)) {
        $defaultConfig = ConvertTo-OrderedBackendConfigValue (Get-Content -Raw -LiteralPath $defaultPath | ConvertFrom-Json)
    }

    $resolvedOverridePath = ""
    $overrideConfig = [ordered]@{}
    foreach ($candidate in @(Get-BackendConfigOverridePaths -BackendId $BackendId -Workdir $Workdir)) {
        if (Test-Path -LiteralPath $candidate) {
            $resolvedOverridePath = (Resolve-Path -LiteralPath $candidate).Path
            $overrideConfig = ConvertTo-OrderedBackendConfigValue (Get-Content -Raw -LiteralPath $candidate | ConvertFrom-Json)
            break
        }
    }

    return [pscustomobject]@{
        BackendId = $BackendId
        DefaultPath = $defaultPath
        OverridePath = $resolvedOverridePath
        Config = (Merge-BackendConfigValue -BaseValue $defaultConfig -OverrideValue $overrideConfig)
    }
}

function Merge-DelegateBackendConfig {
    param(
        [Parameter(Mandatory = $true)]$BaseConfig,
        [Parameter(Mandatory = $true)]$OverrideConfig
    )

    return (Merge-BackendConfigValue -BaseValue $BaseConfig -OverrideValue $OverrideConfig)
}

Export-ModuleMember -Function `
    ConvertTo-OrderedBackendConfigValue, `
    Merge-BackendConfigValue, `
    Get-DefaultBackendConfigPath, `
    Get-BackendConfigOverridePaths, `
    Load-DelegateBackendConfig, `
    Merge-DelegateBackendConfig
