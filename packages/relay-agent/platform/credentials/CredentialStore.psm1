Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Credential store 接口：所有 secret 通过 credential_source 引用（首批 `env:<NAME>`），
# 上层从不接触值本身。set/status/remove 的输出只含 source 与 presence，不含值。
# Credential store contract: secrets are referenced by credential_source (first
# backend `env:<NAME>`); callers never touch the value. Outputs carry only the
# source name and presence, never the value.
Import-Module (Join-Path $PSScriptRoot "EnvCredentialStore.psm1") -Force

function New-StableCredentialEnvName {
    # 由 profile id 生成稳定 env 名：RELAY_PROVIDER_<PROFILE_ID>_API_KEY。
    # Stable env name derived from the profile id.
    param([Parameter(Mandatory = $true)][string]$ProfileId)
    if ($ProfileId -notmatch "^[a-z0-9][a-z0-9-]*$") { throw "invalid profile id for credential env name: $ProfileId" }
    $sanitized = ($ProfileId -replace "-", "_").ToUpperInvariant()
    return "RELAY_PROVIDER_${sanitized}_API_KEY"
}

function Resolve-CredentialBackend {
    # 从 source 前缀解析 backend；目前唯一 backend 是 env:。返回 backend 键。
    param([Parameter(Mandatory = $true)][string]$Source)
    if ($Source -match "^env:([A-Za-z_][A-Za-z0-9_]*)$") { return "env" }
    throw "unsupported credential source: $Source"
}

function Set-Credential {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Scope = "User"
    )
    $backend = Resolve-CredentialBackend -Source $Source
    if ($backend -ne "env") { throw "unsupported credential source: $Source" }
    $envName = $Source.Substring(4)
    Set-EnvCredential -EnvName $envName -Value $Value -Scope $Scope
    return [pscustomobject]@{ source = $Source; present = $true }
}

function Test-CredentialPresence {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$Scope = "User"
    )
    $backend = Resolve-CredentialBackend -Source $Source
    if ($backend -ne "env") { throw "unsupported credential source: $Source" }
    $envName = $Source.Substring(4)
    $present = Test-EnvCredentialPresence -EnvName $envName -Scope $Scope
    return [pscustomobject]@{
        source = $Source
        present = $present
        detail = "env:$envName presence checked (value never read)"
    }
}

function Remove-Credential {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$Scope = "User"
    )
    $backend = Resolve-CredentialBackend -Source $Source
    if ($backend -ne "env") { throw "unsupported credential source: $Source" }
    $envName = $Source.Substring(4)
    Remove-EnvCredential -EnvName $envName -Scope $Scope
    return [pscustomobject]@{ source = $Source; present = $false }
}

function Read-SecretFromStdin {
    # 非交互 secret 输入：从 stdin 读一行，trim 后返回。本函数不向任何流输出值；
    # 调用方不得把返回值写入命令历史、日志或 JSON 输出。
    # Non-interactive secret input: reads one line from stdin and trims it.
    # This function never prints the value; callers must keep it out of
    # history, logs and JSON output.
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { return "" }
    return $line.TrimEnd("`r", "`n").Trim()
}

function Test-SecretPresentInText {
    # secret leakage 断言辅助：doctor/测试用，检查文本是否包含 secret 值。
    # Leakage assertion helper for doctor and tests.
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Secret
    )
    if ([string]::IsNullOrEmpty($Secret)) { return $false }
    return $Text.Contains($Secret)
}

Export-ModuleMember -Function New-StableCredentialEnvName, Resolve-CredentialBackend, Set-Credential, Test-CredentialPresence, Remove-Credential, Read-SecretFromStdin, Test-SecretPresentInText, Test-EnvName, Set-EnvCredential, Test-EnvCredentialPresence, Remove-EnvCredential
