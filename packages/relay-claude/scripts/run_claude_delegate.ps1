param(
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
Invoke-ThinRelay -Backend claude -Prompt $Prompt -Workdir $Workdir -Model $Model -Agent $Agent -PassThrough $PassThrough -LogDir $LogDir -DryRun:$DryRun
exit (Get-ThinRelayLastExitCode)
