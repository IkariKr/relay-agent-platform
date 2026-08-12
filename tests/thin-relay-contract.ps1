$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $repoRoot "shared\scripts\ThinRelay.psm1") -Force

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message Expected='$Expected' Actual='$Actual'" }
}

function Assert-Sequence {
    param([string[]]$Actual, [string[]]$Expected, [string]$Message)
    if ($Actual.Count -ne $Expected.Count) { throw "$Message Expected count=$($Expected.Count) Actual count=$($Actual.Count)" }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Equal -Actual $Actual[$index] -Expected $Expected[$index] -Message "$Message at index $index"
    }
}

$workdir = $repoRoot.Path
$passThrough = @("--model", "native-model", "--flag", "value")

$opencode = New-ThinRelayInvocation -Backend opencode -Prompt "prompt" -Workdir $workdir -Model "chosen-model" -Agent "chosen-agent" -PassThrough $passThrough
Assert-Equal $opencode.Command "opencode" "OpenCode command"
Assert-Sequence $opencode.Arguments @("run", "--dir", $workdir, "--model", "chosen-model", "--agent", "chosen-agent", "--model", "native-model", "--flag", "value", "--", "prompt") "OpenCode arguments"

$claude = New-ThinRelayInvocation -Backend claude -Prompt "prompt" -Workdir $workdir -Model "chosen-model" -Agent "chosen-agent" -PassThrough $passThrough
Assert-Equal $claude.Command "claude" "Claude command"
Assert-Sequence $claude.Arguments @("--print", "--model", "chosen-model", "--agent", "chosen-agent", "--model", "native-model", "--flag", "value", "prompt") "Claude arguments"

$antigravity = New-ThinRelayInvocation -Backend antigravity -Prompt "prompt" -Workdir $workdir -Model "chosen-model" -Agent "chosen-agent" -PassThrough $passThrough
Assert-Equal $antigravity.Command "agy" "Antigravity command"
Assert-Sequence $antigravity.Arguments @("--model", "chosen-model", "--agent", "chosen-agent", "--model", "native-model", "--flag", "value", "--add-dir", $workdir, "--print", "prompt") "Antigravity arguments"

& (Join-Path $repoRoot "scripts\run_relay.ps1") -Backend opencode -Prompt "dry run" -Workdir $workdir -Model "chosen-model" -Agent "chosen-agent" -PassThrough "--model", "native-model" -DryRun
if ($LASTEXITCODE -ne 0) { throw "Dry run must succeed without validating the native CLI." }

$configDir = Join-Path $workdir ".relay-agent\backends"
$configPath = Join-Path $configDir "opencode.json"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
Set-Content -LiteralPath $configPath -Value '{"default_model":"configured-model","default_agent":"configured-agent","default_passthrough":["--auto"]}'
try {
    $defaults = Get-ThinRelayDefaultConfig -Backend opencode -Workdir $workdir
    Assert-Equal ([string]$defaults.Values.default_model) "configured-model" "Workspace default model"
    & (Join-Path $repoRoot "scripts\run_relay.ps1") -Backend opencode -Prompt "dry run" -Workdir $workdir -Model "explicit-model" -Agent "explicit-agent" -PassThrough "--format", "json" -DryRun
    if ($LASTEXITCODE -ne 0) { throw "Explicit command-line values must win over workspace defaults." }
}
finally {
    Remove-Item -LiteralPath $configPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $configDir -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Split-Path -Parent $configDir) -Force -ErrorAction SilentlyContinue
}

foreach ($path in @(
    (Join-Path $repoRoot "backends\agent\run_delegate_agent.ps1"),
    (Join-Path $repoRoot "backends\opencode\run_opencode_delegate.ps1"),
    (Join-Path $repoRoot "scripts\run_claude_delegate.ps1"),
    (Join-Path $repoRoot "backends\antigravity\run_antigravity_delegate.ps1")
)) {
    $source = Get-Content -Raw -LiteralPath $path
    foreach ($forbidden in @("Invoke-DelegateAttempt", "Write-DelegatePostRunStatus", "Write-DelegateLogs", "Start-Sleep", "TimeoutSeconds", "IdleTimeoutSeconds", "MaxTurns")) {
        if ($source -match $forbidden) { throw "Thin runner '$path' contains forbidden v1 behavior '$forbidden'." }
    }
}

Write-Host "Thin Relay contract tests passed."
