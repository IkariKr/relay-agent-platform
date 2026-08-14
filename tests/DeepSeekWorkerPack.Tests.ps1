# DeepSeekWorkerPack.Tests.ps1 — DeepSeek native-provider pack 生命周期测试（DS-*）。
# Lifecycle tests for the DeepSeek native-provider pack (DS-CONFIG/DS-SECRET/DS-OWN/DS-MAIN).
# 全部在临时 CODEX_HOME 上执行，绝不动真实用户配置；无任何付费调用。
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerPackManager.psm1") -Force

    $script:workerId = "deepseek-v4-flash"
    $script:packDir = Join-Path $repoRoot "workers\native-providers\deepseek-v4-flash"
    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-pack-" + [guid]::NewGuid().ToString("N"))
    $script:codexHome = Join-Path $script:testRoot "codex-home"
    New-Item -ItemType Directory -Path $script:codexHome -Force | Out-Null

    # 主配置哨兵：模拟现有 config.toml（含主 provider/model），用于主配置不变断言。
    $script:mainConfig = Join-Path $script:codexHome "config.toml"
    "[model]`nmodel_provider = `"openai`"`nmodel = `"gpt-main`"" | Set-Content -LiteralPath $script:mainConfig -Encoding utf8
}

AfterAll {
    Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "DS-CONFIG-001: agent role + provider overlay are resolvable" {
    It "worker.json loads through the native-provider loader and is discoverable" {
        $m = Load-NativeProviderWorkerManifest -Path (Join-Path $script:packDir "worker.json")
        $m.runtime_type | Should -Be "native-provider"
        $m.id | Should -Be $script:workerId
        $m.provider.provider_id | Should -Be "deepseek"
        $m.provider.wire_api | Should -Be "responses"
        $m.provider.credential_source | Should -Be "env:DEEPSEEK_API_KEY"
    }
    It "the pack agent overlay exists and carries the expected provider wiring" {
        $toml = Get-Content -Raw -LiteralPath (Join-Path $script:packDir "agent.toml")
        $toml | Should -Match "model_provider = `"deepseek`""
        $toml | Should -Match "wire_api = `"responses`""
        $toml | Should -Match "env_key = `"DEEPSEEK_API_KEY`""
    }
}

Describe "DS-SECRET-001: preflight checks presence without exposing the value" {
    It "reports present without printing the credential value" {
        $sentinel = "SENTINEL-SECRET-" + [guid]::NewGuid().ToString("N")
        $env:DEEPSEEK_API_KEY = $sentinel
        try {
            $result = Test-WorkerSecretPreflight -CredentialSource "env:DEEPSEEK_API_KEY"
            $result.present | Should -BeTrue
            ($result.detail) | Should -Not -Match [regex]::Escape($sentinel)
            ($result | ConvertTo-Json) | Should -Not -Match [regex]::Escape($sentinel)
        }
        finally {
            Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
        }
    }
    It "reports absent cleanly when the variable is not set" {
        Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
        $result = Test-WorkerSecretPreflight -CredentialSource "env:DEEPSEEK_API_KEY"
        $result.present | Should -BeFalse
        $result.detail | Should -Not -Match [regex]::Escape("DEEPSEEK_API_KEY=")
    }
}

Describe "DS-OWN-001: install/uninstall only touch pack-owned state" {
    It "install writes exactly the declared owned paths" {
        $before = @(Get-ChildItem -Path $script:codexHome -Recurse -File | ForEach-Object { $_.FullName })
        $result = Install-WorkerPack -WorkerId $script:workerId -DestinationCodexHome $script:codexHome
        @($result.written).Count | Should -Be 1
        $target = Join-Path $script:codexHome "agents\relay\deepseek-v4-flash.toml"
        (Test-Path -LiteralPath $target) | Should -BeTrue
        $after = @(Get-ChildItem -Path $script:codexHome -Recurse -File | ForEach-Object { $_.FullName })
        @($after | Where-Object { $before -notcontains $_ }).Count | Should -Be 1
    }
    It "uninstall removes only pack-owned files and leaves the rest" {
        Uninstall-WorkerPack -WorkerId $script:workerId -DestinationCodexHome $script:codexHome | Out-Null
        (Test-Path -LiteralPath (Join-Path $script:codexHome "agents\relay\deepseek-v4-flash.toml")) | Should -BeFalse
        (Test-Path -LiteralPath $script:mainConfig) | Should -BeTrue
    }
}

Describe "DS-MAIN-001: install never changes the main Agent provider/model" {
    It "config.toml stays byte-identical and the main provider/model survive" {
        $original = Get-Content -Raw -LiteralPath $script:mainConfig
        Install-WorkerPack -WorkerId $script:workerId -DestinationCodexHome $script:codexHome | Out-Null
        $after = Get-Content -Raw -LiteralPath $script:mainConfig
        $after | Should -Be $original
        $after | Should -Match "model_provider = `"openai`""
        $after | Should -Match "model = `"gpt-main`""
        Uninstall-WorkerPack -WorkerId $script:workerId -DestinationCodexHome $script:codexHome | Out-Null
    }
}
