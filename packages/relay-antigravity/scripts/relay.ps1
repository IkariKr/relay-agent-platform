# scripts/relay.ps1 — Relay canonical entrypoint（Thin Relay v2 SOP §4.0）。
# Canonical parser/dispatcher; run/route/doctor 子命令面。安装包内的 relay.cmd / PATH shim
# 只负责定位并调用本脚本，不得复制执行逻辑。
#
# 不使用 param()/CmdletBinding：PowerShell 参数绑定会吞掉 `--` 分隔符并拒绝
# `--passthrough <token>` 的重复消费语义；裸 $args 原样保留全部 token，由本脚本手动解析。
# No param()/CmdletBinding: PowerShell binding strips the `--` separator and cannot
# express repeated `--passthrough <token>` consumption; raw $args preserves every
# token and this script parses them manually.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\shared\scripts\ThinRelay.psm1"
Import-Module $modulePath -Force

function Get-RelayOptionValue {
    # 解析 `--flag=value` 或 `--flag value`；越界或缺值给出 Relay 层明确错误。
    # Supports both --flag=value and --flag value; out-of-range/missing value
    # raises a clear Relay-layer error.
    param(
        [Parameter(Mandatory = $true)][string[]]$Tokens,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][string]$Flag
    )

    $token = $Tokens[$Index.Value]
    $eqPos = $token.IndexOf("=")
    if ($eqPos -ge 0) {
        return $token.Substring($eqPos + 1)
    }

    $Index.Value = $Index.Value + 1
    if ($Index.Value -ge $Tokens.Count) {
        throw "relay: option '$Flag' requires a value"
    }
    return $Tokens[$Index.Value]
}

if ($args.Count -lt 1) {
    throw "relay: a command is required (run | route | doctor)"
}
$command = $args[0]
if ($command -notin @("run", "route", "doctor")) {
    throw "relay: unknown command '$command' (supported: run, route, doctor)"
}
$rest = @()
if ($args.Count -gt 1) {
    # 避免 if 语句输出把单元素数组解包成标量，先构造数组再整体赋值。
    # Avoid the if-statement unwrapping a single-element array into a scalar.
    $slice = $args[1..($args.Count - 1)]
    $rest = @($slice)
}

$backend = ""
$model = ""
$agent = ""
$workdir = (Get-Location).Path
$logDir = ""
$dryRun = $false
$passThrough = New-Object System.Collections.Generic.List[string]
$prompt = ""
$afterSeparator = $false

$i = 0
:parse while ($i -lt $rest.Count) {
    $token = $rest[$i]
    if ($afterSeparator) {
        # `--` 之后的所有 token 原样拼接为 prompt。
        # Everything after `--` is joined verbatim as the prompt.
        $prompt = ($rest[$i..($rest.Count - 1)] -join " ")
        break
    }

    switch -Regex ($token) {
        "^--$" { $afterSeparator = $true }
        "^(--backend|-b)$" { $backend = Get-RelayOptionValue -Tokens $rest -Index ([ref]$i) -Flag $token }
        "^(--model|-m)$" { $model = Get-RelayOptionValue -Tokens $rest -Index ([ref]$i) -Flag $token }
        "^(--agent|-a)$" { $agent = Get-RelayOptionValue -Tokens $rest -Index ([ref]$i) -Flag $token }
        "^(--workdir|-w)$" { $workdir = Get-RelayOptionValue -Tokens $rest -Index ([ref]$i) -Flag $token }
        "^(--log-dir)$" { $logDir = Get-RelayOptionValue -Tokens $rest -Index ([ref]$i) -Flag $token }
        "^--dry-run$" { $dryRun = $true }
        "^(--passthrough)$" {
            $i = $i + 1
            if ($i -ge $rest.Count) { throw "relay: option '--passthrough' requires a value" }
            $passThrough.Add($rest[$i])
        }
        default {
            # PowerShell 在 & 调用脚本时会剥掉 `--` 分隔符（-File 调用则保留）；
            # 因此裸 token 一律视为 prompt 起点，兼容两种调用方式。仍以 `--` 开头但
            # 未识别的 token 视为参数错误，避免把误拼选项静默吞进 prompt。
            # PowerShell strips the `--` separator when a script is invoked via &,
            # so a bare token is treated as the start of the prompt to support both
            # invocation styles. Unrecognized dash-prefixed tokens still error out.
            if ($token -match "^[-/]") { throw "relay: unknown argument '$token'" }
            $prompt = ($rest[$i..($rest.Count - 1)] -join " ")
            break parse
        }
    }
    $i = $i + 1
}

$validBackends = @("opencode", "claude", "antigravity")

switch ($command) {
    "run" {
        if (-not $backend) {
            throw "relay: '--backend' is required for 'relay run' (use 'relay route run' for automatic selection; 'auto' is not a valid backend for run)"
        }
        if ($validBackends -notcontains $backend) {
            throw "relay: unknown backend '$backend' (supported: opencode, claude, antigravity)"
        }
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            throw "relay: a prompt is required after '--'"
        }
        Invoke-ThinRelay -Backend $backend -Prompt $prompt -Workdir $workdir -Model $model -Agent $agent -PassThrough @($passThrough) -LogDir $logDir -DryRun:$dryRun
        exit (Get-ThinRelayLastExitCode)
    }
    "doctor" {
        # 基础 CLI 可用性报告（Phase 1）；native-provider doctor 由 Worker/Host 层扩展。
        # Basic CLI availability report (Phase 1); native-provider doctor is
        # extended by the Worker/Host layer.
        if (-not $backend) {
            throw "relay: '--backend' is required for 'relay doctor'"
        }
        if ($validBackends -notcontains $backend) {
            throw "relay: unknown backend '$backend' (supported: opencode, claude, antigravity)"
        }
        $commandName = Get-ThinRelayCommand -Backend $backend
        $resolved = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -eq $resolved) {
            Write-Host "doctor: backend '$backend' requires '$commandName' on PATH - NOT FOUND"
            exit 1
        }
        Write-Host "doctor: backend '$backend' OK - $($resolved.Source)"
        exit 0
    }
    "route" {
        throw "relay: 'route' is not implemented yet (planned for Thin Relay v2 SOP Phase 2)"
    }
}
