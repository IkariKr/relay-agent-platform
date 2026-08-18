# WorkerDispatch.Tests.ps1 — 统一 Dispatch Policy 契约测试（roadmap Phase C）。
# Dispatch policy contract tests: explicit selection wins, data-boundary fail-closed,
# auto dispatch prefers native-provider, dispatch metadata is recorded.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerDispatch.psm1") -Force
}

Describe "Phase C: explicit user worker selection is never replaced by heuristics" {
    It "returns the explicitly selected native-provider worker" {
        $d = Get-DispatchDecision -WorkerId "deepseek-v4-flash" -DataClass public -HostName "win32"
        $d.worker_id | Should -Be "deepseek-v4-flash"
        $d.runtime_type | Should -Be "native-provider"
        $d.provider | Should -Be "deepseek"
        $d.result_status | Should -Be "allowed"
    }
    It "returns the explicitly selected external-cli worker" {
        $d = Get-DispatchDecision -WorkerId "claude" -DataClass public -HostName "win32"
        $d.worker_id | Should -Be "claude"
        $d.runtime_type | Should -Be "external-cli"
        $d.result_status | Should -Be "allowed"
    }
    It "unknown worker id fails closed" {
        { Get-DispatchDecision -WorkerId "not-a-worker" -DataClass public } | Should -Throw
    }
}

Describe "Phase C: data boundary gating fails closed on sensitive data" {
    It "sensitive data is denied for deny-unless-explicitly-classified workers" {
        $d = Get-DispatchDecision -WorkerId "deepseek-v4-flash" -DataClass sensitive
        $d.data_boundary_decision | Should -BeFalse
        $d.result_status | Should -Be "denied"
    }
    It "sensitive data is denied for external-cli workers with the conservative default too" {
        $d = Get-DispatchDecision -WorkerId "opencode" -DataClass sensitive
        $d.data_boundary_decision | Should -BeFalse
    }
    It "public data is allowed for both runtime types" {
        (Get-DispatchDecision -WorkerId "deepseek-v4-flash" -DataClass public).result_status | Should -Be "allowed"
        (Get-DispatchDecision -WorkerId "claude" -DataClass public).result_status | Should -Be "allowed"
    }
}

Describe "Phase C: auto dispatch prefers native-provider then external-cli, fail-closed on policy denial" {
    It "prefers native-provider for public data" {
        $d = Get-AutoDispatchDecision -CandidateWorkerIds @("deepseek-v4-flash", "claude") -DataClass public -HostName "win32"
        $d.worker_id | Should -Be "deepseek-v4-flash"
        $d.runtime_type | Should -Be "native-provider"
    }
    It "fails closed when every candidate is denied by the data policy" {
        $d = Get-AutoDispatchDecision -CandidateWorkerIds @("deepseek-v4-flash", "claude", "opencode") -DataClass sensitive
        $d.result_status | Should -Be "denied-fail-closed"
        $d.worker_id | Should -Be ""
    }
}

Describe "Phase C: dispatch records public metadata" {
    It "metadata includes worker id, runtime type, host, provider/model, boundary decision, result status" {
        $d = Get-DispatchDecision -WorkerId "deepseek-v4-flash" -DataClass public -HostName "win32"
        $d.worker_id | Should -Be "deepseek-v4-flash"
        $d.runtime_type | Should -Be "native-provider"
        $d.host | Should -Be "win32"
        $d.provider | Should -Be "deepseek"
        $d.model | Should -Not -BeNullOrEmpty
        $d.data_class | Should -Be "public"
        $d.data_boundary_decision | Should -BeTrue
        $d.result_status | Should -Be "allowed"
    }
}
