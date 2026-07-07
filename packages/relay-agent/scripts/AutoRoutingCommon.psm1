Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-BackendRegistryModulePath {
    $candidates = @(
        (Join-Path $PSScriptRoot "..\platform\runtime\BackendRegistry.psm1"),
        (Join-Path $PSScriptRoot "..\..\platform\runtime\BackendRegistry.psm1")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to locate BackendRegistry.psm1 from '$PSScriptRoot'."
}

$backendRegistryModulePath = Get-BackendRegistryModulePath
Import-Module $backendRegistryModulePath -Force -DisableNameChecking

function ConvertTo-OrderedRoutingValue {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-OrderedRoutingValue $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ,(ConvertTo-OrderedRoutingValue $item)
        }
        return $result
    }

    $propertyBag = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $propertyBag[$property.Name] = ConvertTo-OrderedRoutingValue $property.Value
    }
    return $propertyBag
}

function Get-DelegateAgentPackageRoot {
    $localCandidate = Join-Path $PSScriptRoot "auto-routing.default.json"
    if (Test-Path -LiteralPath $localCandidate) {
        return (Resolve-Path -LiteralPath $PSScriptRoot).Path
    }

    $parentPath = Resolve-Path (Join-Path $PSScriptRoot "..")
    $parentCandidate = Join-Path $parentPath "auto-routing.default.json"
    if (Test-Path -LiteralPath $parentCandidate) {
        return $parentPath.Path
    }

    throw "Unable to locate delegate agent package root from '$PSScriptRoot'."
}

function Get-RegisteredRoutingBackendIds {
    return @(Get-RegisteredDelegateBackendIds)
}

function Assert-RegisteredRoutingBackend {
    param([string]$BackendId, [string]$Context = "routing config")

    if ([string]::IsNullOrWhiteSpace($BackendId)) {
        return
    }

    if (-not (Test-DelegateBackendRegistered -BackendId $BackendId)) {
        $known = @(Get-RegisteredRoutingBackendIds)
        throw "Backend '$BackendId' is not registered for $Context. Known backends: $($known -join ', ')."
    }
}

function Get-RoutingBackendAvailabilityMap {
    param([string[]]$BackendIds = @())

    return (Get-DelegateBackendAvailabilityMap -BackendIds $BackendIds)
}

function Get-DefaultUserRoutingConfigPath {
    param([Parameter(Mandatory = $true)][string]$Workdir)

    return (Join-Path $Workdir ".relay-agent\routing.json")
}

function Get-DefaultAutoConfigSearchPaths {
    param([Parameter(Mandatory = $true)][string]$PackageRoot, [Parameter(Mandatory = $true)][string]$Workdir)

    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add((Get-DefaultUserRoutingConfigPath -Workdir $Workdir))
    $paths.Add((Join-Path $Workdir ".relay-agent.json"))
    $paths.Add((Join-Path $PackageRoot "auto-routing.json"))
    $paths.Add((Join-Path $PackageRoot "auto-routing.default.json"))
    return $paths
}

function Get-DefaultTemplateRoutingConfig {
    return [ordered]@{
        version = 2
        defaults = [ordered]@{
            preferred_backend = "claude"
            fallback_backends = @("opencode")
            on_no_match = "preferred_backend"
        }
        rules = @()
    }
}

function Normalize-RoutingDefaults {
    param($Defaults)

    $data = if ($null -eq $Defaults) { [ordered]@{} } else { ConvertTo-OrderedRoutingValue $Defaults }
    $preferredBackend = if ($data.Contains("preferred_backend")) { [string]$data.preferred_backend } else { "claude" }
    Assert-RegisteredRoutingBackend -BackendId $preferredBackend -Context "routing defaults preferred_backend"

    $fallbackBackends = @()
    if ($data.Contains("fallback_backends")) {
        $fallbackBackends = @($data.fallback_backends | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })
    }
    elseif ($data.Contains("fallback_backend") -and -not [string]::IsNullOrWhiteSpace([string]$data.fallback_backend)) {
        $fallbackBackends = @([string]$data.fallback_backend)
    }
    else {
        $fallbackBackends = @("opencode")
    }

    $distinctFallbackBackends = New-Object System.Collections.Generic.List[string]
    foreach ($backendId in $fallbackBackends) {
        Assert-RegisteredRoutingBackend -BackendId $backendId -Context "routing defaults fallback_backends"
        if (-not $distinctFallbackBackends.Contains($backendId)) {
            $distinctFallbackBackends.Add($backendId)
        }
    }

    return [ordered]@{
        preferred_backend = $preferredBackend
        fallback_backends = @($distinctFallbackBackends)
        fallback_backend = if ($distinctFallbackBackends.Count -gt 0) { $distinctFallbackBackends[0] } else { "" }
        on_no_match = if ($data.Contains("on_no_match")) { [string]$data.on_no_match } else { "preferred_backend" }
    }
}

