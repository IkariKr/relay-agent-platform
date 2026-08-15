Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Worker Profile Store：provider profile 的 CRUD 与 ownership（onboarding plan §4）。
# pack（仓库定义）与 profile（用户实例）分离；profile 只保存 Base URL / Model ID 与
# credential source 引用，绝不保存 secret 值。所有写路径都经过 schema/字段校验。
# Provider profile CRUD and ownership. Pack (repo-defined) and profile (user
# instance) are separate; a profile stores Base URL / Model ID plus a credential
# source reference, never a secret value. Every write path validates the schema.
Import-Module (Join-Path $PSScriptRoot "..\hosts\codex\CodexHostAdapter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\credentials\CredentialStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "WorkerRegistry.psm1") -Force

$script:ForbiddenSecretFieldNames = @(
    "api_key", "apiKey", "secret", "secret_value", "secretValue",
    "credential_value", "credentialValue", "credential"
)

function Get-ProfileStoreRoot {
    # <CODEX_HOME>/relay/native-providers/profiles
    param([string]$CodexHome = "")
    if ([string]::IsNullOrWhiteSpace($CodexHome)) { $CodexHome = Get-CodexHome }
    return (Join-Path $CodexHome "relay\native-providers\profiles")
}

function Get-ProfileFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    if ($ProfileId -notmatch "^[a-z0-9][a-z0-9-]*$") { throw "invalid profile id: $ProfileId" }
    return (Join-Path (Get-ProfileStoreRoot -CodexHome $CodexHome) "$ProfileId.json")
}

function Assert-ProfileSchema {
    # 结构校验：required 字段、pattern、wire_api、禁止 secret 字段。
    # Structural validation: required fields, patterns, wire_api, forbidden secret fields.
    param([Parameter(Mandatory = $true)]$Profile)

    if ($Profile -is [System.Collections.IDictionary]) {
        $Profile = [pscustomobject]$Profile
    }

    $required = @(
        "schema_version", "profile_id", "worker_id", "provider_id", "base_url",
        "model_id", "wire_api", "credential_source", "managed_by", "created_at", "updated_at"
    )
    foreach ($key in $required) {
        if ($Profile.PSObject.Properties.Name -notcontains $key) {
            throw "provider profile validation failed: missing field '$key'"
        }
        if ([string]::IsNullOrWhiteSpace([string]$Profile.$key)) {
            throw "provider profile validation failed: empty field '$key'"
        }
    }
    foreach ($forbidden in $script:ForbiddenSecretFieldNames) {
        if ($Profile.PSObject.Properties.Name -contains $forbidden) {
            throw "provider profile validation failed: forbidden secret field '$forbidden'"
        }
    }
    if ([string]$Profile.schema_version -ne "1.0") { throw "provider profile validation failed: unsupported schema_version" }
    if ([string]$Profile.wire_api -ne "responses") { throw "provider profile validation failed: wire_api must be 'responses'" }
    if ([string]$Profile.profile_id -notmatch "^[a-z0-9][a-z0-9-]*$") { throw "provider profile validation failed: invalid profile_id" }
    if ([string]$Profile.worker_id -notmatch "^[a-z0-9][a-z0-9-]*$") { throw "provider profile validation failed: invalid worker_id" }
    if ([string]$Profile.provider_id -notmatch "^[A-Za-z0-9][A-Za-z0-9_-]*$") { throw "provider profile validation failed: invalid provider_id" }
    $baseUrl = [string]$Profile.base_url
    $baseUri = $null
    if (-not [Uri]::TryCreate($baseUrl, [UriKind]::Absolute, [ref]$baseUri) -or $baseUri.Scheme -notin @("http", "https") -or $baseUrl -match '[\r\n"]') {
        throw "provider profile validation failed: invalid base_url"
    }
    if ([string]$Profile.model_id -match '[\r\n"]') { throw "provider profile validation failed: invalid model_id" }
    if ([string]$Profile.credential_source -notmatch "^env:[A-Za-z_][A-Za-z0-9_]*$") { throw "provider profile validation failed: invalid credential_source" }
    if ([string]$Profile.managed_by -ne "relay-agent") { throw "provider profile validation failed: managed_by must be 'relay-agent'" }
    return $true
}

