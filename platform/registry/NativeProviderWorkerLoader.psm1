Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Native-provider worker loader：native-provider manifest 不需要 command/runner_script。
# Native-provider manifests must NOT require command/runner_script (no fake CLI).
function Test-WorkerManifest {
    param([Parameter(Mandatory = $true)]$Manifest)

    $requiredCommon = @(
        "id", "display_name", "runtime_type", "purpose",
        "host_requirements", "data_boundary", "permissions",
        "install_contract", "health_check", "smoke_test", "uninstall_contract"
    )
    foreach ($key in $requiredCommon) {
        if ($Manifest.PSObject.Properties.Name -notcontains $key) { return $false }
    }
    if ($Manifest.runtime_type -notin @("native-provider", "external-cli")) { return $false }

    if ($Manifest.runtime_type -eq "native-provider") {
        if ($Manifest.PSObject.Properties.Name -notcontains "provider") { return $false }
        # 禁止伪造 CLI：native-provider 不得声明 command/runner_script。
        # Forbidden to fake a CLI: native-provider must not declare command/runner_script.
        if ($Manifest.PSObject.Properties.Name -contains "command") { return $false }
        if ($Manifest.PSObject.Properties.Name -contains "runner_script") { return $false }
        foreach ($providerKey in @("provider_id", "model_id", "wire_api", "credential_source", "default_sandbox")) {
            if ($Manifest.provider.PSObject.Properties.Name -notcontains $providerKey) { return $false }
        }
    }

    return $true
}

function Load-NativeProviderWorkerManifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $manifest = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if (-not (Test-WorkerManifest -Manifest $manifest)) {
        throw "worker manifest validation failed: $Path"
    }
    if ($manifest.runtime_type -ne "native-provider") {
        throw "not a native-provider manifest: $Path"
    }
    return $manifest
}

Export-ModuleMember -Function Test-WorkerManifest, Load-NativeProviderWorkerManifest
