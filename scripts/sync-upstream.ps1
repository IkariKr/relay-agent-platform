param(
    [string]$UpstreamName = "upstream",
    [string]$UpstreamUrl = "",
    [string]$Branch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Push-Location -LiteralPath $repoRoot
try {
    $remoteNames = @(git remote)
    if ($remoteNames -notcontains $UpstreamName) {
        if ([string]::IsNullOrWhiteSpace($UpstreamUrl)) {
            throw "Remote '$UpstreamName' is missing. Pass -UpstreamUrl to add it."
        }

        git remote add $UpstreamName $UpstreamUrl
        Write-Host "Added remote '$UpstreamName' -> $UpstreamUrl"
    }

    git fetch $UpstreamName $Branch
    Write-Host "Fetched $UpstreamName/$Branch"
}
finally {
    Pop-Location
}
