param(
    [Parameter(Mandatory = $true)][ValidateSet("explain", "run")][string]$Action,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Workdir = (Get-Location).Path,
    [string]$Model = "",
    [string]$Agent = "",
    [AllowEmptyCollection()][string[]]$PassThrough = @(),
    [string]$AutoConfigPath = "",
    [string]$LogDir = ""
)

# 兼容入口：转调 canonical scripts/relay.ps1 route；本脚本不再自行实现路由逻辑。
# Compatibility entrypoint: delegates to canonical scripts/relay.ps1 route;
# it no longer implements routing logic itself.
$ErrorActionPreference = "Stop"
Write-Host "relay: DEPRECATED - scripts/route_relay.ps1 is a compatibility wrapper; use scripts/relay.ps1 route (or 'relay route') instead."

$relayScript = Join-Path $PSScriptRoot "relay.ps1"

$relayArgs = @("route", $Action)
if ($Workdir) { $relayArgs += "--workdir"; $relayArgs += $Workdir }
if ($Model) { $relayArgs += "--model"; $relayArgs += $Model }
if ($Agent) { $relayArgs += "--agent"; $relayArgs += $Agent }
if ($AutoConfigPath) { $relayArgs += "--auto-config-path"; $relayArgs += $AutoConfigPath }
if ($LogDir) { $relayArgs += "--log-dir"; $relayArgs += $LogDir }
foreach ($item in $PassThrough) { $relayArgs += "--passthrough"; $relayArgs += $item }
$relayArgs += "--"
$relayArgs += $Prompt

& $relayScript @relayArgs
exit $LASTEXITCODE
