# CodexProviderConfigGenerator.Tests.ps1 — overlay 生成与 ownership 契约测试。
# Contract tests for generated Codex overlays (NP-GEN-*), per onboarding plan §11.3.
# 全部在临时 CODEX_HOME 上执行；主 config.toml 不被修改；无任何付费调用。
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\generation\CodexProviderConfigGenerator.psm1") -Force
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerProfileStore.psm1") -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-gen-" + [guid]::NewGuid().ToString("N"))
    $script:codexHome = Join-Path $script:testRoot "codex-home"
    New-Item -ItemType Directory -Path $script:codexHome -Force | Out-Null

    $script:workerId = "deepseek-v4-flash"
    $script:suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $script:profileId = "gen-profile-" + $script:suffix
    $script:baseUrl = "https://nexus.example.com/v1"
    $script:modelId = "deepseek-v4-flash-response"
    $script:secret = "sk-gen-test-" + [guid]::NewGuid().ToString("N")

    $null = New-ProviderProfile -WorkerId $script:workerId -ProfileId $script:profileId `
        -BaseUrl $script:baseUrl -ModelId $script:modelId -CodexHome $script:codexHome

    # 主配置哨兵：生成器不得触碰
    $script:mainConfig = Join-Path $script:codexHome "config.toml"
    "[model]`nmodel_provider = `"openai`"`nmodel = `"gpt-main`"" | Set-Content -LiteralPath $script:mainConfig -Encoding utf8

    $script:overlayPath = Get-GeneratedOverlayPath -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome
}

AfterAll {
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "NP-GEN: overlay generation and ownership" {
    It "NP-GEN-001: pack + profile generate a valid overlay file" {
        $result = New-CodexAgentOverlay -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome
        (Test-Path -LiteralPath $result.path) | Should -BeTrue
        $result.path | Should -Be $script:overlayPath
        $result.worker_id | Should -Be $script:workerId
        $result.profile_id | Should -Be $script:profileId
    }

    It "NP-GEN-002: generated config uses the profile base url and model id" {
        $raw = Get-Content -Raw -LiteralPath $script:overlayPath
        $raw | Should -Match ("base_url = `"" + [regex]::Escape($script:baseUrl) + "`"")
        $raw | Should -Match ("model = `"" + [regex]::Escape($script:modelId) + "`"")
        $raw | Should -Match "model_provider = `"deepseek`""
        $raw | Should -Match "\[model_providers\.deepseek\]"
        $raw | Should -Match "wire_api = `"responses`""
        $raw | Should -Match "sandbox_mode = `"read-only`""
    }

    It "NP-GEN-003: api key appears only as an env reference, never as a value" {
        # secret 放入进程 env（模拟用户已配置 credential），生成物不得包含值
        $profile = Get-ProviderProfile -ProfileId $script:profileId -CodexHome $script:codexHome
        $envName = ([string]$profile.credential_source).Substring(4)
        [Environment]::SetEnvironmentVariable($envName, $script:secret, "Process")
        try {
            $raw = Get-Content -Raw -LiteralPath $script:overlayPath
            $raw | Should -Match ("env_key = `"" + [regex]::Escape($envName) + "`"")
            $raw | Should -Not -Match [regex]::Escape($script:secret)
        }
        finally {
            [Environment]::SetEnvironmentVariable($envName, $null, "Process")
        }
    }

    It "NP-GEN-004: main config.toml stays byte-identical (global model/provider untouched)" {
        $original = Get-Content -Raw -LiteralPath $script:mainConfig
        $null = New-CodexAgentOverlay -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome
        $after = Get-Content -Raw -LiteralPath $script:mainConfig
        $after | Should -Be $original
        $after | Should -Match "model_provider = `"openai`""
        $after | Should -Match "model = `"gpt-main`""
    }

    It "NP-GEN-005: non-relay file at the target path stops generation (fail closed)" {
        $otherProfile = "gen-other-" + $script:suffix
        $null = New-ProviderProfile -WorkerId $script:workerId -ProfileId $otherProfile `
            -BaseUrl "https://other.example.com/v1" -ModelId $script:modelId -CodexHome $script:codexHome
        $otherTarget = Get-GeneratedOverlayPath -WorkerId $script:workerId -ProfileId $otherProfile -CodexHome $script:codexHome
        # 模拟外部文件占位：无 ownership marker
        "model = `"external`"" | Set-Content -LiteralPath $otherTarget -Encoding utf8
        { New-CodexAgentOverlay -WorkerId $script:workerId -ProfileId $otherProfile -CodexHome $script:codexHome } |
            Should -Throw "*not relay-agent owned*"
    }

    It "NP-GEN-006: uninstall removes only relay-owned generated state" {
        Remove-GeneratedOverlay -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome | Out-Null
        (Test-Path -LiteralPath $script:overlayPath) | Should -BeFalse
        # profile 与主配置保留
        (Test-Path -LiteralPath (Get-ProfileFilePath -ProfileId $script:profileId -CodexHome $script:codexHome)) | Should -BeTrue
        (Test-Path -LiteralPath $script:mainConfig) | Should -BeTrue
    }

    It "NP-GEN-007: regenerate after profile update picks up new values" {
        $null = New-CodexAgentOverlay -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome
        $newModel = "deepseek-v4-flash-response-updated"
        $null = Update-ProviderProfile -ProfileId $script:profileId -ModelId $newModel -CodexHome $script:codexHome
        $null = New-CodexAgentOverlay -WorkerId $script:workerId -ProfileId $script:profileId -CodexHome $script:codexHome
        $raw = Get-Content -Raw -LiteralPath $script:overlayPath
        $raw | Should -Match ("model = `"" + [regex]::Escape($newModel) + "`"")
        $raw | Should -Match "managed_by=relay-agent"
    }
}
