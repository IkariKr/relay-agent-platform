param(
    [string]$ForkUrl = "",
    [string]$UpstreamName = "upstream",
    [string]$OriginName = "origin"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

Push-Location -LiteralPath $repoRoot
try {
    $remotes = @{}
    foreach ($remote in (git remote)) {
        $fetchUrl = git remote get-url $remote
        $remotes[$remote] = $fetchUrl.Trim()
    }

    Write-Host "Current remotes:"
    if ($remotes.Count -eq 0) {
        Write-Host "  (none)"
    }
    else {
        foreach ($entry in $remotes.GetEnumerator() | Sort-Object Name) {
            Write-Host "  $($entry.Key): $($entry.Value)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ForkUrl)) {
        Write-Host ""
        Write-Host "No ForkUrl provided. To connect your fork later:"
        Write-Host "  .\scripts\connect-fork.ps1 -ForkUrl https://github.com/<you>/relay-agent-platform.git"
        exit 0
    }

    $currentOriginUrl = $null
    if ($remotes.ContainsKey($OriginName)) {
        $currentOriginUrl = $remotes[$OriginName]
    }

    if ($currentOriginUrl -and -not $remotes.ContainsKey($UpstreamName)) {
        git remote rename $OriginName $UpstreamName
        Write-Host "Renamed $OriginName -> $UpstreamName"
        $remotes.Remove($OriginName)
        $remotes[$UpstreamName] = $currentOriginUrl
    }
    elseif ($currentOriginUrl -and $remotes.ContainsKey($UpstreamName) -and $currentOriginUrl -ne $ForkUrl) {
        git remote set-url $UpstreamName $currentOriginUrl
        git remote remove $OriginName
        Write-Host "Moved existing $OriginName URL onto $UpstreamName and cleared $OriginName"
    }

    if ((git remote) -contains $OriginName) {
        git remote set-url $OriginName $ForkUrl
        Write-Host "Updated $OriginName -> $ForkUrl"
    }
    else {
        git remote add $OriginName $ForkUrl
        Write-Host "Added $OriginName -> $ForkUrl"
    }

    Write-Host ""
    Write-Host "Updated remotes:"
    git remote -v
}
finally {
    Pop-Location
}
