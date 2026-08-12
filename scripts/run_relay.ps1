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

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "..\shared\scripts\ThinRelay.psm1") -Force
Invoke-ThinRelay @PSBoundParameters
exit (Get-ThinRelayLastExitCode)
