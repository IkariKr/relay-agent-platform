# stub-cli.ps1 — 确定性 fake backend CLI，供 Thin Relay 进程契约测试使用。
# stub-cli.ps1 — deterministic fake backend CLI for Thin Relay process contract tests.
#
# 行为由 STUB_* 环境变量控制 / Behavior is controlled via STUB_* env vars:
#   STUB_EXIT_CODE    - 进程退出码，默认 0 / process exit code, default 0
#   STUB_STDOUT_LINE  - 写入 stdout 的一行，默认 "stub stdout" / line written to stdout, default "stub stdout"
#   STUB_STDERR_LINE  - 写入 stderr 的一行，默认 "stub stderr" / line written to stderr, default "stub stderr"
#   STUB_SLEEP_MS     - 写 stdout 后、写 stderr 前睡眠毫秒数（实时 mirror 测试用）
#                       sleep ms between stdout and stderr writes (used by the realtime-mirror test)
#   STUB_COUNT_FILE   - 每次调用追加一行（单次调用断言用）/ append a line per invocation (once-only assertion)
#   STUB_ARGS_FILE    - 收到参数的快照 / snapshot of received arguments
$ErrorActionPreference = "Stop"

if ($env:STUB_ARGS_FILE) {
    ($args -join "`n") | Set-Content -LiteralPath $env:STUB_ARGS_FILE -Encoding utf8
}
if ($env:STUB_COUNT_FILE) {
    Add-Content -LiteralPath $env:STUB_COUNT_FILE -Value (Get-Date -Format o)
}

$stdoutLine = if ($env:STUB_STDOUT_LINE) { $env:STUB_STDOUT_LINE } else { "stub stdout" }
$stderrLine = if ($env:STUB_STDERR_LINE) { $env:STUB_STDERR_LINE } else { "stub stderr" }
$sleepMs = 0
if ($env:STUB_SLEEP_MS) { [int]$sleepMs = $env:STUB_SLEEP_MS }

Write-Output $stdoutLine
if ($sleepMs -gt 0) { Start-Sleep -Milliseconds $sleepMs }
[Console]::Error.WriteLine($stderrLine)

$exitCode = 0
if ($env:STUB_EXIT_CODE) { [int]$exitCode = $env:STUB_EXIT_CODE }
exit $exitCode
