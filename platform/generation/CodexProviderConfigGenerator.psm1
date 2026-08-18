Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Codex provider config generator：pack 模板（仓库定义）+ provider profile（用户实例）
# → 用户级 Codex agent overlay，并在主 config.toml 中只增删 Relay-owned [agents.*]
# 注册段。生成物独立存放于 <CODEX_HOME>/relay/generated/；主 Agent 的全局
# model/model_provider 不被修改，secret 只以 env 引用出现（onboarding plan §4/§7.2、P0-B）。
# Pack template + provider profile -> user-level Codex agent overlay plus a narrowly
# owned [agents.*] registration in config.toml. Global model/model_provider settings
# stay untouched; secrets appear only as env references.
Import-Module (Join-Path $PSScriptRoot "..\hosts\codex\CodexHostAdapter.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\registry\WorkerProfileStore.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\registry\WorkerRegistry.psm1") -Force

$script:OwnershipMarkerLine = "# relay-agent generated overlay; managed_by=relay-agent"
$script:RegistrationMarkerPrefix = "# relay-agent agent-registration"

function Get-WorkerPackDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [string]$RepoRoot = ""
    )
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Get-WorkerRegistryRoot }
    return (Join-Path $RepoRoot "workers\native-providers\$WorkerId")
}

function Get-GeneratedOverlayPath {
    # <CODEX_HOME>/relay/generated/agents/<worker>--<profile>.toml
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    if ([string]::IsNullOrWhiteSpace($CodexHome)) { $CodexHome = Get-CodexHome }
    $dir = Join-Path $CodexHome "relay\generated\agents"
    return (Join-Path $dir "$WorkerId--$ProfileId.toml")
}

function Get-CodexAgentRoleName {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId
    )
    return "$WorkerId--$ProfileId"
}

function Get-CodexMainConfigPath {
    param([string]$CodexHome = "")
    if ([string]::IsNullOrWhiteSpace($CodexHome)) { $CodexHome = Get-CodexHome }
    return (Join-Path $CodexHome "config.toml")
}

function Read-CodexConfigTextState {
    # config.toml patch 必须保留原编码/BOM。PowerShell 7 的 Set-Content -Encoding utf8
    # 默认写 UTF-8 no-BOM，会把用户原有 UTF-8 BOM 静默剥掉，因此这里按原始字节探测
    # 常见 Unicode BOM，并把 encoding 与解码后的正文一起返回。
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            content = ""
            encoding = [System.Text.UTF8Encoding]::new($false)
            existed = $false
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    $encoding = $null
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
        $encoding = [System.Text.UTF32Encoding]::new($true, $true)
        $offset = 4
    }
    elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
        $encoding = [System.Text.UTF32Encoding]::new($false, $true)
        $offset = 4
    }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = [System.Text.UTF8Encoding]::new($true)
        $offset = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = [System.Text.UnicodeEncoding]::new($true, $true)
        $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = [System.Text.UnicodeEncoding]::new($false, $true)
        $offset = 2
    }
    else {
        $encoding = [System.Text.UTF8Encoding]::new($false)
    }

    $content = if ($bytes.Length -gt $offset) { $encoding.GetString($bytes, $offset, $bytes.Length - $offset) } else { "" }
    return [pscustomobject]@{ content = $content; encoding = $encoding; existed = $true }
}

function Write-CodexConfigTextState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][System.Text.Encoding]$Encoding
    )
    [System.IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function Get-CodexRegistrationNewline {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
    if ($Content.Contains("`r`n")) { return "`r`n" }
    if ($Content.Contains("`n")) { return "`n" }
    return [Environment]::NewLine
}

function Get-CodexAgentRegistrationMarkers {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId
    )
    $role = Get-CodexAgentRoleName -WorkerId $WorkerId -ProfileId $ProfileId
    return [pscustomobject]@{
        start = "$script:RegistrationMarkerPrefix begin; worker=$WorkerId; profile=$ProfileId; role=$role"
        end = "$script:RegistrationMarkerPrefix end; worker=$WorkerId; profile=$ProfileId; role=$role"
        role = $role
    }
}

