param(
    [Parameter(Mandatory = $true)]
    [string]$Request,

    [string]$Workdir = (Get-Location).Path,

    [string]$ConfigPath = "",

    [ValidateSet("text", "json")]
    [string]$OutputFormat = "text",

    [switch]$Apply,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$manageScriptPath = Join-Path $PSScriptRoot "manage_auto_routing.ps1"
if (-not (Test-Path -LiteralPath $manageScriptPath)) {
    throw "Routing management script not found: $manageScriptPath"
}

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

function Get-QuotedValues {
    param([Parameter(Mandatory = $true)][string]$Text)

    $quotedPattern = '"([^"]+)"|''([^'']+)''|\u201C([^\u201D]+)\u201D|\u2018([^\u2019]+)\u2019'
    $matches = [regex]::Matches($Text, $quotedPattern)
    $values = @()
    foreach ($match in $matches) {
        foreach ($group in $match.Groups | Select-Object -Skip 1) {
            if ($group.Success -and -not [string]::IsNullOrWhiteSpace($group.Value)) {
                $values += $group.Value.Trim()
                break
            }
        }
    }

    return $values
}

function Remove-WrappingQuotes {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $doubleQuote = [string][char]34
    $singleQuote = [string][char]39
    $leftDoubleQuote = [string][char]0x201C
    $rightDoubleQuote = [string][char]0x201D
    $leftSingleQuote = [string][char]0x2018
    $rightSingleQuote = [string][char]0x2019
    $trimmed = $Value.Trim()
    if (
        ($trimmed.StartsWith($doubleQuote) -and $trimmed.EndsWith($doubleQuote)) -or
        ($trimmed.StartsWith($singleQuote) -and $trimmed.EndsWith($singleQuote)) -or
        ($trimmed.StartsWith($leftDoubleQuote) -and $trimmed.EndsWith($rightDoubleQuote)) -or
        ($trimmed.StartsWith($leftSingleQuote) -and $trimmed.EndsWith($rightSingleQuote))
    ) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Trim()
    }

    return $trimmed
}

function Get-FieldValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Labels
    )

    $escapedLabels = @($Labels | ForEach-Object { [regex]::Escape($_) })
    $labelPattern = ($escapedLabels -join "|")
    $pattern = "(?is)(?:^|[;,\uFF0C\uFF1B:\uFF1A\r\n]|\s)(?:$labelPattern)\s*[:=]\s*(?<value>""[^""]+""|'[^']+'|\u201C[^\u201D]+\u201D|\u2018[^\u2019]+\u2019|.+?)(?=\s*(?:[,;\uFF0C\uFF1B]\s*[A-Za-z][A-Za-z0-9 _-]*\s*[:=]|[;\uFF1B\r\n]|$))"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return ""
    }

    return (Remove-WrappingQuotes $match.Groups["value"].Value)
}

function Split-FieldList {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    if ($Value -match '^(?i)(none|null|empty|clear)$') {
        return @()
    }

    $items = @()
    foreach ($part in ($Value -split '\s*(?:,|\uFF0C|;|\uFF1B|\|)\s*')) {
        $trimmed = (Remove-WrappingQuotes $part).Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $items += $trimmed
        }
    }

    return $items
}

function Convert-KeywordToRegex {
    param([Parameter(Mandatory = $true)][string]$Keyword)

    $escaped = [regex]::Escape($Keyword)
    if ($Keyword -match '^[A-Za-z0-9._-]+$') {
        return "(?i)\b$escaped\b"
    }

    return "(?i)$escaped"
}

function Convert-KeywordsToRegexList {
    param([string[]]$Keywords)

    $patterns = @()
    foreach ($keyword in @($Keywords)) {
        if (-not [string]::IsNullOrWhiteSpace($keyword)) {
            $patterns += (Convert-KeywordToRegex -Keyword $keyword.Trim())
        }
    }

    return $patterns
}

