Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Worker CLI：`relay worker ...` 命令面的解析、执行与格式化（onboarding plan §3/§12 P0-C）。
# 分层：本模块只做参数解析与模块调用编排，业务逻辑在 profile/credential/generation/
# doctor 模块；输出对象统一从 Invoke-WorkerCommand 格式化。secret 绝不进入任何输出。
# `--api-key <value>` 参数不存在——API Key 只能通过 stdin（--api-key-stdin）或
# masked 交互输入提供。
Import-Module (Join-Path $PSScriptRoot "..\registry\WorkerProfileStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\registry\WorkerPackManager.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\credentials\CredentialStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\generation\CodexProviderConfigGenerator.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\hosts\codex\Doctor.psm1") -Force

$script:TemplatePlaceholders = @("<provider-model-id>", "<responses-compatible-endpoint>", "<model>", "<base_url>", "<model-id>")

# ---------------------------------------------------------------------------
# 错误与状态辅助
# ---------------------------------------------------------------------------

function New-WorkerCliError {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message
    )
    return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = $Code; message = $Message } }
}

function New-WorkerCliSuccess {
    param([Parameter(Mandatory = $true)]$Data)
    return [pscustomobject]@{ ok = $true; data = $Data }
}

function Test-RequiredWorkerCapabilities {
    # fail-closed 能力检查：B4 evidence 驱动的必需能力。offline/无 evidence 一律不算就绪。
    param([Parameter(Mandatory = $true)]$ProbeResult)
    $required = @("custom_agent_spawn", "native_wait_callback", "native_cancel", "plaintext_initial_message")
    $blocking = @()
    $caps = $ProbeResult.capabilities
    foreach ($key in $required) {
        # capabilities 是 OrderedDictionary：用 IDictionary.Contains 检查键
        if (-not $caps.Contains($key)) { $blocking += $key; continue }
        $status = [string]$caps[$key].status
        if ($status -ne "supported") { $blocking += $key }
    }
    return $blocking
}

function Get-RepoEvidenceDir {
    # platform/cli -> platform -> repo root
    $repoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    return (Join-Path $repoRoot "docs\evidence\transport")
}

