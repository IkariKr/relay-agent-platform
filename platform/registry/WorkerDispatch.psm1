Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Worker Dispatch：决定 worker/runtime 选择（roadmap Phase C）。
# 用户显式点名的 worker 永不被 heuristic 替换；sensitive 数据在
# deny-unless-explicitly-classified 边界下 fail closed；自动调度 native-provider 优先。
# Decides worker/runtime selection. Explicit user selection is never replaced by
# heuristics; sensitive data fails closed under deny-unless-explicitly-classified;
# auto dispatch prefers native-provider then external-cli.
Import-Module (Join-Path $PSScriptRoot "WorkerRegistry.psm1") -Force

function Test-DataBoundaryAllowsDispatch {
    param(
        [Parameter(Mandatory = $true)]$DataBoundary,
        [Parameter(Mandatory = $true)][ValidateSet("public", "sensitive")][string]$DataClass
    )

    if ($DataClass -eq "sensitive" -and $DataBoundary.sensitive_auto_dispatch -eq "deny-unless-explicitly-classified") {
        return $false
    }
    return $true
}

function Get-DispatchDecision {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [ValidateSet("public", "sensitive")][string]$DataClass = "public",
        [string]$HostName = "",
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot
    $runtimeType = Get-WorkerRuntimeType -WorkerId $WorkerId -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot

    $providerId = ""
    $modelId = ""
    if ($descriptor.PSObject.Properties.Name -contains "provider") {
        $providerId = [string]$descriptor.provider.provider_id
        $modelId = [string]$descriptor.provider.model_id
    }

    $allowed = Test-DataBoundaryAllowsDispatch -DataBoundary $descriptor.data_boundary -DataClass $DataClass

    return [pscustomobject]@{
        worker_id = $WorkerId
        runtime_type = $runtimeType
        host = $HostName
        provider = $providerId
        model = $modelId
        data_class = $DataClass
        data_boundary_decision = $allowed
        result_status = if ($allowed) { "allowed" } else { "denied" }
    }
}

function Get-AutoDispatchDecision {
    param(
        [Parameter(Mandatory = $true)][string[]]$CandidateWorkerIds,
        [ValidateSet("public", "sensitive")][string]$DataClass = "public",
        [string]$HostName = "",
        [string]$NativeProviderRoot = "",
        [string]$BackendRoot = ""
    )

    foreach ($workerId in $CandidateWorkerIds) {
        $decision = Get-DispatchDecision -WorkerId $workerId -DataClass $DataClass -HostName $HostName -NativeProviderRoot $NativeProviderRoot -BackendRoot $BackendRoot
        if ($decision.data_boundary_decision) {
            return $decision
        }
    }

    # 所有候选均被数据策略拒绝 → fail closed，不静默降级。
    # All candidates denied by data policy -> fail closed, no silent downgrade.
    return [pscustomobject]@{
        worker_id = ""
        runtime_type = ""
        host = $HostName
        provider = ""
        model = ""
        data_class = $DataClass
        data_boundary_decision = $false
        result_status = "denied-fail-closed"
    }
}

Export-ModuleMember -Function Test-DataBoundaryAllowsDispatch, Get-DispatchDecision, Get-AutoDispatchDecision
