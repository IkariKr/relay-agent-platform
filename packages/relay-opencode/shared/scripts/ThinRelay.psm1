Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ThinRelayLastExitCode = 0

# 展示/落盘命令时视为 secret 值的标志名；后随的单个 token 一并脱敏。
# Secret value flags; the single following token is redacted together with the flag.
$script:ThinRelaySecretValueFlags = @(
    "--api-key", "--api_key", "--apikey",
    "--token", "--access-token",
    "--secret", "--client-secret",
    "--password", "--passwd"
)

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

    if ($Value -match '[\s"'']') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function ConvertTo-ThinRelayDisplayCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    # token-aware 脱敏：secret 值标志连后随值一起脱敏；内联 key=value 保留键名只脱敏值；
    # Authorization/Bearer 形态整体脱敏。不得只识别 key=value 形式。
    # Token-aware redaction: secret value flags redact the following value; inline
    # key=value keeps the key and redacts the value; Authorization/Bearer forms are
    # redacted wholesale. Must not only recognize key=value form.
    $tokens = New-Object System.Collections.Generic.List[string]
    $tokens.Add($Command)
    $redactNext = $false
    foreach ($arg in $Arguments) {
        if ($redactNext) {
            $tokens.Add("<redacted>")
            $redactNext = $false
            continue
        }
        if ($script:ThinRelaySecretValueFlags -contains $arg) {
            $tokens.Add($arg)
            $redactNext = $true
            continue
        }
        if ($arg -match '(?i)(api[_-]?key|token|secret|password)=(.+)$') {
            $tokens.Add(($arg -replace '(?i)^(.+(?:api[_-]?key|token|secret|password)=).+$', '${1}<redacted>'))
            continue
        }
        if ($arg -match '(?i)^(authorization|proxy-authorization)(\s*[:=]|$)' -or $arg -match '(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+') {
            $tokens.Add("<redacted>")
            continue
        }
        $tokens.Add((ConvertTo-ThinRelayDisplayArgument -Value $arg))
    }
    if ($redactNext) { $tokens.Add("<redacted>") }

    return ($tokens -join " ")
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
        DisplayCommand = (ConvertTo-ThinRelayDisplayCommand -Command $command -Arguments @($arguments))
    }
}

function Get-ThinRelayStreamReader {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Start-Process 创建重定向文件与返回之间可能有极小竞态，短暂重试。
    # There can be a tiny race between Start-Process creating the redirect file and
    # this reader opening it; retry briefly.
    $deadline = (Get-Date).AddSeconds(5)
    while ($true) {
        try {
            $file = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            return [System.IO.StreamReader]::new($file, [System.Text.Encoding]::UTF8, $true, 4096)
        }
        catch [System.IO.FileNotFoundException] {
            if ((Get-Date) -gt $deadline) { throw }
            Start-Sleep -Milliseconds 50
        }
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
    $commandPath = Join-Path $LogDir "$Backend-$stamp.command.txt"
    [System.IO.File]::WriteAllText($commandPath, $invocation.DisplayCommand + "`n")

    # 边运行边增量读取重定向文件，实时转发；禁止等进程结束后再回放。
    # Incrementally read the redirected files while the child runs; never replay after exit.
    $process = Start-Process -FilePath $invocation.Command -ArgumentList @($invocation.Arguments) -WorkingDirectory $resolvedWorkdir -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $stdoutReader = $null
    $stderrReader = $null
    try {
        $stdoutReader = Get-ThinRelayStreamReader -Path $stdoutPath
        $stderrReader = Get-ThinRelayStreamReader -Path $stderrPath
        while (-not $process.HasExited) {
            while ($null -ne ($line = $stdoutReader.ReadLine())) { Write-Output $line }
            while ($null -ne ($line = $stderrReader.ReadLine())) { [Console]::Error.WriteLine($line) }
            Start-Sleep -Milliseconds 50
        }
        while ($null -ne ($line = $stdoutReader.ReadLine())) { Write-Output $line }
        while ($null -ne ($line = $stderrReader.ReadLine())) { [Console]::Error.WriteLine($line) }
    }
    finally {
        if ($null -ne $stdoutReader) { $stdoutReader.Dispose() }
        if ($null -ne $stderrReader) { $stderrReader.Dispose() }
    }
    Write-Host "stdout log: $stdoutPath"
    Write-Host "stderr log: $stderrPath"
    Write-Host "command log: $commandPath"
    $script:ThinRelayLastExitCode = $process.ExitCode
}

function Get-ThinRelayLastExitCode {
    return $script:ThinRelayLastExitCode
}

Export-ModuleMember -Function Get-ThinRelayCommand, Resolve-ThinRelayCommand, Get-ThinRelayDefaultConfig, New-ThinRelayInvocation, Invoke-ThinRelay, Get-ThinRelayLastExitCode
