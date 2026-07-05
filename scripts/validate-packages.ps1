Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$requiredFiles = @(
    "shared\scripts\DelegateCommon.psm1",
    "scripts\run_claude_delegate.ps1",
    "packages\codex-delegate-opencode\scripts\run_opencode_delegate.ps1",
    "packages\codex-delegate-opencode\shared\scripts\DelegateCommon.psm1",
    "SKILL.md",
    "agents\openai.yaml",
    "packages\codex-delegate-opencode\SKILL.md",
    "packages\codex-delegate-opencode\agents\openai.yaml"
)

$missing = @()
foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $missing += $relativePath
    }
}

if ($missing.Count -gt 0) {
    Write-Error "Missing required files:`n$($missing -join "`n")"
}

$rootModule = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "shared\scripts\DelegateCommon.psm1")
$packageModule = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "packages\codex-delegate-opencode\shared\scripts\DelegateCommon.psm1")
if ($rootModule -ne $packageModule) {
    Write-Error "Shared module copy is out of sync. Run scripts/build-packages.ps1."
}

Write-Host "Package validation passed."
