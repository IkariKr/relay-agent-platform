param(
    [string]$WorkspaceSkillsDir = "D:\App\01_Ai\CodeX\skills"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$links = @(
    @{
        Name = "codex-delegate-opencode"
        Target = Join-Path $repoRoot "packages\codex-delegate-opencode"
    }
)

foreach ($link in $links) {
    $destination = Join-Path $WorkspaceSkillsDir $link.Name
    if (Test-Path -LiteralPath $destination) {
        Write-Host "Exists: $destination"
        continue
    }

    New-Item -ItemType Junction -Path $destination -Target $link.Target | Out-Null
    Write-Host "Created junction: $destination -> $($link.Target)"
}
