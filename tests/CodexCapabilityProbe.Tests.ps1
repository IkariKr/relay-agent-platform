# CodexCapabilityProbe.Tests.ps1 — CodeX/Codex capability probe 契约测试（CP-*）。
# Contract tests for the CodeX capability probe (CP-HOST/CP-AGENT/CP-PROV/CP-ISO/CP-HOOK/CP-LIFE/CP-MSG).
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\hosts\codex\Doctor.psm1") -Force
}

Describe "CP-HOST-001: host/build/Codex version are recorded" {
    It "records codex cli version and host identity without any paid call" {
        $result = Get-CodexCapabilityProbeResult
        $result.codex.cli_version | Should -Not -BeNullOrEmpty
        $result.host.name | Should -BeIn @("win32", "linux", "macos", "unknown")
        $result.host.pwsh_version | Should -Not -BeNullOrEmpty
        $result.probe_schema_version | Should -Be "1.0"
    }
}

Describe "CP-AGENT/CP-PROV/CP-ISO/CP-HOOK/CP-LIFE/CP-MSG: fail-closed status semantics" {
    It "every capability carries a valid status and a detail string" {
        $result = Get-CodexCapabilityProbeResult
        foreach ($key in $result.capabilities.Keys) {
            $cap = $result.capabilities[$key]
            $cap.status | Should -BeIn @("supported", "unsupported", "blocked", "unknown")
            $cap.detail | Should -Not -BeNullOrEmpty
        }
    }
    It "live-host behaviors are unknown offline and never fake supported (CP-ISO/CP-HOOK-002/CP-LIFE/CP-MSG)" {
        $result = Get-CodexCapabilityProbeResult
        foreach ($key in @("custom_agent_spawn", "fork_isolation", "hook_additional_context", "native_wait_callback", "native_cancel", "plaintext_initial_message", "plaintext_followup_message")) {
            $result.capabilities[$key].status | Should -Be "unknown"
        }
    }
    It "config structure probe reports config.toml discovery (CP-AGENT-001/CP-PROV-001)" {
        $config = Test-CodexConfigStructure
        $config.path | Should -Not -BeNullOrEmpty
        $config.exists | Should -BeOfType [bool]
    }
}

Describe "Doctor: available vs blocking capabilities" {
    It "prints a fail-closed verdict listing blocking capabilities" {
        $result = Get-CodexCapabilityProbeResult
        $report = Get-CodexCapabilityReport -ProbeResult $result
        $report | Should -Match "VERDICT: native-provider NOT ready"
        $report | Should -Match "custom_agent_spawn"
        $report | Should -Match "No third-party paid call was made"
    }
    It "evidence path follows <date>-codex-<version>-<host>.json" {
        $path = Get-CodexCapabilityEvidencePath -Root (Join-Path ([System.IO.Path]::GetTempPath()) "relay-evidence")
        $path | Should -Match "codex-.*-win32\.json$"
    }
}

Describe "live verification evidence flips demonstrated capabilities to supported" {
    It "custom_agent_spawn / native_wait_callback / native_cancel / plaintext are supported when B4 evidence exists" {
        $evidenceDir = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-evidence-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
        try {
            # 最小 live evidence 占位（结构上匹配 b4-native-child-*.jsonl 命名）
            '{"type":"turn.started"}' | Set-Content -LiteralPath (Join-Path $evidenceDir "b4-native-child-20260814.jsonl") -Encoding utf8
            $result = Get-CodexCapabilityProbeResult -LiveEvidenceDir $evidenceDir
            $result.capabilities.custom_agent_spawn.status | Should -Be "supported"
            $result.capabilities.native_wait_callback.status | Should -Be "supported"
            $result.capabilities.native_cancel.status | Should -Be "supported"
            $result.capabilities.plaintext_initial_message.status | Should -Be "supported"
            $result.capabilities.custom_agent_spawn.evidence | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -LiteralPath $evidenceDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    It "without live evidence the same capabilities stay unknown (fail-closed offline)" {
        $result = Get-CodexCapabilityProbeResult -LiveEvidenceDir (Join-Path ([System.IO.Path]::GetTempPath()) "relay-no-evidence-nowhere")
        $result.capabilities.custom_agent_spawn.status | Should -Be "unknown"
        $result.capabilities.native_cancel.status | Should -Be "unknown"
    }
}

Describe "Invoke-CapabilityProbe writes a schema-shaped evidence artifact" {
    It "persists probe JSON with version, host, codex and fail-closed capabilities" {
        $out = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-evidence-" + [guid]::NewGuid().ToString("N") + ".json")
        try {
            $result = Invoke-CapabilityProbe -OutputPath $out
            (Test-Path -LiteralPath $out) | Should -BeTrue
            $loaded = Get-Content -Raw -LiteralPath $out | ConvertFrom-Json
            $loaded.probe_schema_version | Should -Be "1.0"
            $loaded.generated_at | Should -Not -BeNullOrEmpty
            $loaded.codex.cli_version | Should -Not -BeNullOrEmpty
            $loaded.capabilities.custom_agent_spawn.status | Should -Be "unknown"
        }
        finally {
            Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        }
    }
}
