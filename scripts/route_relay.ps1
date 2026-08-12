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

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Import-Module (Join-Path $repoRoot "backends\agent\AutoRoutingCommon.psm1") -Force
Import-Module (Join-Path $repoRoot "shared\scripts\ThinRelay.psm1") -Force

$resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir).Path
$config = Load-AutoRoutingConfig -AutoConfigPath $AutoConfigPath -PackageRoot $repoRoot.Path -Workdir $resolvedWorkdir
$resolution = Resolve-AutoConfiguredBackend -RoutingConfig $config -Prompt $Prompt -Workdir $resolvedWorkdir -BackendAvailability (Get-RoutingBackendAvailabilityMap)
$invocation = New-ThinRelayInvocation -Backend $resolution.Backend -Prompt $Prompt -Workdir $resolvedWorkdir -Model $Model -Agent $Agent -PassThrough $PassThrough

Write-Host "routing config: $($resolution.ConfigPath)"
Write-Host "selected backend: $($resolution.Backend)"
Write-Host "routing reason: $($resolution.Reason)"
if (-not [string]::IsNullOrWhiteSpace($resolution.Rule)) { Write-Host "routing rule: $($resolution.Rule)" }
Write-Host "native command: $($invocation.DisplayCommand)"

if ($Action -eq "run") {
    Invoke-ThinRelay -Backend $resolution.Backend -Prompt $Prompt -Workdir $resolvedWorkdir -Model $Model -Agent $Agent -PassThrough $PassThrough -LogDir $LogDir
    exit (Get-ThinRelayLastExitCode)
}
