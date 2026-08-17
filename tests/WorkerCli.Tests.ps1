# WorkerCli.Tests.ps1 — `relay worker` CLI 合同测试（NP-CLI-* / NP-CRED-003）。
# Contract tests for the worker command surface. All runs use a temporary
# CODEX_HOME and Process-scope credentials so the user environment is untouched;
# no paid calls are made.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\cli\WorkerCli.psm1") -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-cli-" + [guid]::NewGuid().ToString("N"))
    $script:codexHome = Join-Path $script:testRoot "codex-home"
    New-Item -ItemType Directory -Path $script:codexHome -Force | Out-Null

    $script:workerId = "deepseek-v4-flash"
    $script:profileId = "cli-profile-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    $script:secret = "sk-cli-test-" + [guid]::NewGuid().ToString("N")

    # credential 写入 Process 作用域，绝不污染用户环境
    $env:RELAY_CREDENTIAL_SCOPE = "Process"

    # 辅助函数必须定义在 BeforeAll（run 作用域）内；Pester 6 中 discovery 阶段的
    # 顶层定义在 run 阶段不可见。Helper functions must live in BeforeAll (run scope);
    # Pester 6 separates discovery scope from run scope.
    function Invoke-Cli {
        param([string[]]$Tokens)
        # 捕获 Write-Host（information stream）作为命令输出；返回 exit code。
        $out = (& { $code = Invoke-WorkerCommand -Tokens $Tokens; "EXIT=$code" } 6>&1 | Out-String)
        $exitMatch = [regex]::Match($out, "EXIT=(\d+)\s*$")
        return [pscustomobject]@{
            ExitCode = [int]$exitMatch.Groups[1].Value
            Output = $out
        }
    }

    function ConvertFrom-CliJson {
        param([string]$Output)
        $jsonLine = ($Output -replace "EXIT=\d+\s*$", "").Trim()
        return ($jsonLine | ConvertFrom-Json)
    }
}