function Get-BackendValue {
    param([Parameter(Mandatory = $true)][string]$Text)

    $labeled = Get-FieldValue -Text $Text -Labels @("backend", "route to")
    $registry = @(Get-DelegateBackendRegistry)
    foreach ($manifest in $registry) {
        $backendId = [string]$manifest.id
        $commandName = [string]$manifest.command
        $displayName = [string]$manifest.display_name
        $productName = [string]$manifest.product_name
        $patterns = @(
            "(?i)\b$([regex]::Escape($backendId))\b",
            "(?i)\b$([regex]::Escape($commandName))\b"
        )
        if (-not [string]::IsNullOrWhiteSpace($displayName)) {
            $patterns += "(?i)$([regex]::Escape($displayName))"
        }
        if (-not [string]::IsNullOrWhiteSpace($productName)) {
            $patterns += "(?i)$([regex]::Escape($productName))"
        }

        foreach ($pattern in $patterns) {
            if ($labeled -match $pattern) {
                return $backendId
            }
        }
    }

    foreach ($manifest in $registry) {
        $backendId = [string]$manifest.id
        $commandName = [string]$manifest.command
        $displayName = [string]$manifest.display_name
        $productName = [string]$manifest.product_name
        $patterns = @(
            "(?i)\b$([regex]::Escape($backendId))\b",
            "(?i)\b$([regex]::Escape($commandName))\b"
        )
        if (-not [string]::IsNullOrWhiteSpace($displayName)) {
            $patterns += "(?i)$([regex]::Escape($displayName))"
        }
        if (-not [string]::IsNullOrWhiteSpace($productName)) {
            $patterns += "(?i)$([regex]::Escape($productName))"
        }

        foreach ($pattern in $patterns) {
            if ($Text -match $pattern) {
                return $backendId
            }
        }
    }

    return ""
}

function Get-RequestedAction {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($Text -match '(?i)\b(init|initialize)\b|\u521d\u59cb\u5316') { return "init-user-config" }
    if ($Text -match '(?i)\b(disable|turn off)\b|\u7981\u7528|\u505c\u7528') { return "disable" }
    if ($Text -match '(?i)\b(enable|turn on)\b|\u542f\u7528') { return "enable" }
    if ($Text -match '(?i)\b(remove|delete)\b|\u5220\u9664|\u79fb\u9664') { return "remove" }
    if ($Text -match '(?i)\b(update|change|modify|edit)\b|\u4fee\u6539|\u66f4\u65b0|\u6539\u6210|\u6539\u4e3a') { return "update" }
    if ($Text -match '(?i)\b(add|create|insert)\b|\u65b0\u589e|\u6dfb\u52a0|\u589e\u52a0|\u521b\u5efa') { return "add" }
    if ($Text -match '(?i)\b(explain|why)\b|\u89e3\u91ca|\u4e3a\u4ec0\u4e48|\u547d\u4e2d|\u8d70\u54ea\u4e2a|\u600e\u4e48\u8def\u7531') { return "explain" }
    if ($Text -match '(?i)\b(list|show|view)\b|\u5217\u51fa|\u67e5\u770b|\u663e\u793a|\u770b\u770b') { return "list" }

    throw "Unable to infer routing action from request. Try using words like list, explain, add, update, disable, enable, remove, or init."
}

function Get-RuleNameValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Action
    )

    $namedField = Get-FieldValue -Text $Text -Labels @("rule name", "rulename", "rule", "name")
    if (-not [string]::IsNullOrWhiteSpace($namedField)) {
        return $namedField
    }

    if ($Action -in @("disable", "enable", "remove", "update")) {
        $quoted = @(Get-QuotedValues -Text $Text)
        if ($quoted.Count -gt 0) {
            return $quoted[0]
        }
    }

    return ""
}

function Get-ExplainPromptValue {
    param([Parameter(Mandatory = $true)][string]$Text)

    $promptField = Get-FieldValue -Text $Text -Labels @("prompt", "message", "text")
    if (-not [string]::IsNullOrWhiteSpace($promptField)) {
        return $promptField
    }

    $quoted = @(Get-QuotedValues -Text $Text)
    if ($quoted.Count -gt 0) {
        return $quoted[0]
    }

    return ""
}