function Normalize-RoutingRule {
    param([Parameter(Mandatory = $true)]$Rule)

    $data = ConvertTo-OrderedRoutingValue $Rule
    $when = if ($data.Contains("when")) { ConvertTo-OrderedRoutingValue $data.when } else { [ordered]@{} }
    $promptAny = if ($when.Contains("prompt_any_regex")) { @($when["prompt_any_regex"]) } else { @() }
    $promptAll = if ($when.Contains("prompt_all_regex")) { @($when["prompt_all_regex"]) } else { @() }
    $workdirAny = if ($when.Contains("workdir_any_regex")) { @($when["workdir_any_regex"]) } else { @() }
    $workdirAll = if ($when.Contains("workdir_all_regex")) { @($when["workdir_all_regex"]) } else { @() }
    $backendId = if ($data.Contains("backend")) { [string]$data.backend } else { "claude" }
    Assert-RegisteredRoutingBackend -BackendId $backendId -Context "routing rule"

    return [ordered]@{
        name = if ($data.Contains("name")) { [string]$data.name } else { "" }
        enabled = if ($data.Contains("enabled")) { [bool]$data.enabled } else { $true }
        backend = $backendId
        reason = if ($data.Contains("reason")) { [string]$data.reason } else { "" }
        when = [ordered]@{
            prompt_any_regex = @($promptAny | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            prompt_all_regex = @($promptAll | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            workdir_any_regex = @($workdirAny | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            workdir_all_regex = @($workdirAll | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
}

function Normalize-AutoRoutingConfig {
    param($Config)

    $data = if ($null -eq $Config) { Get-DefaultTemplateRoutingConfig } else { ConvertTo-OrderedRoutingValue $Config }
    $rules = @()
    $defaultsInput = $null
    if ($data.Contains("defaults")) {
        $defaultsInput = $data.defaults
    }
    $inputRules = if ($data.Contains("rules")) { @($data["rules"]) } else { @() }
    foreach ($rule in $inputRules) {
        $rules += ,(Normalize-RoutingRule -Rule $rule)
    }

    return [ordered]@{
        version = if ($data.Contains("version")) { [int]$data.version } else { 2 }
        defaults = (Normalize-RoutingDefaults -Defaults $defaultsInput)
        rules = $rules
    }
}

function ConvertTo-PersistedRoutingConfig {
    param([Parameter(Mandatory = $true)]$Config)

    $normalized = Normalize-AutoRoutingConfig $Config
    return [ordered]@{
        version = 2
        defaults = [ordered]@{
            preferred_backend = $normalized.defaults.preferred_backend
            fallback_backends = @($normalized.defaults.fallback_backends)
            on_no_match = $normalized.defaults.on_no_match
        }
        rules = @(
            foreach ($rule in @($normalized.rules)) {
                $normalizedRule = Normalize-RoutingRule -Rule $rule
                [ordered]@{
                    name = $normalizedRule.name
                    enabled = $normalizedRule.enabled
                    backend = $normalizedRule.backend
                    reason = $normalizedRule.reason
                    when = [ordered]@{
                        prompt_any_regex = @($normalizedRule.when.prompt_any_regex)
                        prompt_all_regex = @($normalizedRule.when.prompt_all_regex)
                        workdir_any_regex = @($normalizedRule.when.workdir_any_regex)
                        workdir_all_regex = @($normalizedRule.when.workdir_all_regex)
                    }
                }
            }
        )
    }
}

function Load-AutoRoutingConfig {
    param(
        [string]$AutoConfigPath,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $candidatePaths = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($AutoConfigPath)) {
        $candidatePaths.Add($AutoConfigPath)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:RELAY_AGENT_CONFIG)) {
        $candidatePaths.Add($env:RELAY_AGENT_CONFIG)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_DELEGATE_AGENT_CONFIG)) {
        $candidatePaths.Add($env:CODEX_DELEGATE_AGENT_CONFIG)
    }

    foreach ($path in (Get-DefaultAutoConfigSearchPaths -PackageRoot $PackageRoot -Workdir $Workdir)) {
        $candidatePaths.Add($path)
    }

    foreach ($candidate in $candidatePaths) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [pscustomobject]@{
                Path = (Resolve-Path -LiteralPath $candidate).Path
                Config = (Normalize-AutoRoutingConfig (Get-Content -Raw -LiteralPath $candidate | ConvertFrom-Json))
            }
        }
    }

    throw "No auto-routing config file was found."
}

function Save-AutoRoutingConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Config
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $persisted = ConvertTo-PersistedRoutingConfig -Config $Config
    $json = $persisted | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $Path -Value $json
}

function New-DefaultUserRoutingConfig {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force) {
        throw "Routing config already exists: $DestinationPath"
    }

    $templatePath = Join-Path $PackageRoot "auto-routing.default.json"
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Routing template not found: $templatePath"
    }

    $template = Normalize-AutoRoutingConfig (Get-Content -Raw -LiteralPath $templatePath | ConvertFrom-Json)
    Save-AutoRoutingConfig -Path $DestinationPath -Config $template
    return (Resolve-Path -LiteralPath $DestinationPath).Path
}

