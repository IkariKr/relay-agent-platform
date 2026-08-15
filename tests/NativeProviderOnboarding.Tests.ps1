# NativeProviderOnboarding.Tests.ps1 — 端到端 Agent onboarding 验收（onboarding plan §12 P0-E）。
# 从用户视角只提供 Base URL / Model ID / API Key，走完整 CLI 流程；终点是
# dispatch-ready（child 生命周期由 Codex host 原生执行，测试不做 paid 调用）。
# End-to-end onboarding from the user's point of view (Base URL / Model ID / API Key
# only); ends at dispatch-ready. No paid calls; child lifecycle stays with the host.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\cli\WorkerCli.psm1") -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-onboard-" + [guid]::NewGuid().ToString("N"))
    $script:codexHome = Join-Path $script:testRoot "codex-home"
    New-Item -ItemType Directory -Path $script:codexHome -Force | Out-Null

    $script:workerId = "deepseek-v4-flash"
    $script:profileId = "onboard-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $script:secret = "sk-onboard-" + [guid]::NewGuid().ToString("N")
    $script:baseUrl = "https://nexus.example.com/v1"
    $script:modelId = "deepseek-v4-flash-response"

    $env:RELAY_CREDENTIAL_SCOPE = "Process"

    function Invoke-Cli {
        param([string[]]$Tokens)
        $out = (& { $code = Invoke-WorkerCommand -Tokens $Tokens; "EXIT=$code" } 6>&1 | Out-String)
        $exitMatch = [regex]::Match($out, "EXIT=(\d+)\s*$")
        return [pscustomobject]@{
            ExitCode = [int]$exitMatch.Groups[1].Value
            Json = (($out -replace "EXIT=\d+\s*$", "").Trim() | ConvertFrom-Json)
            Raw = $out
        }
    }

    function Send-StdinSecret {
        param([string]$Value)
        $reader = [System.IO.StringReader]::new($Value)
        [Console]::SetIn($reader)
        return $reader
    }
}

AfterAll {
    Remove-Item Env:\RELAY_CREDENTIAL_SCOPE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "P0-E scenario 1: brand-new user configures a worker from three inputs only" {
    It "step 1: fresh worker reports needs-config with the exact missing fields" {
        $r = Invoke-Cli -Tokens @("status", $script:workerId, "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $r.Json.status | Should -Be "needs-config"
        @($r.Json.missing) | Should -Contain "base_url"
        @($r.Json.missing) | Should -Contain "model_id"
        @($r.Json.missing) | Should -Contain "credential"
    }

    It "step 2: configure with only Base URL + Model ID + API Key (stdin) succeeds" {
        $reader = Send-StdinSecret -Value $script:secret
        try {
            $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId, "--base-url", $script:baseUrl, "--model", $script:modelId, "--api-key-stdin", "--non-interactive", "--json", "--codex-home", $script:codexHome)
        }
        finally { $reader.Dispose() }
        $r.ExitCode | Should -Be 0
        $r.Json.status | Should -Be "configured"
        $r.Json.credential.present | Should -BeTrue
        $r.Json.readiness | Should -Be "ready"
        $r.Raw | Should -Not -Match [regex]::Escape($script:secret)
    }

    It "step 3: doctor reports ready with zero paid calls" {
        $r = Invoke-Cli -Tokens @("doctor", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $r.Json.status | Should -Be "ready"
        $r.Json.paid_call_performed | Should -BeFalse
        $r.Json.next_action | Should -Be "dispatch"
    }

    It "step 4: dispatch is ready and carries the configured identity" {
        $r = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome, "--", "review this repo read-only")
        $r.ExitCode | Should -Be 0
        $r.Json.status | Should -Be "dispatch-ready"
        $r.Json.provider_alias | Should -Be "deepseek"
        $r.Json.model_id | Should -Be $script:modelId
        $r.Json.execution | Should -Match "spawn_agent"
    }

    It "step 5: uninstall --profile returns the worker to needs-config (clean lifecycle)" {
        $r = Invoke-Cli -Tokens @("uninstall", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $r2 = Invoke-Cli -Tokens @("status", $script:workerId, "--json", "--codex-home", $script:codexHome)
        $r2.Json.status | Should -Be "needs-config"
        # 卸载后 credential 也被清除（Process scope 验证）
        $r3 = Invoke-Cli -Tokens @("credential", "status", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome)
        $r3.ExitCode | Should -Be 1
        $r3.Json.error.code | Should -Be "PROFILE_NOT_FOUND"
    }
}

Describe "P0-E scenario 2: existing profile, model swap without re-entering the key" {
    BeforeAll {
        # 先配置好基础 profile（场景 1 的 step 5 已卸载，重新配置）
        $reader = Send-StdinSecret -Value $script:secret
        try {
            $null = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId, "--base-url", $script:baseUrl, "--model", $script:modelId, "--api-key-stdin", "--non-interactive", "--json", "--codex-home", $script:codexHome)
        }
        finally { $reader.Dispose() }
    }

    It "step 1: model swap uses --keep-credential and never asks for the key again" {
        $newModel = "deepseek-v4-flash-response-r2"
        $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId, "--model", $newModel, "--keep-credential", "--non-interactive", "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $r.Json.status | Should -Be "configured"
        $r.Json.model_id | Should -Be $newModel
        $r.Json.credential.present | Should -BeTrue
        $r.Raw | Should -Not -Match [regex]::Escape($script:secret)
    }

    It "step 2: doctor still ready after the swap" {
        $r = Invoke-Cli -Tokens @("doctor", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome)
        $r.Json.status | Should -Be "ready"
    }

    It "step 3: dispatch uses the new model id" {
        $r = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--profile", $script:profileId, "--json", "--codex-home", $script:codexHome, "--", "check the diff")
        $r.Json.status | Should -Be "dispatch-ready"
        $r.Json.model_id | Should -Be "deepseek-v4-flash-response-r2"
    }
}
