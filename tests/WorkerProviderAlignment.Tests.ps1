# WorkerProviderAlignment.Tests.ps1 — provider 对齐/别名映射检查测试（B2/B4 重开前置）。
# Provider alignment + alias mapping checks; reads only provider section names.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerPackManager.psm1") -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-align-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "provider alignment: exact match" {
    It "reports aligned when the host config has [model_providers.deepseek]" {
        $cfg = Join-Path $script:testRoot "exact.toml"
        "[model_providers.deepseek]`nname = `"DeepSeek`"" | Set-Content -LiteralPath $cfg -Encoding utf8
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath $cfg
        $r.status | Should -Be "aligned"
        $r.expected_provider | Should -Be "deepseek"
    }
}

Describe "provider alignment: alias mapping (custom -> deepseek)" {
    It "reports aligned via the declared provider_alias when the host config has [model_providers.custom]" {
        $cfg = Join-Path $script:testRoot "alias.toml"
        "[model_providers.custom]`nname = `"Custom`"" | Set-Content -LiteralPath $cfg -Encoding utf8
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath $cfg
        $r.status | Should -Be "aligned"
        $r.provider_aliases | Should -Contain "custom"
        $r.actual_providers | Should -Contain "custom"
    }
    It "reports the alias list for the deepseek pack" {
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath (Join-Path $script:testRoot "alias.toml")
        $r.provider_aliases | Should -Contain "custom"
    }
}

Describe "provider alignment: mismatch" {
    It "reports misaligned when the host config has an unrelated provider" {
        $cfg = Join-Path $script:testRoot "other.toml"
        "[model_providers.other-vendor]`nname = `"Other`"" | Set-Content -LiteralPath $cfg -Encoding utf8
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath $cfg
        $r.status | Should -Be "misaligned"
    }
    It "reports misaligned when config.toml is missing" {
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath (Join-Path $script:testRoot "missing.toml")
        $r.status | Should -Be "misaligned"
    }
    It "reads only provider section names and never secret values" {
        $cfg = Join-Path $script:testRoot "secret.toml"
        "[model_providers.custom]`nname = `"Custom`"`nenv_key = `"DEEPSEEK_API_KEY`"`nbase_url = `"https://secret-endpoint.example`"" | Set-Content -LiteralPath $cfg -Encoding utf8
        $r = Test-WorkerProviderAlignment -WorkerId "deepseek-v4-flash" -CodexConfigPath $cfg
        $r.status | Should -Be "aligned"
        ($r | ConvertTo-Json) | Should -Not -Match "secret-endpoint"
    }
}
