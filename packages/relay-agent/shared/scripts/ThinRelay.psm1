Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ThinRelayLastExitCode = 0

function Get-ThinRelayCommand {
    param([Parameter(Mandatory = $true)][string]$Backend)

    switch ($Backend) {
        "opencode" { return "opencode" }
        "claude" { return "claude" }
        "antigravity" { return "agy" }
        default { throw "Unsupported backend '$Backend'. Supported backends: opencode, claude, antigravity." }
    }
}

function Resolve-ThinRelayCommand {
    param([Parameter(Mandatory = $true)][string]$Backend)

    $commandName = Get-ThinRelayCommand -Backend $Backend
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Relay error: backend '$Backend' requires '$commandName' on PATH. Install the native CLI, ensure '$commandName' is available on PATH, then retry scripts/run_relay.ps1. The planned 'relay doctor' command is not available yet."
    }

    return $command.Source
}

function ConvertTo-ThinRelayDisplayArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '(?i)(api[_-]?key|token|secret|password)=') {
        return "<redacted>"
    }
    if ($Value -match '[\s"'']') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Get-ThinRelayDefaultConfig {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("opencode", "claude", "antigravity")][string]$Backend,
        [Parameter(Mandatory = $true)][string]$Workdir
    )

    $paths = @(
        (Join-Path $env:USERPROFILE ".codex\relay\backends\$Backend.json"),
        (Join-Path $Workdir ".relay-agent\backends\$Backend.json")
    )
    $config = [ordered]@{}
    $source = "native default"
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $input = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        foreach ($property in $input.PSObject.Properties) { $config[$property.Name] = $property.Value }
        $source = (Resolve-Path -LiteralPath $path).Path
    }

    return [pscustomobject]@{ Values = $config; Source = $source }
}

function New-ThinRelayInvocation {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("opencode", "claude", "antigravity")][string]$Backend,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Workdir,
        [string]$Model = "",
        [string]$Agent = "",
        [AllowEmptyCollection()][string[]]$PassThrough = @()
    )

    $command = Get-ThinRelayCommand -Backend $Backend
    $arguments = New-Object System.Collections.Generic.List[string]

    switch ($Backend) {
        "opencode" {
            $arguments.Add("run")
            $arguments.Add("--dir")
            $arguments.Add($Workdir)
            if (-not [string]::IsNullOrWhiteSpace($Model)) { $arguments.Add("--model"); $arguments.Add($Model) }
            if (-not [string]::IsNullOrWhiteSpace($Agent)) { $arguments.Add("--agent"); $arguments.Add($Agent) }
            foreach ($item in $PassThrough) { $arguments.Add($item) }
            $arguments.Add("--")
            $arguments.Add($Prompt)
        }
        "claude" {
            $arguments.Add("--print")
            if (-not [string]::IsNullOrWhiteSpace($Model)) { $arguments.Add("--model"); $arguments.Add($Model) }
            if (-not [string]::IsNullOrWhiteSpace($Agent)) { $arguments.Add("--agent"); $arguments.Add($Agent) }
            foreach ($item in $PassThrough) { $arguments.Add($item) }
            $arguments.Add($Prompt)
        }
        "antigravity" {
            if (-not [string]::IsNullOrWhiteSpace($Model)) { $arguments.Add("--model"); $arguments.Add($Model) }
            if (-not [string]::IsNullOrWhiteSpace($Agent)) { $arguments.Add("--agent"); $arguments.Add($Agent) }
            foreach ($item in $PassThrough) { $arguments.Add($item) }
            $arguments.Add("--add-dir")
            $arguments.Add($Workdir)
            $arguments.Add("--print")
            $arguments.Add($Prompt)
        }
    }

    return [pscustomobject]@{
        Backend = $Backend
        Command = $command
        Arguments = @($arguments)
        DisplayCommand = ((@($command) + @($arguments | ForEach-Object { ConvertTo-ThinRelayDisplayArgument -Value $_ })) -join " ")
    }
}

function Invoke-ThinRelay {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("opencode", "claude", "antigravity")][string]$Backend,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Workdir = (Get-Location).Path,
        [string]$Model = "",
        [string]$Agent = "",
        [AllowEmptyCollection()][string[]]$PassThrough = @(),
        [string]$LogDir = "",
        [switch]$DryRun
    )

    $resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
    $defaults = Get-ThinRelayDefaultConfig -Backend $Backend -Workdir $resolvedWorkdir
    $effectiveModel = if (-not [string]::IsNullOrWhiteSpace($Model)) { $Model } elseif ($defaults.Values.Contains("default_model")) { [string]$defaults.Values.default_model } else { "" }
    $effectiveAgent = if (-not [string]::IsNullOrWhiteSpace($Agent)) { $Agent } elseif ($defaults.Values.Contains("default_agent")) { [string]$defaults.Values.default_agent } else { "" }
    $effectivePassThrough = @($PassThrough)
    if ($effectivePassThrough.Count -eq 0 -and $defaults.Values.Contains("default_passthrough")) {
        $effectivePassThrough = @($defaults.Values.default_passthrough | ForEach-Object { [string]$_ })
    }
    $modelSource = if (-not [string]::IsNullOrWhiteSpace($Model)) { "command line" } elseif (-not [string]::IsNullOrWhiteSpace($effectiveModel)) { $defaults.Source } else { "native default" }
    $agentSource = if (-not [string]::IsNullOrWhiteSpace($Agent)) { "command line" } elseif (-not [string]::IsNullOrWhiteSpace($effectiveAgent)) { $defaults.Source } else { "native default" }
    $invocation = New-ThinRelayInvocation -Backend $Backend -Prompt $Prompt -Workdir $resolvedWorkdir -Model $effectiveModel -Agent $effectiveAgent -PassThrough $effectivePassThrough

    Write-Host "backend: $Backend (command line)"
    Write-Host "model: $(if ([string]::IsNullOrWhiteSpace($effectiveModel)) { 'native default' } else { "$effectiveModel ($modelSource)" })"
    Write-Host "agent: $(if ([string]::IsNullOrWhiteSpace($effectiveAgent)) { 'native default' } else { "$effectiveAgent ($agentSource)" })"
    Write-Host "native command: $($invocation.DisplayCommand)"

    if ($DryRun) {
        $script:ThinRelayLastExitCode = 0
        return
    }

    $invocation.Command = Resolve-ThinRelayCommand -Backend $Backend

    if ([string]::IsNullOrWhiteSpace($LogDir)) {
        $nativeArguments = @($invocation.Arguments)
        & $invocation.Command @nativeArguments
        $script:ThinRelayLastExitCode = $LASTEXITCODE
        return
    }

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stdoutPath = Join-Path $LogDir "$Backend-$stamp.stdout.log"
    $stderrPath = Join-Path $LogDir "$Backend-$stamp.stderr.log"
    $process = Start-Process -FilePath $invocation.Command -ArgumentList @($invocation.Arguments) -WorkingDirectory $resolvedWorkdir -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    Get-Content -LiteralPath $stdoutPath | Write-Output
    Get-Content -LiteralPath $stderrPath | Write-Error
    Write-Host "stdout log: $stdoutPath"
    Write-Host "stderr log: $stderrPath"
    $script:ThinRelayLastExitCode = $process.ExitCode
}

function Get-ThinRelayLastExitCode {
    return $script:ThinRelayLastExitCode
}

Export-ModuleMember -Function Get-ThinRelayCommand, Resolve-ThinRelayCommand, Get-ThinRelayDefaultConfig, New-ThinRelayInvocation, Invoke-ThinRelay, Get-ThinRelayLastExitCode
