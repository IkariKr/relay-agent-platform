# ThinRelay.Contract.Tests.ps1 — Thin Relay 命令构造/配置优先级/dry-run/脱敏契约测试。
# Deterministic command-construction contract tests (TR-CMD-* / TR-CFG-* / TR-DRY-* / TR-SEC-*).
# 运行方式 / run:  Invoke-Pester -Path ./tests/ThinRelay.Contract.Tests.ps1
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot "shared\scripts\ThinRelay.psm1"
    Import-Module $modulePath -Force

    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-contract-" + [guid]::NewGuid().ToString("N"))
    $script:workdir = Join-Path $testRoot "ws"
    New-Item -ItemType Directory -Path (Join-Path $script:workdir ".relay-agent\backends") -Force | Out-Null
}

AfterAll {
    Remove-Item -LiteralPath (Split-Path -Parent $script:workdir) -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "TR-CMD-001: explicit model/agent/prompt produce expected native commands" {
    It "opencode" {
        $inv = New-ThinRelayInvocation -Backend opencode -Prompt "p" -Workdir $script:workdir -Model "m" -Agent "a"
        $inv.Command | Should -Be "opencode"
        ($inv.Arguments -join " ") | Should -Be ("run --dir $script:workdir --model m --agent a -- p")
    }
    It "claude" {
        $inv = New-ThinRelayInvocation -Backend claude -Prompt "p" -Workdir $script:workdir -Model "m" -Agent "a"
        $inv.Command | Should -Be "claude"
        ($inv.Arguments -join " ") | Should -Be ("--print --model m --agent a p")
    }
    It "antigravity" {
        $inv = New-ThinRelayInvocation -Backend antigravity -Prompt "p" -Workdir $script:workdir -Model "m" -Agent "a"
        $inv.Command | Should -Be "agy"
        ($inv.Arguments -join " ") | Should -Be ("--model m --agent a --add-dir $script:workdir --print p")
    }
}

Describe "TR-CMD-002: passthrough keeps order, sits before the prompt separator, same-name tokens are not re-interpreted" {
    It "opencode passthrough order" {
        $inv = New-ThinRelayInvocation -Backend opencode -Prompt "p" -Workdir $script:workdir -Model "m" -Agent "a" -PassThrough @("--model", "native-model", "--format", "json")
        ($inv.Arguments -join " ") | Should -Be ("run --dir $script:workdir --model m --agent a --model native-model --format json -- p")
    }
    It "claude passthrough order (no separator)" {
        $inv = New-ThinRelayInvocation -Backend claude -Prompt "p" -Workdir $script:workdir -PassThrough @("--permission-mode", "default")
        ($inv.Arguments -join " ") | Should -Be ("--print --permission-mode default p")
    }
}

Describe "TR-CFG-001: config only fills missing values; CLI args win" {
    BeforeEach {
        $script:cfgPath = Join-Path $script:workdir ".relay-agent\backends\opencode.json"
        @{ default_model = "cfg-model"; default_agent = "cfg-agent"; default_passthrough = @("--tui") } |
            ConvertTo-Json | Set-Content -LiteralPath $script:cfgPath -Encoding utf8
    }
    AfterEach {
        Remove-Item -LiteralPath $script:cfgPath -Force -ErrorAction SilentlyContinue
    }
    It "applies workspace defaults when CLI args are missing" {
        $output = (Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir -DryRun 6>&1 | Out-String)
        $escapedConfigPath = [regex]::Escape($script:cfgPath)
        $output | Should -Match "cfg-model"
        $output | Should -Match "cfg-agent"
        $output | Should -Match "--tui"
        $output | Should -Match $escapedConfigPath
    }
    It "CLI args override workspace defaults" {
        $output = (Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir -DryRun -Model "cli-model" -Agent "cli-agent" 6>&1 | Out-String)
        $output | Should -Match "cli-model \(command line\)"
        $output | Should -Match "cli-agent \(command line\)"
        $output | Should -Not -Match "cfg-model"
    }
}

Describe "TR-DRY-001: dry-run does not resolve or start the backend CLI" {
    It "succeeds even when no backend CLI is on PATH" {
        $originalPath = $env:PATH
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-empty-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        try {
            $env:PATH = $emptyDir
            { Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir -DryRun 6>&1 | Out-Null } | Should -Not -Throw
            Get-ThinRelayLastExitCode | Should -Be 0
        }
        finally {
            $env:PATH = $originalPath
            Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-SEC-001: token-aware redaction of display/log commands" {
    It "redacts inline key=value" {
        $inv = New-ThinRelayInvocation -Backend opencode -Prompt "p" -Workdir $script:workdir -PassThrough @("--api-key=sk-123")
        $inv.DisplayCommand | Should -Not -Match "sk-123"
        $inv.DisplayCommand | Should -Match "--api-key=<redacted>"
    }
    It "redacts separated secret flag values" {
        $inv = New-ThinRelayInvocation -Backend claude -Prompt "p" -Workdir $script:workdir -PassThrough @("--api-key", "sk-secret", "--token", "tok-value")
        $inv.DisplayCommand | Should -Not -Match "sk-secret"
        $inv.DisplayCommand | Should -Not -Match "tok-value"
        $inv.DisplayCommand | Should -Match "--api-key <redacted> --token <redacted>"
    }
    It "redacts password forms" {
        $inv = New-ThinRelayInvocation -Backend antigravity -Prompt "p" -Workdir $script:workdir -PassThrough @("--password", "pw-value")
        $inv.DisplayCommand | Should -Not -Match "pw-value"
        $inv.DisplayCommand | Should -Match "--password <redacted>"
    }
    It "redacts Authorization/Bearer header token" {
        $inv = New-ThinRelayInvocation -Backend opencode -Prompt "p" -Workdir $script:workdir -PassThrough @("--header", "Authorization: Bearer abc.def")
        $inv.DisplayCommand | Should -Not -Match "abc"
    }
    It "keeps non-secret values and quotes tokens with whitespace" {
        $inv = New-ThinRelayInvocation -Backend opencode -Prompt "p" -Workdir $script:workdir -Model "gpt-5" -PassThrough @("--format", "json")
        $inv.DisplayCommand | Should -Match "gpt-5"
        $inv.DisplayCommand | Should -Match "--format json"
    }
}
