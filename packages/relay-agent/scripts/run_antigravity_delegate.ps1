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
$coreCandidates = @((Join-Path $PSScriptRoot "..\shared\scripts\ThinRelay.psm1"), (Join-Path $PSScriptRoot "..\..\shared\scripts\ThinRelay.psm1"))
$core = @($coreCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
if ($core.Count -eq 0) { throw "Unable to locate ThinRelay.psm1." }
Import-Module $core -Force
Invoke-ThinRelay -Backend antigravity -Prompt $Prompt -Workdir $Workdir -Model $Model -Agent $Agent -PassThrough $PassThrough -LogDir $LogDir -DryRun:$DryRun
exit (Get-ThinRelayLastExitCode)
