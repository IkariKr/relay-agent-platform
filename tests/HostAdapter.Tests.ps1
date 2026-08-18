# HostAdapter.Tests.ps1 — 其他宿主 host adapter 契约测试（roadmap Phase E）。
# Host adapter contract tests: capability detector, generic-shell (external-cli only),
# codex host (evidence-gated native capability).
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\hosts\HostAdapter.psm1") -Force
    $script:genericShell = Join-Path $repoRoot "platform\hosts\generic-shell\GenericShellHost.psm1"
    $script:codexHost = Join-Path $repoRoot "platform\hosts\codex\CodexHostAdapter.psm1"
}

Describe "Phase E: generic-shell host exposes external-cli workers only" {
    It "reports identity" {
        $report = Get-HostCapabilityReport -HostModulePath $script:genericShell
        $report.identity.name | Should -Be "generic-shell"
    }
    It "cannot host native-provider children (roadmap E item 3)" {
        $report = Get-HostCapabilityReport -HostModulePath $script:genericShell
        $report.native_provider_capable | Should -BeFalse
        $report.installable_runtime_types | Should -Contain "external-cli"
        $report.installable_runtime_types | Should -Not -Contain "native-provider"
    }
    It "exposes only external-cli workers from the registry" {
        $workers = Get-InstallableWorkerDescriptorsForHost -HostModulePath $script:genericShell -NativeProviderRoot (Join-Path $PSScriptRoot "fixtures\workers") -BackendRoot (Join-Path $repoRoot "backends")
        @($workers | Where-Object runtime_type -eq "native-provider").Count | Should -Be 0
        @($workers | Where-Object runtime_type -eq "external-cli").Count | Should -BeGreaterThan 0
    }
}

Describe "Phase E: codex host gates native capability on evidence" {
    It "reports host identity with the codex cli version" {
        $report = Get-HostCapabilityReport -HostModulePath $script:codexHost
        $report.identity.name | Should -Be "win32"
        $report.identity.codex_cli_version | Should -Not -BeNullOrEmpty
    }
    It "fails closed when no capability evidence exists" {
        $evDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-host-ev-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $evDir -Force | Out-Null
        try {
            $report = Get-HostCapabilityReport -HostModulePath $script:codexHost -EvidenceDir $evDir
            $report.native_provider_capable | Should -BeFalse
            $report.installable_runtime_types | Should -Contain "external-cli"
        }
        finally {
            Remove-Item -LiteralPath $evDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It "reports native-provider capable when live evidence is all supported" {
        $evDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-host-ev-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $evDir -Force | Out-Null
        try {
            $supported = [ordered]@{ status = "supported" }
            $probe = [ordered]@{
                capabilities = [ordered]@{
                    custom_agent_spawn      = $supported
                    fork_isolation          = $supported
                    native_wait_callback    = $supported
                    native_cancel           = $supported
                    plaintext_initial_message = $supported
                }
            }
            $probe | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evDir "2026-08-14-codex-0.147.0-win32.json") -Encoding utf8
            $report = Get-HostCapabilityReport -HostModulePath $script:codexHost -EvidenceDir $evDir
            $report.native_provider_capable | Should -BeTrue
            $report.installable_runtime_types | Should -Contain "native-provider"
        }
        finally {
            Remove-Item -LiteralPath $evDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It "fails closed when any live capability is not yet supported" {
        $evDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-host-ev-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $evDir -Force | Out-Null
        try {
            $probe = [ordered]@{
                capabilities = [ordered]@{
                    custom_agent_spawn      = [ordered]@{ status = "supported" }
                    fork_isolation          = [ordered]@{ status = "unknown" }
                    native_wait_callback    = [ordered]@{ status = "unknown" }
                    native_cancel           = [ordered]@{ status = "unknown" }
                    plaintext_initial_message = [ordered]@{ status = "supported" }
                }
            }
            $probe | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evDir "2026-08-14-codex-0.147.0-win32.json") -Encoding utf8
            $report = Get-HostCapabilityReport -HostModulePath $script:codexHost -EvidenceDir $evDir
            $report.native_provider_capable | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $evDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