function Get-NativeProviderReadiness {
    # 组合检查：worker manifest → profile → 配置值 → credential → host capability → overlay。
    # Combined readiness: manifest -> profile -> values -> credential -> host capability -> overlay.
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    try {
        $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId
    }
    catch {
        return [pscustomobject]@{ status = "worker-not-found"; error_code = "WORKER_NOT_FOUND"; blocking = @(); next_action = $null }
    }
    if ([string]$descriptor.runtime_type -ne "native-provider") {
        return [pscustomobject]@{ status = "not-native-provider"; error_code = "NOT_NATIVE_PROVIDER"; blocking = @(); next_action = $null }
    }

    $missing = @()
    $profile = $null
    if ([string]::IsNullOrWhiteSpace($ProfileId)) {
        $profiles = @(Get-ProviderProfiles -WorkerId $WorkerId -CodexHome $CodexHome)
        if ($profiles.Count -eq 0) {
            $missing += @("base_url", "model_id", "credential")
            return [pscustomobject]@{
                status = "needs-config"; error_code = "PROFILE_NOT_FOUND"; worker_id = $WorkerId
                missing = @($missing); blocking = @(); next_action = "configure"
            }
        }
        if ($profiles.Count -gt 1) {
            return [pscustomobject]@{
                status = "invalid-config"; error_code = "PROFILE_SELECTION_REQUIRED"; worker_id = $WorkerId
                profile_ids = @($profiles | ForEach-Object { [string]$_.profile_id } | Sort-Object)
                missing = @("profile"); blocking = @(); next_action = "status --profile"
            }
        }
        $profile = $profiles[0]
    }
    else {
        try { $profile = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome }
        catch {
            $missing += @("base_url", "model_id", "credential")
            return [pscustomobject]@{
                status = "needs-config"; error_code = "PROFILE_NOT_FOUND"; worker_id = $WorkerId; profile_id = $ProfileId
                missing = @($missing); blocking = @(); next_action = "configure"
            }
        }
    }

    $baseUrl = [string]$profile.base_url
    $modelId = [string]$profile.model_id
    if ([string]::IsNullOrWhiteSpace($baseUrl) -or $script:TemplatePlaceholders -contains $baseUrl) { $missing += "base_url" }
    if ([string]::IsNullOrWhiteSpace($modelId) -or $script:TemplatePlaceholders -contains $modelId) { $missing += "model_id" }

    $credentialSource = [string]$profile.credential_source
    $credentialPresent = $false
    try {
        $credentialPresent = (Test-CredentialPresence -Source $credentialSource -Scope $CredentialScope).present
    }
    catch { $credentialPresent = $false }
    if (-not $credentialPresent) { $missing += "credential" }

    $overlayPath = Get-GeneratedOverlayPath -WorkerId $WorkerId -ProfileId ([string]$profile.profile_id) -CodexHome $CodexHome
    $overlayGenerated = (Test-Path -LiteralPath $overlayPath) -and (Test-GeneratedOverlayOwned -Path $overlayPath)
    $agentRegistered = Test-CodexAgentRegistrationOwned -WorkerId $WorkerId -ProfileId ([string]$profile.profile_id) -CodexHome $CodexHome

    $probe = Get-CodexCapabilityProbeResult -LiveEvidenceDir (Get-RepoEvidenceDir)
    $blocking = @(Test-RequiredWorkerCapabilities -ProbeResult $probe)

    if ($missing.Count -gt 0) {
        $status = if ($missing -contains "credential" -and $missing.Count -eq 1) { "credential-missing" } else { "needs-config" }
        $next = if ($missing -contains "credential") { "credential set" } else { "configure" }
        return [pscustomobject]@{
            status = $status; error_code = "INCOMPLETE_CONFIG"; worker_id = $WorkerId
            profile_id = [string]$profile.profile_id; missing = @($missing)
            credential = [pscustomobject]@{ source = $credentialSource; present = $credentialPresent }
            overlay_generated = $overlayGenerated; agent_registered = $agentRegistered; blocking = @($blocking); next_action = $next
        }
    }
    if (-not $overlayGenerated) {
        return [pscustomobject]@{
            status = "needs-config"; error_code = "OVERLAY_MISSING"; worker_id = $WorkerId
            profile_id = [string]$profile.profile_id; missing = @("overlay")
            credential = [pscustomobject]@{ source = $credentialSource; present = $credentialPresent }
            overlay_generated = $false; agent_registered = $agentRegistered; blocking = @($blocking); next_action = "configure"
        }
    }
    if (-not $agentRegistered) {
        return [pscustomobject]@{
            status = "provider-misaligned"; error_code = "AGENT_REGISTRATION_MISSING"; worker_id = $WorkerId
            profile_id = [string]$profile.profile_id; missing = @("agent_registration")
            credential = [pscustomobject]@{ source = $credentialSource; present = $credentialPresent }
            overlay_generated = $overlayGenerated; agent_registered = $false; blocking = @($blocking); next_action = "configure"
        }
    }
    if ($blocking.Count -gt 0) {
        return [pscustomobject]@{
            status = "host-blocked"; error_code = "HOST_CAPABILITY_BLOCKED"; worker_id = $WorkerId
            profile_id = [string]$profile.profile_id
            credential = [pscustomobject]@{ source = $credentialSource; present = $credentialPresent }
            overlay_generated = $overlayGenerated; agent_registered = $agentRegistered; blocking = @($blocking); next_action = $null
        }
    }

    return [pscustomobject]@{
        status = "ready"; error_code = $null; worker_id = $WorkerId
        profile_id = [string]$profile.profile_id
        provider_id = [string]$profile.provider_id
        base_url = $baseUrl; model_id = $modelId
        credential = [pscustomobject]@{ source = $credentialSource; present = $credentialPresent }
        overlay_generated = $overlayGenerated; agent_registered = $agentRegistered
        agent_role = Get-CodexAgentRoleName -WorkerId $WorkerId -ProfileId ([string]$profile.profile_id)
        blocking = @(); next_action = "dispatch"
    }
}

# ---------------------------------------------------------------------------
# 命令实现
# ---------------------------------------------------------------------------

