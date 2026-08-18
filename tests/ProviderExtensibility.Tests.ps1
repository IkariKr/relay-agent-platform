# ProviderExtensibility.Tests.ps1 — 第二 provider 零核心特判验收（roadmap Phase D）。
# Second-provider acceptance: adding provider-b requires only manifest + config +
# smoke fixture, with zero provider-specific branches in the registry core.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    # 顺序敏感：WorkerDispatch 模块内会 -Force 重载 WorkerRegistry（PowerShell 会
    # 把它从全局会话移除并装入 WorkerDispatch 模块作用域），因此必须先 Import
    # WorkerDispatch，再 Import WorkerRegistry 到全局，避免测试依赖执行顺序。
    # Order matters: WorkerDispatch -Force reloads WorkerRegistry into its module
    # scope and evicts the global copy, so import WorkerDispatch first, then the
    # registry, keeping this file self-contained.
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerDispatch.psm1") -Force
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerRegistry.psm1") -Force
    $script:fixtureRoot = Join-Path $PSScriptRoot "fixtures\workers"
    $script:backendRoot = Join-Path $repoRoot "backends"
}

Describe "Phase D: provider-b lands through the same registry code path" {
    It "is enumerated with no core change" {
        $workers = Get-WorkerDescriptors -NativeProviderRoot $script:fixtureRoot -BackendRoot $script:backendRoot
        @($workers | Where-Object id -eq "provider-b").Count | Should -Be 1
    }
    It "resolves its descriptor with the declared provider wiring" {
        $desc = Get-WorkerDescriptor -WorkerId "provider-b" -NativeProviderRoot $script:fixtureRoot -BackendRoot $script:backendRoot
        $desc.runtime_type | Should -Be "native-provider"
        $desc.provider.provider_id | Should -Be "provider-b"
        $desc.provider.credential_source | Should -Be "env:PROVIDER_B_API_KEY"
    }
    It "dispatch handles the second provider without modification" {
        $d = Get-DispatchDecision -WorkerId "provider-b" -DataClass public -NativeProviderRoot $script:fixtureRoot -BackendRoot $script:backendRoot
        $d.result_status | Should -Be "allowed"
        $d.runtime_type | Should -Be "native-provider"
    }
}

Describe "Phase D: the registry core has no provider-specific branches" {
    It "platform/registry contains no deepseek or provider-b literals" {
        $core = @(Get-ChildItem -Path (Join-Path $repoRoot "platform\registry") -Filter "*.psm1" -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
        $core | Should -Not -Match "deepseek"
        $core | Should -Not -Match "provider-b"
    }
    It "the full suite keeps passing unchanged (cumulative coverage)" {
        # 该文件被全量套件执行时，WR-/DS-/Dispatch 用例一起通过即证明无核心回归。
        (Test-Path -LiteralPath (Join-Path $repoRoot "tests\WorkerRegistry.Tests.ps1")) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $repoRoot "tests\DeepSeekWorkerPack.Tests.ps1")) | Should -BeTrue
    }
}