function Get-RegexSelection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$RegexLabels,
        [Parameter(Mandatory = $true)][string[]]$KeywordLabels
    )

    $directRegex = Split-FieldList (Get-FieldValue -Text $Text -Labels $RegexLabels)
    if ($directRegex.Count -gt 0) {
        return $directRegex
    }

    $keywords = Split-FieldList (Get-FieldValue -Text $Text -Labels $KeywordLabels)
    if ($keywords.Count -gt 0) {
        return (Convert-KeywordsToRegexList -Keywords $keywords)
    }

    return @()
}

function Get-EnabledValue {
    param([Parameter(Mandatory = $true)][string]$Text)

    $value = Get-FieldValue -Text $Text -Labels @("enabled")
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    if ($value -match '^(?i)(true|yes|on|enabled|1)$') {
        return $true
    }
    if ($value -match '^(?i)(false|no|off|disabled|0)$') {
        return $false
    }

    throw "Unable to parse enabled value '$value'."
}

function ConvertTo-RuleSlugSegment {
    param([Parameter(Mandatory = $true)][string]$Value)

    $normalized = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $normalized = $normalized.Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ""
    }

    return $normalized
}

function New-InferredRuleName {
    param(
        [string]$Backend,
        [string[]]$PromptAnyRegex,
        [string[]]$WorkdirAnyRegex
    )

    $segments = @()
    if (-not [string]::IsNullOrWhiteSpace($Backend)) {
        $segments += (ConvertTo-RuleSlugSegment -Value $Backend)
    }

    foreach ($pattern in @($PromptAnyRegex + $WorkdirAnyRegex)) {
        $slug = ConvertTo-RuleSlugSegment -Value $pattern
        if (-not [string]::IsNullOrWhiteSpace($slug)) {
            $segments += $slug
        }
        if ($segments.Count -ge 3) {
            break
        }
    }

    if ($segments.Count -eq 0) {
        $segments = @("routing-rule")
    }

    return (($segments | Select-Object -First 3) -join "-")
}