function Get-EditableRoutingConfigPath {
    param(
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return $ConfigPath
    }

    return (Get-DefaultUserRoutingConfigPath -Workdir $Workdir)
}

function Get-OrCreateEditableRoutingConfig {
    param(
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $targetPath = Get-EditableRoutingConfigPath -ConfigPath $ConfigPath -Workdir $Workdir
    if (-not (Test-Path -LiteralPath $targetPath)) {
        $null = New-DefaultUserRoutingConfig -PackageRoot $PackageRoot -DestinationPath $targetPath
    }

    return [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $targetPath).Path
        Config = (Normalize-AutoRoutingConfig (Get-Content -Raw -LiteralPath $targetPath | ConvertFrom-Json))
    }
}

function Find-RoutingRuleIndex {
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$RuleName
    )

    for ($i = 0; $i -lt @($Config.rules).Count; $i++) {
        if ([string]$Config.rules[$i].name -eq $RuleName) {
            return $i
        }
    }
    return -1
}

function Get-RoutingRuleConditionSummary {
    param([Parameter(Mandatory = $true)]$Rule)

    $parts = @()
    if (@($Rule.when.prompt_any_regex).Count -gt 0) {
        $parts += "prompt_any=" + (@($Rule.when.prompt_any_regex) -join ", ")
    }
    if (@($Rule.when.prompt_all_regex).Count -gt 0) {
        $parts += "prompt_all=" + (@($Rule.when.prompt_all_regex) -join ", ")
    }
    if (@($Rule.when.workdir_any_regex).Count -gt 0) {
        $parts += "workdir_any=" + (@($Rule.when.workdir_any_regex) -join ", ")
    }
    if (@($Rule.when.workdir_all_regex).Count -gt 0) {
        $parts += "workdir_all=" + (@($Rule.when.workdir_all_regex) -join ", ")
    }

    if ($parts.Count -eq 0) {
        return "(no conditions)"
    }

    return ($parts -join " | ")
}

function Test-RegexListMatch {
    param(
        [string]$Value,
        [object[]]$Patterns,
        [string]$Mode = "any"
    )

    if ($null -eq $Patterns -or $Patterns.Count -eq 0) {
        return $true
    }

    $matched = @($Patterns | Where-Object { $Value -match $_ })
    if ($Mode -eq "all") {
        return $matched.Count -eq $Patterns.Count
    }

    return $matched.Count -gt 0
}

