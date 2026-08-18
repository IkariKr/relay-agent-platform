# WorkerRegistry.Tests.ps1 — Worker Runtime Registry 契约测试（WR-*）。
# Contract tests for the Worker Runtime Registry (WR-SCHEMA/WR-ADAPTER/WR-NATIVE/WR-ID/WR-DATA).
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerRegistry.psm1") -Force

    $script:fixtureProviderRoot = Join-Path $PSScriptRoot "fixtures\workers"
    $script:backendRoot = Join-Path $repoRoot "backends"
    $script:fixturePath = Join-Path $script:fixtureProviderRoot "native-provider-fixture\worker.json"
}

Describe "WR-SCHEMA-001: native-provider manifest validation" {
    It "accepts a valid synthetic native-provider manifest" {
        $m = Load-NativeProviderWorkerManifest -Path $script:fixturePath
        $m.runtime_type | Should -Be "native-provider"
        $m.id | Should -Be "native-fixture"
    }
    It "rejects a native-provider manifest that fakes a command" {
        $m = Get-Content -Raw -LiteralPath $script:fixturePath | ConvertFrom-Json
        $m | Add-Member -NotePropertyName command -NotePropertyValue "deepseek" -Force
        Test-WorkerManifest -Manifest $m | Should -BeFalse
    }
    It "rejects a native-provider manifest without a provider block" {
        $m = Get-Content -Raw -LiteralPath $script:fixturePath | ConvertFrom-Json
        $m.PSObject.Properties.Remove("provider")
        Test-WorkerManifest -Manifest $m | Should -BeFalse
    }
    It "rejects an unknown runtime_type" {
        $m = Get-Content -Raw -LiteralPath $script:fixturePath | ConvertFrom-Json
        $m.runtime_type = "mystery-runtime"
        Test-WorkerManifest -Manifest $m | Should -BeFalse
    }
}

Describe "WR-ADAPTER-001: legacy backend.json normalizes to an external-cli WorkerDescriptor" {
    It "claude" {
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "claude\backend.json") | ConvertFrom-Json
        $desc = ConvertFrom-BackendManifest -BackendManifest $manifest
        $desc.runtime_type | Should -Be "external-cli"
        $desc.id | Should -Be "claude"
        $desc.cli.command | Should -Be "claude"
        $desc.cli.product_name | Should -Be "Claude Code"
    }
    It "opencode" {
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "opencode\backend.json") | ConvertFrom-Json
        $desc = ConvertFrom-BackendManifest -BackendManifest $manifest
        $desc.runtime_type | Should -Be "external-cli"
        $desc.id | Should -Be "opencode"
        $desc.cli.command | Should -Be "opencode"
    }
}

Describe "WR-ADAPTER-002: adapter injects defaults without touching the legacy schema" {
    It "conservative data boundary for unknown egress" {
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "opencode\backend.json") | ConvertFrom-Json
        $desc = ConvertFrom-BackendManifest -BackendManifest $manifest
        $desc.data_boundary.execution_boundary | Should -Be "external-process"
        $desc.data_boundary.egress | Should -Be "unknown-or-provider-dependent"
        $desc.data_boundary.sensitive_auto_dispatch | Should -Be "deny-unless-explicitly-classified"
    }
    It "legacy backend.json itself is unchanged (no schema migration needed)" {
        $raw = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "claude\backend.json") | ConvertFrom-Json
        $raw.PSObject.Properties.Name | Should -Not -Contain "runtime_type"
        $raw.PSObject.Properties.Name | Should -Not -Contain "data_boundary"
    }
}

Describe "WR-NATIVE-001: registry describes both runtime types without a fake CLI" {
    It "enumerates external-cli and native-provider workers together" {
        $workers = Get-WorkerDescriptors -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot
        @($workers | Where-Object id -eq "native-fixture").Count | Should -Be 1
        @($workers | Where-Object id -eq "claude").Count | Should -Be 1
        @($workers | Where-Object runtime_type -eq "external-cli").Count | Should -BeGreaterThan 0
    }
    It "native-provider descriptor carries no CLI command" {
        $desc = Get-WorkerDescriptor -WorkerId "native-fixture" -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot
        $desc.PSObject.Properties.Name | Should -Not -Contain "command"
        $desc.PSObject.Properties.Name | Should -Not -Contain "runner_script"
    }
    It "external-cli worker resolves through the adapter source of truth" {
        $desc = Get-WorkerDescriptor -WorkerId "antigravity" -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot
        $desc.runtime_type | Should -Be "external-cli"
        $desc.cli.command | Should -Be "agy"
    }
}

Describe "WR-ID-001: worker id is the stable registry key" {
    It "unknown worker id throws" {
        { Get-WorkerDescriptor -WorkerId "not-a-worker" -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot } | Should -Throw
    }
    It "runtime type dispatch is stable across lookups" {
        Get-WorkerRuntimeType -WorkerId "native-fixture" -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot | Should -Be "native-provider"
        Get-WorkerRuntimeType -WorkerId "opencode" -NativeProviderRoot $script:fixtureProviderRoot -BackendRoot $script:backendRoot | Should -Be "external-cli"
    }
}

Describe "WR-DATA-001/002: data boundary defaults and explicit overrides" {
    It "unknown external-cli egress denies sensitive auto-dispatch by default (WR-DATA-001)" {
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "claude\backend.json") | ConvertFrom-Json
        $desc = ConvertFrom-BackendManifest -BackendManifest $manifest
        $desc.data_boundary.sensitive_auto_dispatch | Should -Be "deny-unless-explicitly-classified"
    }
    It "an explicit local-only profile overrides the conservative default (WR-DATA-002)" {
        $manifest = Get-Content -Raw -LiteralPath (Join-Path $script:backendRoot "opencode\backend.json") | ConvertFrom-Json
        $desc = ConvertFrom-BackendManifest -BackendManifest $manifest -DataBoundaryOverride @{ egress = "local-only" }
        $desc.data_boundary.egress | Should -Be "local-only"
        $desc.data_boundary.sensitive_auto_dispatch | Should -Be "deny-unless-explicitly-classified"
    }
}
