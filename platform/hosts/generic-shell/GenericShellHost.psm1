Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Generic shell host：无 Codex 原生 multi-agent 能力，只能承载 external-cli worker。
# A plain shell cannot host Codex native children; it only exposes external-cli workers.
function Get-HostIdentity {
    return [pscustomobject]@{
        name = "generic-shell"
        description = "plain shell without Codex native-child hosting"
    }
}

function Test-HostNativeProviderCapability {
    param([string]$CapabilityName = "native-provider-child")

    return $false
}

function Get-HostInstalledWorkerRuntimeTypes {
    return @("external-cli")
}

Export-ModuleMember -Function Get-HostIdentity, Test-HostNativeProviderCapability, Get-HostInstalledWorkerRuntimeTypes