function Invoke-WorkerList {
    param(
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    $workers = @(Get-WorkerDescriptors)
    $rows = @()
    foreach ($worker in $workers) {
        $profiles = @(Get-ProviderProfiles -WorkerId ([string]$worker.id) -CodexHome $CodexHome)
        $status = "external-cli"
        if ([string]$worker.runtime_type -eq "native-provider") {
            if ($profiles.Count -eq 0) { $status = "needs-config" }
            else {
                $ready = Get-NativeProviderReadiness -WorkerId ([string]$worker.id) -CodexHome $CodexHome -CredentialScope $CredentialScope
                $status = $ready.status
            }
        }
        $rows += [pscustomobject]@{
            worker_id = [string]$worker.id
            runtime_type = [string]$worker.runtime_type
            purpose = [string]$worker.descriptor.purpose
            profiles = $profiles.Count
            status = $status
        }
    }
    return (New-WorkerCliSuccess -Data @{ workers = @($rows) })
}

function Invoke-WorkerShow {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    try { $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId }
    catch { return (New-WorkerCliError -Code "WORKER_NOT_FOUND" -Message "worker '$WorkerId' is not registered") }

    $profiles = @()
    foreach ($p in @(Get-ProviderProfiles -WorkerId $WorkerId -CodexHome $CodexHome)) {
        $present = $false
        try { $present = (Test-CredentialPresence -Source ([string]$p.credential_source) -Scope $CredentialScope).present } catch { $present = $false }
        $profiles += [pscustomobject]@{
            profile_id = [string]$p.profile_id
            provider_id = [string]$p.provider_id
            base_url = [string]$p.base_url
            model_id = [string]$p.model_id
            credential_source = [string]$p.credential_source
            credential_present = $present
        }
    }
    $data = [ordered]@{
        worker_id = $WorkerId
        runtime_type = [string]$descriptor.runtime_type
        purpose = [string]$descriptor.purpose
        data_boundary = $descriptor.data_boundary
        provider = [ordered]@{
            provider_id = [string]$descriptor.provider.provider_id
            model_id = [string]$descriptor.provider.model_id
            wire_api = [string]$descriptor.provider.wire_api
            default_sandbox = [string]$descriptor.provider.default_sandbox
            credential_source = [string]$descriptor.provider.credential_source
        }
        profiles = @($profiles)
    }
    return (New-WorkerCliSuccess -Data $data)
}

function Invoke-WorkerStatus {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    $ready = Get-NativeProviderReadiness -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome -CredentialScope $CredentialScope
    return (New-WorkerCliSuccess -Data $ready)
}

function Read-MaskedSecret {
    # masked 交互输入（Read-Host -AsSecureString）；输入为空返回 ""。
    # 返回后立即由调用方使用，PowerShell 字符串不可变，明文只存在于当前进程内存。
    $secure = Read-Host -AsSecureString "API Key (masked): "
    if ($null -eq $secure -or $secure.Length -eq 0) { return "" }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Invoke-WorkerConfigure {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [string]$BaseUrl = "",
        [string]$ModelId = "",
        [string]$ProviderAlias = "",
        [switch]$ApiKeyStdin,
        [switch]$NonInteractive,
        [switch]$KeepCredential,
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    try { Get-WorkerDescriptor -WorkerId $WorkerId | Out-Null }
    catch { return (New-WorkerCliError -Code "WORKER_NOT_FOUND" -Message "worker '$WorkerId' is not registered" ) }

    if ([string]::IsNullOrWhiteSpace($ProfileId)) { $ProfileId = "$WorkerId-default" }

    # 现有 profile 作为默认值基础（Agent 非交互模式不重复询问已提供字段）
    $existing = $null
    try { $existing = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome } catch { $existing = $null }

    $effectiveBaseUrl = $BaseUrl
    if ([string]::IsNullOrWhiteSpace($effectiveBaseUrl) -and $null -ne $existing) { $effectiveBaseUrl = [string]$existing.base_url }
    $effectiveModelId = $ModelId
    if ([string]::IsNullOrWhiteSpace($effectiveModelId) -and $null -ne $existing) { $effectiveModelId = [string]$existing.model_id }

    $isInteractive = (-not $NonInteractive)
    if ([string]::IsNullOrWhiteSpace($effectiveBaseUrl) -and $isInteractive) {
        $effectiveBaseUrl = Read-Host "Base URL"
    }
    if ([string]::IsNullOrWhiteSpace($effectiveModelId) -and $isInteractive) {
        $effectiveModelId = Read-Host "Model ID"
    }

    $missing = @()
    if ([string]::IsNullOrWhiteSpace($effectiveBaseUrl)) { $missing += "base_url" }
    if ([string]::IsNullOrWhiteSpace($effectiveModelId)) { $missing += "model_id" }
    if ($missing.Count -gt 0) {
        return (New-WorkerCliSuccess -Data ([pscustomobject]@{
            status = "needs-config"; worker_id = $WorkerId; profile_id = $ProfileId
            missing = @($missing); next_action = "configure"
        }))
    }

    # credential：--api-key-stdin > masked 交互 > 保留现有
    $newSecret = ""
    $credentialProvided = $false
    if ($ApiKeyStdin) {
        $newSecret = Read-SecretFromStdin
        if (-not [string]::IsNullOrWhiteSpace($newSecret)) { $credentialProvided = $true }
    }
    elseif ($isInteractive -and -not $KeepCredential) {
        $newSecret = Read-MaskedSecret
        if (-not [string]::IsNullOrWhiteSpace($newSecret)) { $credentialProvided = $true }
    }

    try {
        if ($null -eq $existing) {
            $profile = New-ProviderProfile -WorkerId $WorkerId -ProfileId $ProfileId `
                -BaseUrl $effectiveBaseUrl -ModelId $effectiveModelId `
                -ProviderId $ProviderAlias -CodexHome $CodexHome
        }
        else {
            $profile = Update-ProviderProfile -ProfileId $ProfileId `
                -BaseUrl $effectiveBaseUrl -ModelId $effectiveModelId -ProviderId $ProviderAlias -CodexHome $CodexHome
        }
    }
    catch {
        if ($_.Exception.Message -match "already exists") {
            return (New-WorkerCliError -Code "PROVIDER_PROFILE_CONFLICT" -Message $_.Exception.Message)
        }
        throw
    }

    if ($credentialProvided) {
        try {
            Set-Credential -Source ([string]$profile.credential_source) -Value $newSecret -Scope $CredentialScope | Out-Null
        }
        catch {
            return (New-WorkerCliError -Code "CREDENTIAL_WRITE_UNSUPPORTED" -Message "credential write failed (use 'relay worker credential set' with masked prompt)")
        }
        $newSecret = ""
    }

    try {
        $null = New-CodexAgentOverlay -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome -ProviderAlias $ProviderAlias
        $null = Install-CodexAgentRegistration -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome
    }
    catch {
        if ($_.Exception.Message -match "not relay-agent owned|generated config conflict") {
            return (New-WorkerCliError -Code "GENERATED_CONFIG_CONFLICT" -Message $_.Exception.Message)
        }
        throw
    }

    $ready = Get-NativeProviderReadiness -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome -CredentialScope $CredentialScope
    $data = [ordered]@{
        status = "configured"
        worker_id = $WorkerId
        profile_id = $ProfileId
        provider_id = [string]$profile.provider_id
        base_url = [string]$profile.base_url
        model_id = [string]$profile.model_id
        credential = [ordered]@{ source = [string]$profile.credential_source; present = $ready.credential.present }
        readiness = $ready.status
        paid_call_performed = $false
        next_action = if ($ready.status -eq "ready") { "dispatch" } else { "doctor" }
    }
    return (New-WorkerCliSuccess -Data $data)
}

function Invoke-WorkerCredential {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [switch]$ApiKeyStdin,
        [switch]$NonInteractive,
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    try {
        $profile = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome
    }
    catch { return (New-WorkerCliError -Code "PROFILE_NOT_FOUND" -Message "provider profile '$ProfileId' not found (configure the worker first)") }
    if ([string]$profile.worker_id -ne $WorkerId) {
        return (New-WorkerCliError -Code "PROFILE_NOT_FOUND" -Message "profile '$ProfileId' is bound to worker '$($profile.worker_id)', not '$WorkerId'")
    }
    $source = [string]$profile.credential_source

    switch ($Action) {
        "set" {
            $value = ""
            if ($ApiKeyStdin) { $value = Read-SecretFromStdin }
            elseif (-not $NonInteractive) { $value = Read-MaskedSecret }
            if ([string]::IsNullOrWhiteSpace($value)) {
                return (New-WorkerCliError -Code "CREDENTIAL_MISSING" -Message "no API key provided; use --api-key-stdin or run the masked prompt interactively")
            }
            try {
                Set-Credential -Source $source -Value $value -Scope $CredentialScope | Out-Null
            }
            catch {
                return (New-WorkerCliError -Code "CREDENTIAL_WRITE_UNSUPPORTED" -Message "credential write failed")
            }
            $value = ""
            return (New-WorkerCliSuccess -Data ([pscustomobject]@{ action = "set"; source = $source; present = $true }))
        }
        "status" {
            $present = (Test-CredentialPresence -Source $source -Scope $CredentialScope).present
            return (New-WorkerCliSuccess -Data ([pscustomobject]@{ action = "status"; source = $source; present = $present }))
        }
        "remove" {
            Remove-Credential -Source $source -Scope $CredentialScope | Out-Null
            return (New-WorkerCliSuccess -Data ([pscustomobject]@{ action = "remove"; source = $source; present = $false }))
        }
    }
    return (New-WorkerCliError -Code "INVALID_ACTION" -Message "unknown credential action '$Action'")
}

function Invoke-WorkerDoctor {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    $ready = Get-NativeProviderReadiness -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome -CredentialScope $CredentialScope
    $probe = Get-CodexCapabilityProbeResult -LiveEvidenceDir (Get-RepoEvidenceDir)
    $credentialPresent = if ($ready.PSObject.Properties.Name -contains "credential") { $ready.credential.present } else { $false }
    $overlayGenerated = if ($ready.PSObject.Properties.Name -contains "overlay_generated") { $ready.overlay_generated } else { $false }
    $agentRegistered = if ($ready.PSObject.Properties.Name -contains "agent_registered") { $ready.agent_registered } else { $false }
    $data = [ordered]@{
        status = $ready.status
        error_code = $ready.error_code
        worker_id = $WorkerId
        profile_id = if ($ready.PSObject.Properties.Name -contains "profile_id") { $ready.profile_id } else { $null }
        paid_call_performed = $false
        checks = [ordered]@{
            worker_manifest = if ($ready.error_code -eq "WORKER_NOT_FOUND") { "missing" } else { "ok" }
            profile = if ($ready.error_code -in @("PROFILE_NOT_FOUND", "PROFILE_SELECTION_REQUIRED")) { "missing" } else { "ok" }
            credential = if ($credentialPresent) { "present" } else { "missing" }
            overlay_generated = $overlayGenerated
            agent_registration = if ($agentRegistered) { "registered" } else { "missing" }
            host_capability = if ($ready.blocking.Count -eq 0) { "ok" } else { "blocked" }
        }
        blocking = @($ready.blocking)
        next_action = $ready.next_action
    }
    return (New-WorkerCliSuccess -Data $data)
}

function Invoke-WorkerDispatch {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [Parameter(Mandatory = $true)][string]$Task,
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    if ([string]::IsNullOrWhiteSpace($Task)) {
        return (New-WorkerCliError -Code "TASK_MISSING" -Message "a task is required after '--'")
    }
    $ready = Get-NativeProviderReadiness -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome -CredentialScope $CredentialScope
    if ($ready.status -ne "ready") {
        $profileId = if ($ready.PSObject.Properties.Name -contains "profile_id") { $ready.profile_id } else { $null }
        return (New-WorkerCliSuccess -Data ([ordered]@{
            status = "blocked"; error_code = $ready.error_code; worker_id = $WorkerId
            profile_id = $profileId; blocking = @($ready.blocking); next_action = $ready.next_action
        }))
    }
    $data = [ordered]@{
        status = "dispatch-ready"
        worker_id = $WorkerId
        runtime_type = "native-provider"
        profile_id = [string]$ready.profile_id
        provider_alias = [string]$ready.provider_id
        agent_role = [string]$ready.agent_role
        model_id = [string]$ready.model_id
        data_boundary = (Get-WorkerDescriptor -WorkerId $WorkerId).data_boundary
        execution = "codex-native-child (spawn_agent managed by the Codex host; relay does not implement a second child lifecycle)"
        task = $Task
    }
    return (New-WorkerCliSuccess -Data $data)
}

function Invoke-WorkerUninstall {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$ProfileId = "",
        [string]$CodexHome = "",
        [string]$CredentialScope = "User"
    )
    try { Get-WorkerDescriptor -WorkerId $WorkerId | Out-Null }
    catch { return (New-WorkerCliError -Code "WORKER_NOT_FOUND" -Message "worker '$WorkerId' is not registered") }

    $removed = @()
    if (-not [string]::IsNullOrWhiteSpace($ProfileId)) {
        # 指定 profile：只清理该 profile 的 overlay、profile 与 credential
        try {
            $profile = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome
            if ([string]$profile.worker_id -ne $WorkerId) {
                return (New-WorkerCliError -Code "PROFILE_NOT_FOUND" -Message "profile '$ProfileId' is bound to worker '$($profile.worker_id)'")
            }
            Remove-CodexAgentRegistration -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome | Out-Null
            Remove-GeneratedOverlay -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome | Out-Null
            Remove-Credential -Source ([string]$profile.credential_source) -Scope $CredentialScope | Out-Null
            Remove-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome | Out-Null
            $removed += @("agent-registration", "overlay", "profile", "credential")
        }
        catch { return (New-WorkerCliError -Code "PROFILE_NOT_FOUND" -Message "provider profile '$ProfileId' not found") }
    }
    else {
        # 整个 worker：pack staging + 所有 Relay-owned overlay（profile 与 credential 保留，单独按 profile 卸载）
        Uninstall-WorkerPack -WorkerId $WorkerId | Out-Null
        foreach ($p in @(Get-ProviderProfiles -WorkerId $WorkerId -CodexHome $CodexHome)) {
            Remove-CodexAgentRegistration -WorkerId $WorkerId -ProfileId ([string]$p.profile_id) -CodexHome $CodexHome | Out-Null
            Remove-GeneratedOverlay -WorkerId $WorkerId -ProfileId ([string]$p.profile_id) -CodexHome $CodexHome | Out-Null
            $removed += ("agent-registration:" + [string]$p.profile_id)
            $removed += ("overlay:" + [string]$p.profile_id)
        }
        $removed += "pack-staging"
    }
    return (New-WorkerCliSuccess -Data ([pscustomobject]@{ worker_id = $WorkerId; removed = @($removed) }))
}

# ---------------------------------------------------------------------------
# 命令行解析与总入口
# ---------------------------------------------------------------------------

function Get-WorkerOptionValue {
    param(
        [Parameter(Mandatory = $true)][string[]]$Tokens,
        [Parameter(Mandatory = $true)][ref]$Index,
        [Parameter(Mandatory = $true)][string]$Flag,
        [Parameter(Mandatory = $true)][ref]$Options
    )
    $token = $Tokens[$Index.Value]
    $eqPos = $token.IndexOf("=")
    if ($eqPos -ge 0) {
        $Options.Value[$Flag] = $token.Substring($eqPos + 1)
        return
    }
    $Index.Value = $Index.Value + 1
    if ($Index.Value -ge $Tokens.Count) { throw "relay worker: option '$Flag' requires a value" }
    $Options.Value[$Flag] = $Tokens[$Index.Value]
}

function Invoke-WorkerCommand {
    # 总入口：解析 token 数组、分发命令、格式化输出、返回退出码（0/1）。
    # Entry point: parses tokens, dispatches, formats output, returns exit code.
    param([string[]]$Tokens)

    if ($Tokens.Count -lt 1) {
        Write-Host "usage: relay worker <list|show|status|configure|credential|doctor|dispatch|uninstall> [options]"
        return 1
    }
    $sub = $Tokens[0]

    $json = $false
    $options = @{}
    $positional = New-Object System.Collections.Generic.List[string]
    $task = ""
    $afterSeparator = $false

    $i = 1
    :parse while ($i -lt $Tokens.Count) {
        $token = $Tokens[$i]
        if ($afterSeparator) {
            $task = ($Tokens[$i..($Tokens.Count - 1)] -join " ")
            break
        }
        switch -Regex ($token) {
            "^--$" { $afterSeparator = $true }
            "^(--json)$" { $json = $true }
            "^(--non-interactive)$" { $options["non_interactive"] = $true }
            "^(--api-key-stdin)$" { $options["api_key_stdin"] = $true }
            "^(--keep-credential)$" { $options["keep_credential"] = $true }
            "^(--auto)$" { $options["auto"] = $true }
            "^(--profile|--base-url|--model|--provider-alias|--codex-home)$" {
                Get-WorkerOptionValue -Tokens $Tokens -Index ([ref]$i) -Flag $token -Options ([ref]$options)
            }
            # 明确禁止：API Key 不得作为命令行参数出现。等号形式也必须在进入
            # generic unknown-option 分支前拦截，否则错误文本会把 secret 原样回显。
            "^((--api-key|-k)(=.*)?|--api-key-stdin=.*)$" {
                throw "relay worker: --api-key <value> is forbidden; use --api-key-stdin or the masked prompt"
            }
            default {
                # unknown option 可能是用户把 secret 拼进了拼写错误的参数（例如
                # --apikey=<value>）。错误消息绝不回显原 token，避免 transcript 泄漏。
                if ($token -match "^[-/]") { throw "relay worker: unknown option; check command syntax" }
                $positional.Add($token)
            }
        }
        $i = $i + 1
    }

    $codexHome = if ($options.ContainsKey("--codex-home")) { [string]$options["--codex-home"] } else { "" }
    # credential 写入作用域：默认 User（持久）；测试/自动化通过 RELAY_CREDENTIAL_SCOPE=Process 注入，
    # 避免测试污染用户环境。该环境变量不是 secret 通道。
    $credentialScope = if (-not [string]::IsNullOrWhiteSpace($env:RELAY_CREDENTIAL_SCOPE)) { $env:RELAY_CREDENTIAL_SCOPE } else { "User" }

    $result = $null
    switch ($sub) {
        "list" {
            $result = Invoke-WorkerList -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "show" {
            if ($positional.Count -lt 1) { throw "relay worker: 'show' requires a worker id" }
            $result = Invoke-WorkerShow -WorkerId $positional[0] -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "status" {
            if ($positional.Count -lt 1) { throw "relay worker: 'status' requires a worker id" }
            $result = Invoke-WorkerStatus -WorkerId $positional[0] -ProfileId $options["--profile"] -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "configure" {
            if ($positional.Count -lt 1) { throw "relay worker: 'configure' requires a worker id" }
            $result = Invoke-WorkerConfigure -WorkerId $positional[0] `
                -ProfileId $options["--profile"] -BaseUrl $options["--base-url"] -ModelId $options["--model"] `
                -ProviderAlias $options["--provider-alias"] `
                -ApiKeyStdin:([bool]$options["api_key_stdin"]) -NonInteractive:([bool]$options["non_interactive"]) `
                -KeepCredential:([bool]$options["keep_credential"]) -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "credential" {
            if ($positional.Count -lt 2) { throw "relay worker: 'credential' requires an action (set|status|remove) and a worker id" }
            $action = $positional[0]
            if ($action -notin @("set", "status", "remove")) { throw "relay worker: unknown credential action '$action' (set|status|remove)" }
            if (-not $options.ContainsKey("--profile")) { throw "relay worker: 'credential' requires --profile <profile-id>" }
            $result = Invoke-WorkerCredential -Action $action -WorkerId $positional[1] `
                -ProfileId $options["--profile"] `
                -ApiKeyStdin:([bool]$options["api_key_stdin"]) -NonInteractive:([bool]$options["non_interactive"]) `
                -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "doctor" {
            if ($positional.Count -lt 1) { throw "relay worker: 'doctor' requires a worker id" }
            $result = Invoke-WorkerDoctor -WorkerId $positional[0] -ProfileId $options["--profile"] -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "dispatch" {
            if ($positional.Count -lt 1) { throw "relay worker: 'dispatch' requires a worker id" }
            $result = Invoke-WorkerDispatch -WorkerId $positional[0] -ProfileId $options["--profile"] -Task $task -CodexHome $codexHome -CredentialScope $credentialScope
        }
        "uninstall" {
            if ($positional.Count -lt 1) { throw "relay worker: 'uninstall' requires a worker id" }
            $result = Invoke-WorkerUninstall -WorkerId $positional[0] -ProfileId $options["--profile"] -CodexHome $codexHome -CredentialScope $credentialScope
        }
        default {
            throw "relay worker: unknown subcommand '$sub' (list|show|status|configure|credential|doctor|dispatch|uninstall)"
        }
    }

    if ($null -eq $result) { return 1 }

    if (-not $result.ok) {
        if ($json) {
            $result | ConvertTo-Json -Depth 5 | Write-Host
        }
        else {
            [Console]::Error.WriteLine("relay worker: ERROR $($result.error.code): $($result.error.message)")
        }
        return 1
    }

    if ($json) {
        $result.data | ConvertTo-Json -Depth 6 | Write-Host
    }
    else {
        $result.data | Format-List | Out-String -Width 200 | Write-Host
    }
    return 0
}

Export-ModuleMember -Function Invoke-WorkerCommand, Get-NativeProviderReadiness, Invoke-WorkerList, Invoke-WorkerShow, Invoke-WorkerStatus, Invoke-WorkerConfigure, Invoke-WorkerCredential, Invoke-WorkerDoctor, Invoke-WorkerDispatch, Invoke-WorkerUninstall
