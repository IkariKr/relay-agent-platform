# scripts/test.ps1 — unified deterministic test runner (next-steps P0-3).
# 所有 deterministic suite 的唯一入口：native-provider、external-cli、host adapter、
# dispatch、registry 均由此运行；CI 与 release checklist 必须调用本脚本。
# Single entry point for the deterministic suite; CI and the release checklist must
# call this script so evidence is reproducible from one command.
#
# 用法 / usage:
#   pwsh -NoProfile -File ./scripts/test.ps1                  # full suite
#   pwsh -NoProfile -File ./scripts/test.ps1 -Path tests/WorkerRegistry.Tests.ps1
#   pwsh -NoProfile -File ./scripts/test.ps1 -ExportEvidence  # also write evidence json
#
# 退出码 / exit code: 0 = all passed, 1 = any failure (or environment error).
param(
    [string]$Path = "",
    [switch]$ExportEvidence,
    [string]$EvidenceDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Write-ErrorExit {
    param([string]$Message)
    [Console]::Error.WriteLine("test.ps1: $Message")
    exit 1
}

# --- 1. PowerShell host check (Pester 6 requires PowerShell 7.2+) -----------------
$psMajor = $PSVersionTable.PSVersion.Major
$psMinor = $PSVersionTable.PSVersion.Minor
if ($psMajor -lt 7 -or ($psMajor -eq 7 -and $psMinor -lt 2)) {
    Write-ErrorExit "PowerShell $($PSVersionTable.PSVersion) is not supported; run this runner with pwsh 7.2+ (pwsh -NoProfile -File ./scripts/test.ps1)"
}

# --- 2. Pester version gate (locked contract: >=5 <7) -----------------------------
Import-Module Pester -ErrorAction Stop
$pesterVersion = [version](Get-Module Pester).Version
if ($pesterVersion -lt [version]"5.0.0" -or $pesterVersion -ge [version]"7.0.0") {
    Write-ErrorExit "Pester $pesterVersion is outside the locked contract (>=5 <7). Install a supported version, e.g.: pwsh -NoProfile -Command 'Install-Module Pester -RequiredVersion 6.1.0 -Scope CurrentUser -Force'"
}

# --- 3. Discover test files ---------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path $repoRoot "tests\*.Tests.ps1"
}
if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = Join-Path $repoRoot $Path
}

# --- 4. Best-effort Codex build identity (non-blocking; recorded in evidence) ------
$codexVersion = $null
if ($env:CODEX_VERSION) {
    $codexVersion = $env:CODEX_VERSION
} else {
    try {
        $codexVersion = (codex --version 2>$null | Select-Object -First 1).Trim()
    } catch { $codexVersion = $null }
}

# --- 5. Run the suite ----------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$result = Invoke-Pester -Path $Path -PassThru
$stopwatch.Stop()

# --- 6. Report ------------------------------------------------------------------------
$failed = @($result.Failed)
Write-Output ""
Write-Output ("Test run: {0}" -f $(if ($Path -like "*\*.Tests.ps1") { "full suite" } else { $Path }))
Write-Output ("PowerShell: {0}  Pester: {1}  OS: {2}" -f $PSVersionTable.PSVersion, $pesterVersion, [System.Environment]::OSVersion.VersionString)
if ($codexVersion) { Write-Output ("Codex: {0}" -f $codexVersion) }
Write-Output ("Passed: {0}  Failed: {1}  Skipped: {2}  Total: {3}  Duration: {4:0.0}s" -f $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.TotalCount, $stopwatch.Elapsed.TotalSeconds)

if ($failed.Count -gt 0) {
    Write-Output ""
    Write-Output "Failed tests:"
    foreach ($t in $failed) {
        $err = if ($t.ErrorRecord) { $t.ErrorRecord.Exception.Message } else { "unknown error" }
        Write-Output ("  FAIL {0} :: {1} :: {2}" -f $t.ExpandedPath, $t.Name, $err)
    }
    exit 1
}

# --- 7. Optional evidence artifact -----------------------------------------------------
if ($ExportEvidence) {
    if ([string]::IsNullOrWhiteSpace($EvidenceDir)) {
        $EvidenceDir = Join-Path $repoRoot "docs\evidence\test-run"
    }
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
    $evidence = [ordered]@{
        schema_version = "1.0"
        generated_at   = (Get-Date).ToUniversalTime().ToString("o")
        runner         = "scripts/test.ps1"
        powershell     = $PSVersionTable.PSVersion.ToString()
        pester         = $pesterVersion.ToString()
        os             = [System.Environment]::OSVersion.VersionString
        codex          = $codexVersion
        path           = $Path
        total          = $result.TotalCount
        passed         = $result.PassedCount
        failed         = $result.FailedCount
        skipped        = $result.SkippedCount
        duration_ms    = [int]$stopwatch.Elapsed.TotalMilliseconds
    }
    $file = Join-Path $EvidenceDir ((Get-Date).ToString("yyyyMMdd-HHmmss") + "-test-run.json")
    $evidence | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $file -Encoding utf8
    Write-Output ("Evidence: {0}" -f $file)
}

exit 0
