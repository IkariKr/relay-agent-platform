# ThinRelay.Process.Tests.ps1 — Thin Relay 真实进程契约测试（stub CLI 驱动）。
# Deterministic process-contract tests driven by the stub CLI fixture (TR-PROC-* / TR-LOG-* / TR-ONCE-* / TR-GIT-*).
# stub 行为见 tests/fixtures/stub-cli/stub-cli.ps1。
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot "shared\scripts\ThinRelay.psm1"
    Import-Module $modulePath -Force

    $script:stubDir = Join-Path $PSScriptRoot "fixtures\stub-cli"
    $script:originalPath = $env:PATH
    $env:PATH = "$script:stubDir;$env:PATH"

    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-proc-" + [guid]::NewGuid().ToString("N"))
    $script:workdir = Join-Path $testRoot "ws"          # 非 Git 工作目录 / non-git workdir
    $script:logdir = Join-Path $testRoot "logs"
    New-Item -ItemType Directory -Path $script:workdir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:logdir -Force | Out-Null
}

AfterAll {
    $env:PATH = $script:originalPath
    Remove-Item -LiteralPath (Split-Path -Parent $script:workdir) -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "TR-PROC-001: stdout/stderr are mirrored into separate log files" {
    It "splits streams and keeps each log free of the other stream" {
        $env:STUB_STDOUT_LINE = "proc-stdout-line"
        $env:STUB_STDERR_LINE = "proc-stderr-line"
        try {
            Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir -LogDir $script:logdir | Out-Null
            Get-ThinRelayLastExitCode | Should -Be 0
            $stdoutLog = Get-ChildItem $script:logdir -Filter "opencode-*.stdout.log" | Sort-Object LastWriteTime | Select-Object -Last 1
            $stderrLog = Get-ChildItem $script:logdir -Filter "opencode-*.stderr.log" | Sort-Object LastWriteTime | Select-Object -Last 1
            $stdoutLog | Should -Not -BeNullOrEmpty
            $stderrLog | Should -Not -BeNullOrEmpty
            (Get-Content -LiteralPath $stdoutLog.FullName -Raw) | Should -Match "proc-stdout-line"
            (Get-Content -LiteralPath $stdoutLog.FullName -Raw) | Should -Not -Match "proc-stderr-line"
            (Get-Content -LiteralPath $stderrLog.FullName -Raw) | Should -Match "proc-stderr-line"
            (Get-Content -LiteralPath $stderrLog.FullName -Raw) | Should -Not -Match "proc-stdout-line"
        }
        finally {
            Remove-Item Env:\STUB_STDOUT_LINE -ErrorAction SilentlyContinue
            Remove-Item Env:\STUB_STDERR_LINE -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-PROC-002: native exit code is returned as-is" {
    It "propagates non-zero exit code through the thin core" {
        $env:STUB_EXIT_CODE = "7"
        try {
            Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir | Out-Null
            Get-ThinRelayLastExitCode | Should -Be 7
        }
        finally {
            Remove-Item Env:\STUB_EXIT_CODE -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-PROC-003: CLI missing raises a clear Relay-layer error" {
    It "throws a Relay error when the backend CLI is not on PATH" {
        $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-empty-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
        $originalPath = $env:PATH
        try {
            $env:PATH = $emptyDir
            { Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir | Out-Null } |
                Should -Throw -ExpectedMessage "*Relay error: backend 'opencode' requires 'opencode'*"
        }
        finally {
            $env:PATH = $originalPath
            Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-LOG-001: --log-dir mirrors stdout while the child is still running" {
    It "realtime line appears before the process exits (no replay after exit)" {
        $env:STUB_STDOUT_LINE = "realtime-line"
        $env:STUB_SLEEP_MS = "3000"
        $job = Start-Job -ScriptBlock {
            param($modulePath, $workdir, $logdir)
            Import-Module $modulePath -Force
            Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $workdir -LogDir $logdir | Out-Null
        } -ArgumentList $modulePath, $script:workdir, $script:logdir
        try {
            $seenWhileRunning = $false
            $deadline = (Get-Date).AddSeconds(2)
            while ((Get-Date) -lt $deadline -and $job.State -eq "Running") {
                $latest = Get-ChildItem $script:logdir -Filter "opencode-*.stdout.log" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime | Select-Object -Last 1
                if ($latest -and (Get-Content -LiteralPath $latest.FullName -Raw -ErrorAction SilentlyContinue) -match "realtime-line") {
                    $seenWhileRunning = $true
                    break
                }
                Start-Sleep -Milliseconds 50
            }
            $seenWhileRunning | Should -BeTrue "stdout log should contain the line while the child is still running"
            $job.State | Should -Be "Running"
        }
        finally {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Remove-Item Env:\STUB_SLEEP_MS -ErrorAction SilentlyContinue
            Remove-Item Env:\STUB_STDOUT_LINE -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-ONCE-001: default execution invokes the backend exactly once" {
    It "no retry, no second invocation" {
        $countFile = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-count-" + [guid]::NewGuid().ToString("N") + ".txt")
        $env:STUB_COUNT_FILE = $countFile
        try {
            Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir | Out-Null
            @(Get-Content -LiteralPath $countFile).Count | Should -Be 1
        }
        finally {
            Remove-Item Env:\STUB_COUNT_FILE -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $countFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-GIT-001: non-git workdir works and Relay does not run git" {
    It "runs fine in a plain directory without .git and records no git invocation" {
        (Test-Path -LiteralPath (Join-Path $script:workdir ".git")) | Should -BeFalse
        $argsFile = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-args-" + [guid]::NewGuid().ToString("N") + ".txt")
        $env:STUB_ARGS_FILE = $argsFile
        try {
            Invoke-ThinRelay -Backend claude -Prompt "p" -Workdir $script:workdir | Out-Null
            Get-ThinRelayLastExitCode | Should -Be 0
            (Get-Content -LiteralPath $argsFile -Raw) | Should -Not -Match "git"
        }
        finally {
            Remove-Item Env:\STUB_ARGS_FILE -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $argsFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "TR-SEC-002: command manifest written by --log-dir is redacted" {
    It "writes a redacted command list alongside the raw logs" {
        $env:STUB_STDOUT_LINE = "manifest-line"
        try {
            Invoke-ThinRelay -Backend opencode -Prompt "p" -Workdir $script:workdir -LogDir $script:logdir -PassThrough @("--api-key", "sk-manifest-secret") | Out-Null
            $commandLog = Get-ChildItem $script:logdir -Filter "opencode-*.command.txt" | Sort-Object LastWriteTime | Select-Object -Last 1
            $commandLog | Should -Not -BeNullOrEmpty
            (Get-Content -LiteralPath $commandLog.FullName -Raw) | Should -Match "opencode"
            (Get-Content -LiteralPath $commandLog.FullName -Raw) | Should -Match "<redacted>"
            (Get-Content -LiteralPath $commandLog.FullName -Raw) | Should -Not -Match "sk-manifest-secret"
        }
        finally {
            Remove-Item Env:\STUB_STDOUT_LINE -ErrorAction SilentlyContinue
        }
    }
}