function New-ProviderProfile {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ModelId,
        [string]$ProviderId = "",
        [string]$WireApi = "responses",
        [string]$CredentialSource = "",
        [string]$CodexHome = ""
    )
    if ($ProfileId -notmatch "^[a-z0-9][a-z0-9-]*$") { throw "invalid profile id: $ProfileId" }

    $path = Get-ProfileFilePath -ProfileId $ProfileId -CodexHome $CodexHome
    if (Test-Path -LiteralPath $path) { throw "provider profile conflict: profile '$ProfileId' already exists (fail closed)" }

    if ([string]::IsNullOrWhiteSpace($ProviderId)) {
        $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId
        $ProviderId = [string]$descriptor.provider.provider_id
    }
    if ([string]::IsNullOrWhiteSpace($CredentialSource)) {
        $CredentialSource = "env:" + (New-StableCredentialEnvName -ProfileId $ProfileId)
    }

    $now = (Get-Date).ToUniversalTime().ToString("o")
    $profile = [pscustomobject]@{
        schema_version     = "1.0"
        profile_id         = $ProfileId
        worker_id          = $WorkerId
        provider_id        = $ProviderId
        base_url           = $BaseUrl
        model_id           = $ModelId
        wire_api           = $WireApi
        credential_source  = $CredentialSource
        managed_by         = "relay-agent"
        created_at         = $now
        updated_at         = $now
    }
    $null = Assert-ProfileSchema -Profile $profile

    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $profile | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $path -Encoding utf8
    return (Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome)
}

function Get-ProviderProfile {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $path = Get-ProfileFilePath -ProfileId $ProfileId -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $path)) { throw "provider profile not found: $ProfileId" }
    $profile = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    $null = Assert-ProfileSchema -Profile $profile
    return $profile
}

function Get-ProviderProfiles {
    param(
        [string]$WorkerId = "",
        [string]$CodexHome = ""
    )
    $root = Get-ProfileStoreRoot -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $profiles = @()
    foreach ($file in (Get-ChildItem -LiteralPath $root -Filter "*.json" -File)) {
        $profile = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
        try { $null = Assert-ProfileSchema -Profile $profile } catch { continue }
        if ([string]::IsNullOrWhiteSpace($WorkerId) -or [string]$profile.worker_id -eq $WorkerId) {
            $profiles += $profile
        }
    }
    return $profiles
}

function Update-ProviderProfile {
    # 只更新非 secret 配置；credential_source 保持不变（换 key 走 credential 命令）。
    # Updates non-secret fields only; credential_source is preserved (key rotation
    # goes through the credential command).
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$BaseUrl = "",
        [string]$ModelId = "",
        [string]$ProviderId = "",
        [string]$CodexHome = ""
    )
    $profile = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome
    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) { $profile.base_url = $BaseUrl }
    if (-not [string]::IsNullOrWhiteSpace($ModelId)) { $profile.model_id = $ModelId }
    if (-not [string]::IsNullOrWhiteSpace($ProviderId)) { $profile.provider_id = $ProviderId }
    $profile.updated_at = (Get-Date).ToUniversalTime().ToString("o")
    $null = Assert-ProfileSchema -Profile $profile

    $path = Get-ProfileFilePath -ProfileId $ProfileId -CodexHome $CodexHome
    $profile | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $path -Encoding utf8
    return (Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome)
}

function Remove-ProviderProfile {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $path = Get-ProfileFilePath -ProfileId $ProfileId -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $path)) { throw "provider profile not found: $ProfileId" }
    Remove-Item -LiteralPath $path -Force
    return [pscustomobject]@{ profile_id = $ProfileId; removed = $true }
}

Export-ModuleMember -Function Get-ProfileStoreRoot, Get-ProfileFilePath, Assert-ProfileSchema, New-ProviderProfile, Get-ProviderProfile, Get-ProviderProfiles, Update-ProviderProfile, Remove-ProviderProfile
