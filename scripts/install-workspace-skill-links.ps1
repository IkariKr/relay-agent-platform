param(
    [string]$WorkspaceSkillsDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$defaultWorkspaceSkillsDir = Split-Path -Parent $repoRoot
if ([string]::IsNullOrWhiteSpace($WorkspaceSkillsDir)) {
    $WorkspaceSkillsDir = $defaultWorkspaceSkillsDir
}

$links = @(
    @{
        Name = "relay-agent"
        Target = Join-Path $repoRoot "packages\relay-agent"
    },
    @{
        Name = "relay-claude"
        Target = Join-Path $repoRoot "packages\relay-claude"
    },
    @{
        Name = "relay-opencode"
        Target = Join-Path $repoRoot "packages\relay-opencode"
    },
    @{
        Name = "relay-antigravity"
        Target = Join-Path $repoRoot "packages\relay-antigravity"
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
