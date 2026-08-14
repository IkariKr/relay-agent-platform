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
    It "fails closed while live-host capability evidence is unknown" {
        $report = Get-HostCapabilityReport -HostModulePath $script:codexHost
        # A2 evidence: custom_agent_spawn/fork_isolation/wait_callback/plaintext all unknown
        $report.native_provider_capable | Should -BeFalse
        $report.installable_runtime_types | Should -Contain "external-cli"
    }
}
