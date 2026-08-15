Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Env credential backend：secret 只以环境变量形式存在，value 永不写入文件或输出。
# Env credential backend: secrets live only as environment variables; the value is
# never written to files or printed. Default scope is User (persistent); tests use
# Process scope so the runner never pollutes the user environment.
function Test-EnvName {
    param([Parameter(Mandatory = $true)][string]$EnvName)
    return ($EnvName -match "^[A-Za-z_][A-Za-z0-9_]*$")
}

function Set-EnvCredential {
    param(
        [Parameter(Mandatory = $true)][string]$EnvName,
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$Scope = "User"
    )
    if (-not (Test-EnvName -EnvName $EnvName)) { throw "invalid credential env name: $EnvName" }
    [Environment]::SetEnvironmentVariable($EnvName, $Value, $Scope)
}

function Test-EnvCredentialPresence {
    param(
        [Parameter(Mandatory = $true)][string]$EnvName,
        [string]$Scope = "User"
    )
    if (-not (Test-EnvName -EnvName $EnvName)) { throw "invalid credential env name: $EnvName" }
    $value = [Environment]::GetEnvironmentVariable($EnvName, $Scope)
    return (-not [string]::IsNullOrWhiteSpace($value))
}

function Remove-EnvCredential {
    param(
        [Parameter(Mandatory = $true)][string]$EnvName,
        [string]$Scope = "User"
    )
    if (-not (Test-EnvName -EnvName $EnvName)) { throw "invalid credential env name: $EnvName" }
    [Environment]::SetEnvironmentVariable($EnvName, $null, $Scope)
}

Export-ModuleMember -Function Test-EnvName, Set-EnvCredential, Test-EnvCredentialPresence, Remove-EnvCredential