function New-RoutingInterpretation {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Action
    )

    $backend = Get-BackendValue -Text $Text
    $ruleName = Get-RuleNameValue -Text $Text -Action $Action
    $reason = Get-FieldValue -Text $Text -Labels @("reason")
    $promptAnyRegex = Get-RegexSelection `
        -Text $Text `
        -RegexLabels @("prompt_any_regex", "prompt regex", "prompt any regex") `
        -KeywordLabels @("prompt keywords", "prompt keyword", "keywords")
    $promptAllRegex = Get-RegexSelection `
        -Text $Text `
        -RegexLabels @("prompt_all_regex", "prompt all regex") `
        -KeywordLabels @("prompt all keywords")
    $workdirAnyRegex = Get-RegexSelection `
        -Text $Text `
        -RegexLabels @("workdir_any_regex", "workdir regex", "workdir any regex") `
        -KeywordLabels @("workdir keywords", "workdir keyword")
    $workdirAllRegex = Get-RegexSelection `
        -Text $Text `
        -RegexLabels @("workdir_all_regex", "workdir all regex") `
        -KeywordLabels @("workdir all keywords")
    $enabled = Get-EnabledValue -Text $Text
    $prompt = ""

    if ($Action -eq "explain") {
        $prompt = Get-ExplainPromptValue -Text $Text
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            throw 'Explain request needs a prompt. Example: prompt: "please review this API design"'
        }
    }

    if ($Action -eq "add") {
        if ([string]::IsNullOrWhiteSpace($backend)) {
            throw "Add request needs a backend. Example: backend: opencode"
        }
        if ([string]::IsNullOrWhiteSpace($ruleName)) {
            $ruleName = New-InferredRuleName -Backend $backend -PromptAnyRegex $promptAnyRegex -WorkdirAnyRegex $workdirAnyRegex
        }
    }

    if ($Action -in @("update", "disable", "enable", "remove")) {
        if ([string]::IsNullOrWhiteSpace($ruleName)) {
            throw "$Action request needs a rule name. Example: rule: `"quick-fixes`""
        }
    }

    return [pscustomobject]@{
        Action = $Action
        RuleName = $ruleName
        Backend = $backend
        Reason = $reason
        Prompt = $prompt
        PromptAnyRegex = @($promptAnyRegex)
        PromptAllRegex = @($promptAllRegex)
        WorkdirAnyRegex = @($workdirAnyRegex)
        WorkdirAllRegex = @($workdirAllRegex)
        Enabled = $enabled
    }
}

function Get-ManageScriptArguments {
    param(
        [Parameter(Mandatory = $true)]$Interpretation,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [string]$ConfigPath,
        [switch]$Force
    )

    $arguments = [ordered]@{
        Action = $Interpretation.Action
        Workdir = $Workdir
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $arguments.ConfigPath = $ConfigPath
    }

    switch ($Interpretation.Action) {
        "explain" {
            $arguments.Prompt = $Interpretation.Prompt
        }
        "init-user-config" {
            if ($Force) {
                $arguments.Force = $true
            }
        }
        "add" {
            $arguments.RuleName = $Interpretation.RuleName
            $arguments.Backend = $Interpretation.Backend
            if (-not [string]::IsNullOrWhiteSpace($Interpretation.Reason)) {
                $arguments.Reason = $Interpretation.Reason
            }
            if ($Interpretation.PromptAnyRegex.Count -gt 0) { $arguments.PromptAnyRegex = $Interpretation.PromptAnyRegex }
            if ($Interpretation.PromptAllRegex.Count -gt 0) { $arguments.PromptAllRegex = $Interpretation.PromptAllRegex }
            if ($Interpretation.WorkdirAnyRegex.Count -gt 0) { $arguments.WorkdirAnyRegex = $Interpretation.WorkdirAnyRegex }
            if ($Interpretation.WorkdirAllRegex.Count -gt 0) { $arguments.WorkdirAllRegex = $Interpretation.WorkdirAllRegex }
            if ($null -ne $Interpretation.Enabled) { $arguments.Enabled = $Interpretation.Enabled }
        }
        "update" {
            $arguments.RuleName = $Interpretation.RuleName
            if (-not [string]::IsNullOrWhiteSpace($Interpretation.Backend)) { $arguments.Backend = $Interpretation.Backend }
            if ($Interpretation.Reason -ne "") { $arguments.Reason = $Interpretation.Reason }
            if ($Interpretation.PromptAnyRegex.Count -gt 0 -or $Request -match '(?i)prompt keywords|prompt keyword|keywords|prompt regex|prompt any regex|prompt_any_regex') {
                $arguments.PromptAnyRegex = $Interpretation.PromptAnyRegex
            }
            if ($Interpretation.PromptAllRegex.Count -gt 0 -or $Request -match '(?i)prompt all keywords|prompt all regex|prompt_all_regex') {
                $arguments.PromptAllRegex = $Interpretation.PromptAllRegex
            }
            if ($Interpretation.WorkdirAnyRegex.Count -gt 0 -or $Request -match '(?i)workdir keywords|workdir keyword|workdir regex|workdir any regex|workdir_any_regex') {
                $arguments.WorkdirAnyRegex = $Interpretation.WorkdirAnyRegex
            }
            if ($Interpretation.WorkdirAllRegex.Count -gt 0 -or $Request -match '(?i)workdir all keywords|workdir all regex|workdir_all_regex') {
                $arguments.WorkdirAllRegex = $Interpretation.WorkdirAllRegex
            }
            if ($null -ne $Interpretation.Enabled) { $arguments.Enabled = $Interpretation.Enabled }
        }
        "disable" {
            $arguments.RuleName = $Interpretation.RuleName
        }
        "enable" {
            $arguments.RuleName = $Interpretation.RuleName
        }
        "remove" {
            $arguments.RuleName = $Interpretation.RuleName
        }
    }

    return $arguments
}

function ConvertTo-ArgumentPreview {
    param([Parameter(Mandatory = $true)]$Arguments)

    $parts = @("& `"$manageScriptPath`"")
    foreach ($property in $Arguments.GetEnumerator()) {
        $name = $property.Key
        $value = $property.Value
        if ($value -is [System.Array]) {
            $items = @($value | ForEach-Object { "`"$_`"" })
            $parts += "-$name " + ($items -join ", ")
            continue
        }

        if ($value -is [bool]) {
            $parts += ('-{0}:${1}' -f $name, $value.ToString().ToLowerInvariant())
            continue
        }

        $parts += "-$name `"$value`""
    }

    return ($parts -join " ")
}

function Write-InterpretationText {
    param(
        [Parameter(Mandatory = $true)]$Interpretation,
        [Parameter(Mandatory = $true)]$Arguments,
        [switch]$Apply
    )

    Write-Host "Request: $Request"
    Write-Host "InterpretedAction: $($Interpretation.Action)"
    if (-not [string]::IsNullOrWhiteSpace($Interpretation.RuleName)) {
        Write-Host "RuleName: $($Interpretation.RuleName)"
    }
    if (-not [string]::IsNullOrWhiteSpace($Interpretation.Backend)) {
        Write-Host "Backend: $($Interpretation.Backend)"
    }
    if (-not [string]::IsNullOrWhiteSpace($Interpretation.Reason)) {
        Write-Host "Reason: $($Interpretation.Reason)"
    }
    if (-not [string]::IsNullOrWhiteSpace($Interpretation.Prompt)) {
        Write-Host "Prompt: $($Interpretation.Prompt)"
    }
    if ($Interpretation.PromptAnyRegex.Count -gt 0) {
        Write-Host "PromptAnyRegex: $(@($Interpretation.PromptAnyRegex) -join ', ')"
    }
    if ($Interpretation.PromptAllRegex.Count -gt 0) {
        Write-Host "PromptAllRegex: $(@($Interpretation.PromptAllRegex) -join ', ')"
    }
    if ($Interpretation.WorkdirAnyRegex.Count -gt 0) {
        Write-Host "WorkdirAnyRegex: $(@($Interpretation.WorkdirAnyRegex) -join ', ')"
    }
    if ($Interpretation.WorkdirAllRegex.Count -gt 0) {
        Write-Host "WorkdirAllRegex: $(@($Interpretation.WorkdirAllRegex) -join ', ')"
    }
    if ($null -ne $Interpretation.Enabled) {
        Write-Host "Enabled: $($Interpretation.Enabled)"
    }

    Write-Host "Workdir: $Workdir"
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        Write-Host "ConfigPath: $ConfigPath"
    }
    Write-Host "ManageCommand: $(ConvertTo-ArgumentPreview -Arguments $Arguments)"

    if ($Interpretation.Action -in @("add", "update", "disable", "enable", "remove", "init-user-config") -and -not $Apply) {
        Write-Host "ApplyMode: preview only"
        Write-Host "NextStep: re-run with -Apply to persist changes"
    }
    else {
        Write-Host "ApplyMode: execute"
    }

    if ($Interpretation.Action -eq "add") {
        Write-Host "RuleOrderNote: add appends the new rule after existing entries; move it upward in routing.json if you want higher priority"
    }
}

$action = Get-RequestedAction -Text $Request
$interpretation = New-RoutingInterpretation -Text $Request -Action $action
$arguments = Get-ManageScriptArguments -Interpretation $interpretation -Workdir $Workdir -ConfigPath $ConfigPath -Force:$Force

if ($OutputFormat -eq "json") {
    [pscustomobject]@{
        request = $Request
        apply = [bool]$Apply
        workdir = $Workdir
        config_path = $ConfigPath
        interpretation = [pscustomobject]@{
            action = $interpretation.Action
            rule_name = $interpretation.RuleName
            backend = $interpretation.Backend
            reason = $interpretation.Reason
            prompt = $interpretation.Prompt
            prompt_any_regex = @($interpretation.PromptAnyRegex)
            prompt_all_regex = @($interpretation.PromptAllRegex)
            workdir_any_regex = @($interpretation.WorkdirAnyRegex)
            workdir_all_regex = @($interpretation.WorkdirAllRegex)
            enabled = $interpretation.Enabled
        }
        manage_command = (ConvertTo-ArgumentPreview -Arguments $arguments)
    } | ConvertTo-Json -Depth 10
    exit 0
}

Write-InterpretationText -Interpretation $interpretation -Arguments $arguments -Apply:$Apply

$isMutatingAction = $interpretation.Action -in @("add", "update", "disable", "enable", "remove", "init-user-config")
if ($isMutatingAction -and -not $Apply) {
    exit 0
}

& $manageScriptPath @arguments
exit $LASTEXITCODE