function Test-CodexAgentRegistrationOwned {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $configPath = Get-CodexMainConfigPath -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $configPath)) { return $false }
    $content = Get-Content -Raw -LiteralPath $configPath
    if ($null -eq $content) { $content = "" }
    $markers = Get-CodexAgentRegistrationMarkers -WorkerId $WorkerId -ProfileId $ProfileId
    if (-not $content.Contains($markers.start) -or -not $content.Contains($markers.end)) { return $false }
    $roleHeader = "[agents.$($markers.role)]"
    return $content.Contains($roleHeader)
}

function Install-CodexAgentRegistration {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $configPath = Get-CodexMainConfigPath -CodexHome $CodexHome
    $parent = Split-Path -Parent $configPath
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $state = Read-CodexConfigTextState -Path $configPath
    $content = [string]$state.content
    $markers = Get-CodexAgentRegistrationMarkers -WorkerId $WorkerId -ProfileId $ProfileId
    $roleHeader = "[agents.$($markers.role)]"
    $overlayPath = (Get-GeneratedOverlayPath -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome).Replace("\", "/").Replace('"', '\"')

    $startIndex = $content.IndexOf($markers.start, [StringComparison]::Ordinal)
    if ($startIndex -ge 0) {
        $endIndex = $content.IndexOf($markers.end, $startIndex, [StringComparison]::Ordinal)
        if ($endIndex -lt 0) { throw "generated config conflict: relay-owned registration marker is incomplete for role '$($markers.role)'" }
        $endIndex += $markers.end.Length
        $existingBlock = $content.Substring($startIndex, $endIndex - $startIndex)
        $newline = Get-CodexRegistrationNewline -Content $existingBlock
        $prefixKind = "legacy"
        $metadataMatch = [regex]::Match($existingBlock, "(?m)^# relay-agent agent-registration metadata; prefix=(none|lf|crlf)\r?$")
        if ($metadataMatch.Success) { $prefixKind = $metadataMatch.Groups[1].Value }
        $block = @(
            $markers.start,
            "$script:RegistrationMarkerPrefix metadata; prefix=$prefixKind",
            $roleHeader,
            "description = `"Relay native-provider worker $WorkerId (profile $ProfileId)`"",
            "config_file = `"$overlayPath`"",
            $markers.end
        ) -join $newline
        $content = $content.Substring(0, $startIndex) + $block + $content.Substring($endIndex)
    }
    elseif ($content -cmatch "(?m)^\s*\[agents\.$([regex]::Escape($markers.role))\]\s*$") {
        throw "generated config conflict: agent role '$($markers.role)' already exists and is not relay-agent owned (fail closed)"
    }
    else {
        $newline = Get-CodexRegistrationNewline -Content $content
        $prefix = ""
        $prefixKind = "none"
        if ($content.Length -gt 0 -and -not $content.EndsWith("`n") -and -not $content.EndsWith("`r")) {
            $prefix = $newline
            $prefixKind = if ($newline -eq "`r`n") { "crlf" } else { "lf" }
        }
        $block = @(
            $markers.start,
            "$script:RegistrationMarkerPrefix metadata; prefix=$prefixKind",
            $roleHeader,
            "description = `"Relay native-provider worker $WorkerId (profile $ProfileId)`"",
            "config_file = `"$overlayPath`"",
            $markers.end
        ) -join $newline
        $content += $prefix + $block
    }
    Write-CodexConfigTextState -Path $configPath -Content $content -Encoding $state.encoding
    return [pscustomobject]@{ path = $configPath; role = $markers.role; profile_id = $ProfileId; worker_id = $WorkerId }
}

function Remove-CodexAgentRegistration {
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $configPath = Get-CodexMainConfigPath -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $configPath)) { return [pscustomobject]@{ removed = $false; path = $configPath } }
    $state = Read-CodexConfigTextState -Path $configPath
    $content = [string]$state.content
    $markers = Get-CodexAgentRegistrationMarkers -WorkerId $WorkerId -ProfileId $ProfileId
    $startIndex = $content.IndexOf($markers.start, [StringComparison]::Ordinal)
    if ($startIndex -lt 0) { return [pscustomobject]@{ removed = $false; path = $configPath } }
    $endIndex = $content.IndexOf($markers.end, $startIndex, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw "refusing to remove incomplete relay agent registration for '$($markers.role)'" }
    $endIndex += $markers.end.Length

    $block = $content.Substring($startIndex, $endIndex - $startIndex)
    $metadataMatch = [regex]::Match($block, "(?m)^# relay-agent agent-registration metadata; prefix=(none|lf|crlf)\r?$")
    $removeStart = $startIndex
    if ($metadataMatch.Success) {
        switch ($metadataMatch.Groups[1].Value) {
            "lf" {
                if ($removeStart -ge 1 -and $content.Substring($removeStart - 1, 1) -eq "`n") { $removeStart -= 1 }
            }
            "crlf" {
                if ($removeStart -ge 2 -and $content.Substring($removeStart - 2, 2) -eq "`r`n") { $removeStart -= 2 }
            }
        }
    }
    else {
        # 兼容本修复前已生成的 legacy block：旧格式没有 prefix metadata，且在
        # end marker 后追加换行。仅 legacy 路径沿用旧清理方式。
        while ($endIndex -lt $content.Length -and $content[$endIndex] -in @("`r", "`n")) { $endIndex++ }
    }

    $newContent = $content.Substring(0, $removeStart) + $content.Substring($endIndex)
    Write-CodexConfigTextState -Path $configPath -Content $newContent -Encoding $state.encoding
    return [pscustomobject]@{ removed = $true; path = $configPath; role = $markers.role }
}

