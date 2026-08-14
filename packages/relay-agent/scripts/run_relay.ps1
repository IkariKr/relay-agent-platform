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

# 兼容入口（弃用窗口内）：转调 canonical scripts/relay.ps1 run，不再自行执行。
# Compatibility entrypoint (deprecation window): delegates to canonical
# scripts/relay.ps1 run; this wrapper no longer executes anything itself.
$ErrorActionPreference = "Stop"
Write-Host "relay: DEPRECATED - scripts/run_relay.ps1 is a compatibility wrapper; use scripts/relay.ps1 run (or 'relay run') instead."

$relayScript = Join-Path $PSScriptRoot "relay.ps1"
$relayArgs = @("run", "--backend", $Backend)
if ($Workdir) { $relayArgs += "--workdir"; $relayArgs += $Workdir }
if ($Model) { $relayArgs += "--model"; $relayArgs += $Model }
if ($Agent) { $relayArgs += "--agent"; $relayArgs += $Agent }
if ($LogDir) { $relayArgs += "--log-dir"; $relayArgs += $LogDir }
if ($DryRun) { $relayArgs += "--dry-run" }
foreach ($item in $PassThrough) { $relayArgs += "--passthrough"; $relayArgs += $item }
$relayArgs += "--"
$relayArgs += $Prompt

& $relayScript @relayArgs
exit $LASTEXITCODE