function Test-RuleMatches {
    param(
        $Rule,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $ruleData = Normalize-RoutingRule -Rule $Rule
    if (-not $ruleData.enabled) {
        return $false
    }

    if (-not (Test-RegexListMatch -Value $Prompt -Patterns $ruleData.when.prompt_any_regex -Mode "any")) {
        return $false
    }
    if (-not (Test-RegexListMatch -Value $Prompt -Patterns $ruleData.when.prompt_all_regex -Mode "all")) {
        return $false
    }
    if (-not (Test-RegexListMatch -Value $Workdir -Patterns $ruleData.when.workdir_any_regex -Mode "any")) {
        return $false
    }
    if (-not (Test-RegexListMatch -Value $Workdir -Patterns $ruleData.when.workdir_all_regex -Mode "all")) {
        return $false
    }

    return $true
}

function Resolve-AutoConfiguredBackend {
    param(
        [Parameter(Mandatory = $true)]$RoutingConfig,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [hashtable]$BackendAvailability = $null,
        [bool]$HasClaude = $false,
        [bool]$HasOpenCode = $false
    )

    $config = Normalize-AutoRoutingConfig $RoutingConfig.Config
    $ruleHit = $null
    foreach ($rule in @($config.rules)) {
        if (Test-RuleMatches -Rule $rule -Prompt $Prompt -Workdir $Workdir) {
            $ruleHit = $rule
            break
        }
    }

    $availability = [ordered]@{}
    if ($null -ne $BackendAvailability -and $BackendAvailability.Count -gt 0) {
        foreach ($backendId in $BackendAvailability.Keys) {
            $availability[[string]$backendId] = [bool]$BackendAvailability[$backendId]
        }
    }
    else {
        foreach ($pair in (Get-RoutingBackendAvailabilityMap).GetEnumerator()) {
            $availability[[string]$pair.Key] = [bool]$pair.Value
        }
        if (-not $availability.Contains("claude")) {
            $availability["claude"] = $HasClaude
        }
        if (-not $availability.Contains("opencode")) {
            $availability["opencode"] = $HasOpenCode
        }
    }

    $preferredBackend = $config.defaults.preferred_backend
    $fallbackBackends = @($config.defaults.fallback_backends)
    $noMatchAction = $config.defaults.on_no_match

    $selectedBackend = $null
    $reason = $null
    if ($ruleHit) {
        $selectedBackend = $ruleHit.backend
        $reason = if ($ruleHit.reason) { [string]$ruleHit.reason } else { "matched rule '$($ruleHit.name)'" }
    }
    else {
        switch ($noMatchAction) {
            "fallback_backend" {
                if ($fallbackBackends.Count -gt 0) {
                    $selectedBackend = $fallbackBackends[0]
                    $reason = "no rule matched; using configured fallback backend"
                }
                else {
                    $selectedBackend = $preferredBackend
                    $reason = "no rule matched; fallback_backends was empty, using configured preferred backend"
                }
            }
            default {
                $selectedBackend = $preferredBackend
                $reason = "no rule matched; using configured preferred backend"
            }
        }
    }

    if ($availability.Contains($selectedBackend) -and $availability[$selectedBackend]) {
        return [pscustomobject]@{
            Backend = $selectedBackend
            Reason = $reason
            Rule = if ($ruleHit) { $ruleHit.name } else { "" }
            ConfigPath = $RoutingConfig.Path
        }
    }

    $orderedFallbackCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($backendId in $fallbackBackends) {
        if ($backendId -ne $selectedBackend -and -not $orderedFallbackCandidates.Contains($backendId)) {
            $orderedFallbackCandidates.Add($backendId)
        }
    }

    foreach ($pair in $availability.GetEnumerator()) {
        if ($pair.Key -ne $selectedBackend -and -not $orderedFallbackCandidates.Contains([string]$pair.Key)) {
            $orderedFallbackCandidates.Add([string]$pair.Key)
        }
    }

    foreach ($fallbackCandidate in $orderedFallbackCandidates) {
        if ($availability.Contains($fallbackCandidate) -and $availability[$fallbackCandidate]) {
            return [pscustomobject]@{
                Backend = $fallbackCandidate
                Reason = "$reason; selected backend unavailable, fell back to $fallbackCandidate"
                Rule = if ($ruleHit) { $ruleHit.name } else { "" }
                ConfigPath = $RoutingConfig.Path
            }
        }
    }

    $checkedBackends = @($availability.Keys)
    throw "No registered backend commands were found on PATH. Checked backends: $($checkedBackends -join ', ')."
}

Export-ModuleMember -Function `
    ConvertTo-OrderedRoutingValue, `
    Get-DelegateAgentPackageRoot, `
    Get-RegisteredRoutingBackendIds, `
    Assert-RegisteredRoutingBackend, `
    Get-RoutingBackendAvailabilityMap, `
    Get-DefaultUserRoutingConfigPath, `
    Get-DefaultAutoConfigSearchPaths, `
    Get-DefaultTemplateRoutingConfig, `
    Normalize-RoutingDefaults, `
    Normalize-RoutingRule, `
    Normalize-AutoRoutingConfig, `
    ConvertTo-PersistedRoutingConfig, `
    Load-AutoRoutingConfig, `
    Save-AutoRoutingConfig, `
    New-DefaultUserRoutingConfig, `
    Get-EditableRoutingConfigPath, `
    Get-OrCreateEditableRoutingConfig, `
    Find-RoutingRuleIndex, `
    Get-RoutingRuleConditionSummary, `
    Test-RegexListMatch, `
    Test-RuleMatches, `
    Resolve-AutoConfiguredBackend
