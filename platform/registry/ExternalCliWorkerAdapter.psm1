Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ExternalCliWorkerAdapter：把 legacy backend.json 归一化为统一 WorkerDescriptor。
# Normalizes legacy backend.json into the unified WorkerDescriptor; legacy schema
# is untouched (no flag-day migration, no fake fields for native providers).
function ConvertFrom-BackendManifest {
    param(
        [Parameter(Mandatory = $true)]$BackendManifest,
        [hashtable]$DataBoundaryOverride = $null
    )

    $dataBoundary = [ordered]@{
        execution_boundary = "external-process"
        egress = "unknown-or-provider-dependent"
        sensitive_auto_dispatch = "deny-unless-explicitly-classified"
    }
    if ($null -ne $DataBoundaryOverride) {
        foreach ($key in $DataBoundaryOverride.Keys) {
            $dataBoundary[$key] = $DataBoundaryOverride[$key]
        }
    }

    $descriptor = [ordered]@{
        id = [string]$BackendManifest.id
        display_name = [string]$BackendManifest.display_name
        runtime_type = "external-cli"
        purpose = "run the $($BackendManifest.id) CLI as a thin external worker"
        host_requirements = [ordered]@{ command_on_path = [string]$BackendManifest.command }
        data_boundary = $dataBoundary
        permissions = [ordered]@{ process_scope = "one native CLI invocation" }
        install_contract = [ordered]@{ kind = "cli-on-path"; command = [string]$BackendManifest.command }
        health_check = [ordered]@{ kind = "command-resolution" }
        smoke_test = [ordered]@{ kind = "best-effort" }
        uninstall_contract = [ordered]@{ kind = "none" }
        cli = [ordered]@{
            command = [string]$BackendManifest.command
            product_name = [string]$BackendManifest.product_name
            package_name = [string]$BackendManifest.package_name
            runner_script = [string]$BackendManifest.runner_script
            default_surface = [string]$BackendManifest.default_surface
            capabilities = $BackendManifest.capabilities
        }
    }

    return [pscustomobject]$descriptor
}

Export-ModuleMember -Function ConvertFrom-BackendManifest