function Test-GeneratedOverlayOwned {
    # 只有带 Relay ownership marker 的生成物才算 Relay-owned；其余一律视为外部文件。
    # Only files carrying the Relay ownership marker count as Relay-owned.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $head = @(Get-Content -LiteralPath $Path -TotalCount 3 -ErrorAction SilentlyContinue)
    return (@($head | Where-Object { $_ -like ($script:OwnershipMarkerLine + "*") }).Count -gt 0)
}

function ConvertTo-CodexOverlayContent {
    # 模板替换：model/base_url/model_provider/段名/env_key 由 profile 驱动。
    # 不解析 TOML（pack 模板由仓库维护），用模板行正则精准替换；任何行缺失即失败。
    # Template-driven line replacement; a missing template line is an error.
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][string]$ModelId,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ProviderAlias,
        [Parameter(Mandatory = $true)][string]$EnvName
    )
    if ($Template -notmatch "(?m)^model = ") { throw "overlay template missing 'model' line" }
    if ($Template -notmatch "(?m)^base_url = ") { throw "overlay template missing 'base_url' line" }
    if ($Template -notmatch "(?m)^model_provider = ") { throw "overlay template missing 'model_provider' line" }
    if ($Template -notmatch "(?m)^\[model_providers\.") { throw "overlay template missing '[model_providers.*]' section" }
    if ($Template -notmatch "(?m)^env_key = ") { throw "overlay template missing 'env_key' line" }

    $content = $Template
    # CRLF 感知行尾：Windows 模板行尾是 \r\n，锚点必须允许可选 \r（否则替换静默不生效）。
    # CRLF-aware line ends: Windows templates end lines with \r\n, so anchors allow
    # an optional \r or the replacement silently never fires.
    $content = [regex]::Replace($content, "(?m)^model = `".*`"\r?$", "model = `"$ModelId`"")
    $content = [regex]::Replace($content, "(?m)^base_url = `".*`"\r?$", "base_url = `"$BaseUrl`"")
    $content = [regex]::Replace($content, "(?m)^model_provider = `".*`"\r?$", "model_provider = `"$ProviderAlias`"")
    $content = [regex]::Replace($content, "(?m)^\[model_providers\.[^\]]+\]\r?$", "[model_providers.$ProviderAlias]")
    $content = [regex]::Replace($content, "(?m)^env_key = `".*`"\r?$", "env_key = `"$EnvName`"")
    return $content
}

function New-CodexAgentOverlay {
    # 生成（或覆盖 Relay-owned 的）用户级 overlay；目标被非 Relay 文件占用时 fail closed。
    # Generates (or overwrites Relay-owned) user-level overlays; fails closed when the
    # target is occupied by a non-Relay file.
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = "",
        [string]$ProviderAlias = ""
    )
    $profile = Get-ProviderProfile -ProfileId $ProfileId -CodexHome $CodexHome
    if ([string]$profile.worker_id -ne $WorkerId) {
        throw "provider profile '$ProfileId' is bound to worker '$($profile.worker_id)', not '$WorkerId'"
    }

    $target = Get-GeneratedOverlayPath -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome
    if ((Test-Path -LiteralPath $target) -and -not (Test-GeneratedOverlayOwned -Path $target)) {
        throw "generated config conflict: '$target' exists and is not relay-agent owned (fail closed)"
    }

    $alias = $ProviderAlias
    if ([string]::IsNullOrWhiteSpace($alias)) { $alias = [string]$profile.provider_id }

    $packDir = Get-WorkerPackDirectory -WorkerId $WorkerId
    $templatePath = Join-Path $packDir "agent.toml"
    if (-not (Test-Path -LiteralPath $templatePath)) { throw "pack overlay template missing: $templatePath" }
    $template = Get-Content -Raw -LiteralPath $templatePath

    $credentialSource = [string]$profile.credential_source
    if ($credentialSource -notmatch "^env:([A-Za-z_][A-Za-z0-9_]*)$") {
        throw "unsupported credential source in profile: $credentialSource"
    }
    $envName = $matches[1]

    $body = ConvertTo-CodexOverlayContent -Template $template `
        -ModelId ([string]$profile.model_id) `
        -BaseUrl ([string]$profile.base_url) `
        -ProviderAlias $alias `
        -EnvName $envName

    $header = "$script:OwnershipMarkerLine; worker=$WorkerId; profile=$ProfileId; provider_alias=$alias"
    $content = $header + "`n" + $body

    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Set-Content -LiteralPath $target -Value $content -Encoding utf8

    return [pscustomobject]@{
        path = $target
        worker_id = $WorkerId
        profile_id = $ProfileId
        provider_alias = $alias
        model_id = [string]$profile.model_id
        base_url = [string]$profile.base_url
    }
}

function Remove-GeneratedOverlay {
    # 只删除 Relay-owned 生成物；非 Relay 文件绝不触碰。
    # Removes only Relay-owned artifacts; never touches non-Relay files.
    param(
        [Parameter(Mandatory = $true)][string]$WorkerId,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [string]$CodexHome = ""
    )
    $target = Get-GeneratedOverlayPath -WorkerId $WorkerId -ProfileId $ProfileId -CodexHome $CodexHome
    if (-not (Test-Path -LiteralPath $target)) { return [pscustomobject]@{ path = $target; removed = $false } }
    if (-not (Test-GeneratedOverlayOwned -Path $target)) {
        throw "refusing to remove non-relay file: $target"
    }
    Remove-Item -LiteralPath $target -Force
    return [pscustomobject]@{ path = $target; removed = $true }
}

function Get-CodexRoleRegistrationSnippet {
    # 输出建议的 config.toml [agents.*] 注册段文本（文档/doctor 提示用）。
    # 不自动 patch 主 config.toml：主配置修改需新的 runtime evidence 证明必要性
    # （onboarding plan §7.2）；本函数只提供人/Agent 可见的建议文本。
    param([Parameter(Mandatory = $true)][string]$WorkerId)
    $descriptor = Get-WorkerDescriptor -WorkerId $WorkerId
    return @"
# relay-agent suggested role registration (apply only after verified Codex config format)
[agents.$WorkerId]
description = "$($descriptor.display_name) (relay-agent native-provider worker)"
config_file = "<CODEX_HOME>/relay/generated/agents/<worker>--<profile>.toml"
"@
}

Export-ModuleMember -Function Get-WorkerPackDirectory, Get-GeneratedOverlayPath, Get-CodexAgentRoleName, Get-CodexMainConfigPath, Test-CodexAgentRegistrationOwned, Install-CodexAgentRegistration, Remove-CodexAgentRegistration, Test-GeneratedOverlayOwned, ConvertTo-CodexOverlayContent, New-CodexAgentOverlay, Remove-GeneratedOverlay, Get-CodexRoleRegistrationSnippet