AfterAll {
    Remove-Item Env:\RELAY_CREDENTIAL_SCOPE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "NP-CLI: worker command surface with --json contract" {
    It "NP-CLI-001: list --json shows both runtimes with stable fields" {
        $r = Invoke-Cli -Tokens @("list", "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $workers = @($json.workers)
        $workers.Count | Should -BeGreaterThan 0
        $native = @($workers | Where-Object { $_.worker_id -eq $script:workerId })[0]
        $native.runtime_type | Should -Be "native-provider"
        $native.status | Should -Be "needs-config"
        @($workers | Where-Object { $_.runtime_type -eq "external-cli" }).Count | Should -BeGreaterThan 0
    }

    It "NP-CLI-002: configure without fields returns stable machine status + missing list (no prompt)" {
        $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId,
            "--non-interactive", "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "needs-config"
        @($json.missing) | Should -Contain "base_url"
        @($json.missing) | Should -Contain "model_id"
        $json.next_action | Should -Be "configure"
    }

    It "NP-CLI-003: non-interactive mode never prompts (fast return, no hang)" {
        # 若实现偷偷 prompt，该测试会挂起；快速返回即通过
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--non-interactive", "--json",
            "--codex-home", $script:codexHome)
        $sw.Stop()
        $sw.Elapsed.TotalSeconds | Should -BeLessThan 10
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "needs-config"
    }

    It "NP-CRED-003: api-key with an inline value is rejected (never exists as a CLI option)" {
        # 测试名避免 <...>：Pester 6 会把 It 名称中的尖括号当参数化占位符展开
        { Invoke-Cli -Tokens @("configure", $script:workerId, "--api-key", "sk-forbidden",
            "--json", "--codex-home", $script:codexHome) } | Should -Throw "*--api-key <value> is forbidden*"
    }

    It "NP-CRED-007: api-key equals syntax is rejected without echoing the secret" {
        $inlineSecret = "sk-inline-" + [guid]::NewGuid().ToString("N")
        $message = ""
        try {
            Invoke-Cli -Tokens @("configure", $script:workerId, "--api-key=$inlineSecret",
                "--json", "--codex-home", $script:codexHome) | Out-Null
            throw "expected forbidden api-key syntax to fail"
        }
        catch {
            $message = $_.Exception.Message
        }
        $message | Should -Match "--api-key <value> is forbidden"
        $message | Should -Not -Match [regex]::Escape($inlineSecret)
    }

    It "NP-CRED-008: unknown option errors never echo an equals-suffixed value" {
        $sensitiveValue = "sensitive-sentinel-" + [guid]::NewGuid().ToString("N")
        $message = ""
        try {
            Invoke-Cli -Tokens @("configure", $script:workerId, "--apikey=$sensitiveValue",
                "--json", "--codex-home", $script:codexHome) | Out-Null
            throw "expected unknown option to fail"
        }
        catch {
            $message = $_.Exception.Message
        }
        $message | Should -Match "unknown option"
        $message | Should -Not -Match [regex]::Escape($sensitiveValue)
        $message | Should -Not -Match "--apikey="
    }

    It "NP-CLI-006: doctor reports a missing worker manifest instead of claiming ok" {
        $r = Invoke-Cli -Tokens @("doctor", "no-such-worker", "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "worker-not-found"
        $json.error_code | Should -Be "WORKER_NOT_FOUND"
        $json.checks.worker_manifest | Should -Be "missing"
    }

    It "NP-CLI-007: multiple profiles require explicit selection and dispatch fails closed" {
        $profile1 = "multi-a-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
        $profile2 = "multi-b-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
        foreach ($profile in @($profile1, $profile2)) {
            $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $profile,
                "--base-url", "https://gateway.example.com/v1", "--model", "deepseek-v4-flash-response",
                "--non-interactive", "--json", "--codex-home", $script:codexHome)
            $r.ExitCode | Should -Be 0
        }
        try {
            $status = Invoke-Cli -Tokens @("status", $script:workerId, "--json", "--codex-home", $script:codexHome)
            $statusJson = ConvertFrom-CliJson -Output $status.Output
            $statusJson.status | Should -Be "invalid-config"
            $statusJson.error_code | Should -Be "PROFILE_SELECTION_REQUIRED"
            @($statusJson.profile_ids) | Should -Contain $profile1
            @($statusJson.profile_ids) | Should -Contain $profile2

            $dispatch = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--json", "--codex-home", $script:codexHome, "--", "review")
            $dispatchJson = ConvertFrom-CliJson -Output $dispatch.Output
            $dispatchJson.status | Should -Be "blocked"
            $dispatchJson.error_code | Should -Be "PROFILE_SELECTION_REQUIRED"
        }
        finally {
            foreach ($profile in @($profile1, $profile2)) {
                Invoke-Cli -Tokens @("uninstall", $script:workerId, "--profile", $profile, "--json", "--codex-home", $script:codexHome) | Out-Null
            }
        }
    }

    It "NP-CLI-004: dispatch fails closed before configuration is ready" {
        $r = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--json", "--", "review this code")
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "blocked"
        $json.next_action | Should -Not -BeNullOrEmpty
    }

    It "NP-CLI-005: dispatch respects explicit worker id (unknown worker -> worker-not-found)" {
        $r = Invoke-Cli -Tokens @("dispatch", "no-such-worker", "--json", "--", "task")
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.error_code | Should -Be "WORKER_NOT_FOUND"
        $json.next_action | Should -BeNullOrEmpty
    }
}

Describe "NP-CLI: full configure -> doctor -> dispatch lifecycle (no paid calls)" {
    It "configure with stdin credential configures profile, credential and overlay" {
        $reader = [System.IO.StringReader]::new($script:secret)
        [Console]::SetIn($reader)
        try {
            $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId,
                "--base-url", "https://nexus.example.com/v1", "--model", "deepseek-v4-flash-response",
                "--api-key-stdin", "--non-interactive", "--json", "--codex-home", $script:codexHome)
        }
        finally { $reader.Dispose() }
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "configured"
        $json.profile_id | Should -Be $script:profileId
        $json.credential.present | Should -BeTrue
        $json.paid_call_performed | Should -BeFalse
        # secret 不出现在任何输出
        $r.Output | Should -Not -Match [regex]::Escape($script:secret)
    }

    It "provider alias update keeps profile, overlay and dispatch identity aligned" {
        $r = Invoke-Cli -Tokens @("configure", $script:workerId, "--profile", $script:profileId,
            "--provider-alias", "relay-nexus", "--keep-credential", "--non-interactive", "--json",
            "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.provider_id | Should -Be "relay-nexus"

        $dispatch = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome, "--", "identity check")
        $dispatchJson = ConvertFrom-CliJson -Output $dispatch.Output
        $dispatchJson.provider_alias | Should -Be "relay-nexus"
    }

    It "status --json reports ready when configured with verified host capability" {
        $r = Invoke-Cli -Tokens @("status", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "ready"
        $json.credential.present | Should -BeTrue
        $json.overlay_generated | Should -BeTrue
        $json.next_action | Should -Be "dispatch"
    }

    It "doctor --json reports zero paid calls and full checks" {
        $r = Invoke-Cli -Tokens @("doctor", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.paid_call_performed | Should -BeFalse
        $json.checks.worker_manifest | Should -Be "ok"
        $json.checks.credential | Should -Be "present"
        $json.checks.host_capability | Should -Be "ok"
    }

    It "dispatch --json returns dispatch-ready with the explicit worker/profile" {
        $r = Invoke-Cli -Tokens @("dispatch", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome, "--", "review the repo read-only")
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.status | Should -Be "dispatch-ready"
        $json.worker_id | Should -Be $script:workerId
        $json.profile_id | Should -Be $script:profileId
        $json.runtime_type | Should -Be "native-provider"
        $json.task | Should -Be "review the repo read-only"
        $json.execution | Should -Match "spawn_agent"
    }

    It "credential status/remove cycle works and never leaks the secret" {
        $r = Invoke-Cli -Tokens @("credential", "status", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $json = ConvertFrom-CliJson -Output $r.Output
        $json.present | Should -BeTrue
        $json.source | Should -Match "^env:RELAY_PROVIDER_"
        $r.Output | Should -Not -Match [regex]::Escape($script:secret)

        $r2 = Invoke-Cli -Tokens @("credential", "remove", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $json2 = ConvertFrom-CliJson -Output $r2.Output
        $json2.present | Should -BeFalse

        $r3 = Invoke-Cli -Tokens @("status", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $json3 = ConvertFrom-CliJson -Output $r3.Output
        $json3.status | Should -Be "credential-missing"
        $json3.next_action | Should -Be "credential set"
    }

    It "uninstall --profile removes only that profile's overlay, profile and credential" {
        $r = Invoke-Cli -Tokens @("uninstall", $script:workerId, "--profile", $script:profileId,
            "--json", "--codex-home", $script:codexHome)
        $r.ExitCode | Should -Be 0
        $json = ConvertFrom-CliJson -Output $r.Output
        @($json.removed) | Should -Contain "overlay"
        @($json.removed) | Should -Contain "profile"
        @($json.removed) | Should -Contain "credential"
        # worker 仍在 registry（uninstall 只清 relay state，不删仓库 pack）
        $r2 = Invoke-Cli -Tokens @("show", $script:workerId, "--json", "--codex-home", $script:codexHome)
        $json2 = ConvertFrom-CliJson -Output $r2.Output
        $json2.worker_id | Should -Be $script:workerId
        @($json2.profiles).Count | Should -Be 0
    }
}
