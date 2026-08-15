# SkillProtocol.Tests.ps1 — skill Agent protocol 与 package 自包含测试。
# Tests for the generated skill protocol (NP-SKILL-*) and package self-containment
# (NP-PKG-001), per onboarding plan §11.4. Runs after scripts/build-packages.ps1.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    # 先执行真实构建（幂等），确保测试的是当前生成物
    & (Join-Path $repoRoot "scripts\build-packages.ps1") | Out-Null

    $script:agentSkill = Join-Path $repoRoot "packages\relay-agent\SKILL.md"
    $script:claudeSkill = Join-Path $repoRoot "packages\relay-claude\SKILL.md"
    $script:agentPackage = Join-Path $repoRoot "packages\relay-agent"
}

Describe "NP-SKILL: generated relay-agent skill carries the Agent protocol" {
    It "NP-SKILL-001: SKILL.md contains the native-provider discovery/config/execute flow" {
        (Test-Path -LiteralPath $script:agentSkill) | Should -BeTrue
        $content = Get-Content -Raw -LiteralPath $script:agentSkill
        $content | Should -Match "Native Provider Workers"
        $content | Should -Match "relay worker list --json"
        $content | Should -Match "relay worker configure"
        $content | Should -Match "--api-key-stdin"
        $content | Should -Match "relay worker doctor"
        $content | Should -Match "relay worker dispatch"
    }

    It "NP-SKILL-002: the skill forbids command-line api keys" {
        $content = Get-Content -Raw -LiteralPath $script:agentSkill
        $content | Should -Match "不存在"
        $content | Should -Match "--api-key <value>"
        $content | Should -Match "绝不"
    }

    It "NP-SKILL-003: skill description matches native-provider configuration intent" {
        $content = Get-Content -Raw -LiteralPath $script:agentSkill
        $content | Should -Match "native-provider workers"
        $content | Should -Match "Responses-compatible"
        $content | Should -Match "Base URL"
    }

    It "NP-SKILL-005: runtime error codes have explicit Agent recovery actions" {
        $content = Get-Content -Raw -LiteralPath $script:agentSkill
        $content | Should -Match "PROFILE_SELECTION_REQUIRED"
        $content | Should -Match "profile_ids"
        $content | Should -Match "AGENT_REGISTRATION_MISSING"
        $content | Should -Match '重跑 `configure`'
    }

    It "dedicated external-cli surfaces do not expose native-provider onboarding" {
        $claude = Get-Content -Raw -LiteralPath $script:claudeSkill
        $claude | Should -Not -Match "Native Provider Workers"
    }
}

Describe "NP-PKG: relay-agent package is self-contained for native-provider" {
    It "NP-PKG-001: package ships registry/contracts/hosts/credentials/generation/cli and the worker pack" {
        foreach ($required in @(
                "platform\cli\WorkerCli.psm1",
                "platform\registry\WorkerProfileStore.psm1",
                "platform\registry\WorkerPackManager.psm1",
                "platform\contracts\provider-profile.schema.json",
                "platform\contracts\worker-manifest.schema.json",
                "platform\hosts\codex\Doctor.psm1",
                "platform\hosts\codex\CapabilityProbe.psm1",
                "platform\credentials\CredentialStore.psm1",
                "platform\generation\CodexProviderConfigGenerator.psm1",
                "workers\native-providers\deepseek-v4-flash\worker.json",
                "workers\native-providers\deepseek-v4-flash\agent.toml"
            )) {
            (Test-Path -LiteralPath (Join-Path $script:agentPackage $required)) | Should -BeTrue -Because $required
        }
    }

    It "NP-PKG-002: worker list runs from the packaged module tree (clean install simulation)" {
        Import-Module (Join-Path $script:agentPackage "platform\cli\WorkerCli.psm1") -Force
        $out = (& { $code = Invoke-WorkerCommand -Tokens @("list", "--json"); "EXIT=$code" } 6>&1 | Out-String)
        $exitMatch = [regex]::Match($out, "EXIT=(\d+)\s*$")
        [int]$exitMatch.Groups[1].Value | Should -Be 0
        $jsonLine = ($out -replace "EXIT=\d+\s*$", "").Trim()
        $json = $jsonLine | ConvertFrom-Json
        @($json.workers | Where-Object { $_.worker_id -eq "deepseek-v4-flash" })[0].runtime_type | Should -Be "native-provider"
    }
}
