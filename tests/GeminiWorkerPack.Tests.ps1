# GeminiWorkerPack.Tests.ps1 — Gemini 原生 provider pack 基础契约。
# Gemini native-provider pack baseline contract.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerPackManager.psm1") -Force

    $script:workerId = "gemini-3-7-flash-high"
    $script:packDir = Join-Path $repoRoot "workers\native-providers\$script:workerId"
}

Describe "GM-CONFIG-001: Gemini native-provider pack is discoverable" {
    It "declares a Responses-compatible Gemini worker with a read-only overlay" {
        $manifest = Load-NativeProviderWorkerManifest -Path (Join-Path $script:packDir "worker.json")
        $manifest.id | Should -Be $script:workerId
        $manifest.runtime_type | Should -Be "native-provider"
        $manifest.provider.provider_id | Should -Be "gemini"
        $manifest.provider.model_id | Should -Be "gemini-3.7-flash-high"
        $manifest.provider.wire_api | Should -Be "responses"
        $manifest.permissions.sandbox_mode | Should -Be "read-only"

        $overlay = Get-Content -Raw -LiteralPath (Join-Path $script:packDir "agent.toml")
        $overlay | Should -Match 'model_provider = "gemini"'
        $overlay | Should -Match 'model = "<provider-model-id>"'
        $overlay | Should -Match 'wire_api = "responses"'
    }
}
