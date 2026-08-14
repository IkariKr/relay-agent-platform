# RelayCli.Tests.ps1 — canonical scripts/relay.ps1 入口契约测试（TR-CLI-*）。
# Contract tests for the canonical scripts/relay.ps1 entrypoint.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:relayScript = Join-Path $repoRoot "scripts\relay.ps1"
    $script:legacyScript = Join-Path $repoRoot "scripts\run_relay.ps1"
    $script:stubDir = Join-Path $PSScriptRoot "fixtures\stub-cli"
    $script:originalPath = $env:PATH
    $env:PATH = "$script:stubDir;$env:PATH"

    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-cli-" + [guid]::NewGuid().ToString("N"))
    $script:workdir = Join-Path $testRoot "ws"
    New-Item -ItemType Directory -Path $script:workdir -Force | Out-Null
}

AfterAll {
    $env:PATH = $script:originalPath
    Remove-Item -LiteralPath (Split-Path -Parent $script:workdir) -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "TR-CLI-001: relay.ps1 run and the legacy wrapper share the same thin core" {
    It "produce identical native commands for equivalent inputs" {
        $relayOut = (& $script:relayScript run --backend opencode --model m --agent a --workdir $script:workdir --dry-run -- "p" 6>&1 | Out-String)
        $legacyOut = (& $script:legacyScript -Backend opencode -Model m -Agent a -Workdir $script:workdir -Prompt "p" -DryRun 6>&1 | Out-String)
        $relayCmd = (($relayOut -split "`n") | Where-Object { $_ -match "^native command:" }) -replace "^native command: ", ""
        $legacyCmd = (($legacyOut -split "`n") | Where-Object { $_ -match "^native command:" }) -replace "^native command: ", ""
        $relayCmd | Should -Be $legacyCmd
        $relayCmd | Should -Match "opencode run --dir $([regex]::Escape($script:workdir)) --model m --agent a -- p"
    }
}

Describe "relay run argument validation" {
    It "requires --backend" {
        { & $script:relayScript run -- "p" } | Should -Throw "*--backend*"
    }
    It "rejects 'auto' as a backend for run" {
        { & $script:relayScript run --backend auto -- "p" } | Should -Throw "*auto*"
    }
    It "requires a prompt after --" {
        { & $script:relayScript run --backend opencode } | Should -Throw "*prompt*"
    }
    It "rejects unknown arguments" {
        { & $script:relayScript run --backend opencode --bogus -- "p" } | Should -Throw "*unknown argument*"
    }
}

Describe "relay run passthrough parsing" {
    It "consumes each --passthrough token and places them before the prompt separator" {
        $out = (& $script:relayScript run --backend opencode --workdir $script:workdir --dry-run --passthrough --model --passthrough --format --passthrough json -- "p" 6>&1 | Out-String)
        $out | Should -Match "--model --format json -- p"
    }
}

Describe "relay run executes the backend and propagates the native exit code" {
    It "runs the stub through the canonical entrypoint" {
        $countFile = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-cli-count-" + [guid]::NewGuid().ToString("N") + ".txt")
        $env:STUB_EXIT_CODE = "7"
        $env:STUB_COUNT_FILE = $countFile
        try {
            & $script:relayScript run --backend opencode --workdir $script:workdir -- "p" | Out-Null
            $LASTEXITCODE | Should -Be 7
            @(Get-Content -LiteralPath $countFile).Count | Should -Be 1
        }
        finally {
            Remove-Item Env:\STUB_EXIT_CODE -ErrorAction SilentlyContinue
            Remove-Item Env:\STUB_COUNT_FILE -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $countFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "relay doctor" {
    It "reports backend availability and exits 0 when the CLI is resolvable" {
        $out = (& $script:relayScript doctor --backend opencode 6>&1 | Out-String)
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match "doctor: backend 'opencode' OK"
        $out | Should -Match "stub-cli"
    }
    It "reports NOT FOUND and exits 1 when the CLI is missing" {
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-empty-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $env:PATH = $emptyDir
            $out = (& $script:relayScript doctor --backend claude 6>&1 | Out-String)
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match "NOT FOUND"
        }
        finally {
            $env:PATH = $originalPath
            Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "relay route" {
    BeforeAll {
        $script:routingConfig = Join-Path (Split-Path -Parent $script:workdir) "routing.json"
        @{
            version = 2
            defaults = @{
                preferred_backend = "claude"
                fallback_backends = @("opencode")
                on_no_match = "preferred_backend"
            }
            rules = @(
                @{
                    name = "read-only"
                    backend = "opencode"
                    reason = "read-only review"
                    enabled = $true
                    when = @{ prompt_any_regex = @(".*read.*") }
                }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:routingConfig -Encoding utf8
    }
    It "explain selects the matching rule backend and prints the native command without executing" {
        $out = (& $script:relayScript route explain --auto-config-path $script:routingConfig --workdir $script:workdir -- "read this file" 6>&1 | Out-String)
        $LASTEXITCODE | Should -Be 0
        $out | Should -Match "selected backend: opencode"
        $out | Should -Match "routing rule: read-only"
        $out | Should -Match "native command: opencode run"
    }
    It "explain falls back to the preferred backend when no rule matches" {
        $out = (& $script:relayScript route explain --auto-config-path $script:routingConfig --workdir $script:workdir -- "implement a feature" 6>&1 | Out-String)
        $out | Should -Match "selected backend: claude"
        $out | Should -Match "preferred backend"
    }
    It "run executes the routed backend and propagates its exit code" {
        $env:STUB_EXIT_CODE = "3"
        try {
            & $script:relayScript route run --auto-config-path $script:routingConfig --workdir $script:workdir -- "read this file" | Out-Null
            $LASTEXITCODE | Should -Be 3
        }
        finally {
            Remove-Item Env:\STUB_EXIT_CODE -ErrorAction SilentlyContinue
        }
    }
    It "only selects registered external-cli backends (TR-ROUTE-001)" {
        $badConfig = Join-Path (Split-Path -Parent $script:workdir) "routing-bad.json"
        @{
            version = 2
            defaults = @{
                preferred_backend = "claude"
                fallback_backends = @("opencode")
                on_no_match = "preferred_backend"
            }
            rules = @(
                @{
                    name = "native"
                    backend = "deepseek-v4-flash"
                    when = @{ prompt_any_regex = @(".*") }
                }
            )
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $badConfig -Encoding utf8
        try {
            { & $script:relayScript route explain --auto-config-path $badConfig --workdir $script:workdir -- "anything" } | Should -Throw
        }
        finally {
            Remove-Item -LiteralPath $badConfig -Force -ErrorAction SilentlyContinue
        }
    }
}
