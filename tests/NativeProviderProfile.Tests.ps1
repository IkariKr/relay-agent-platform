# NativeProviderProfile.Tests.ps1 — provider profile 与 credential store 契约测试。
# Contract tests for provider profile CRUD (NP-PROFILE-*) and credential store
# (NP-CRED-*), per onboarding plan §11.1/§11.2. All credential writes use Process
# scope so the runner never touches the user environment.
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repoRoot "platform\registry\WorkerProfileStore.psm1") -Force
    Import-Module (Join-Path $repoRoot "platform\credentials\CredentialStore.psm1") -Force

    $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("relay-profile-" + [guid]::NewGuid().ToString("N"))
    $script:codexHome = Join-Path $script:testRoot "codex-home"
    New-Item -ItemType Directory -Path $script:codexHome -Force | Out-Null

    $script:secret = "sk-relay-test-" + [guid]::NewGuid().ToString("N")
    $script:suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $script:profileA = "profile-a-" + $script:suffix
    $script:profileB = "profile-b-" + $script:suffix
    $script:workerId = "deepseek-v4-flash"
    $script:sourceA = "env:" + (New-StableCredentialEnvName -ProfileId $script:profileA)
}

AfterAll {
    Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($profileId in @($script:profileA, $script:profileB, ("cred-only-" + $script:suffix))) {
        [Environment]::SetEnvironmentVariable((New-StableCredentialEnvName -ProfileId $profileId), $null, "Process")
    }
}

Describe "NP-PROFILE: provider profile contract" {
    It "NP-PROFILE-001: base url + model id form a valid profile" {
        $p = New-ProviderProfile -WorkerId $script:workerId -ProfileId $script:profileA `
            -BaseUrl "https://example.com/v1" -ModelId "deepseek-v4-flash-response" -CodexHome $script:codexHome
        $p.schema_version | Should -Be "1.0"
        $p.profile_id | Should -Be $script:profileA
        $p.worker_id | Should -Be $script:workerId
        $p.provider_id | Should -Be "deepseek"
        $p.managed_by | Should -Be "relay-agent"
        $p.wire_api | Should -Be "responses"
        $p.credential_source | Should -Match "^env:RELAY_PROVIDER_.*_API_KEY$"
        $file = Join-Path $script:codexHome "relay\native-providers\profiles\$($script:profileA).json"
        (Test-Path -LiteralPath $file) | Should -BeTrue
    }

    It "NP-PROFILE-002: profile file never contains a secret value or secret-named fields" {
        New-ProviderProfile -WorkerId $script:workerId -ProfileId $script:profileB `
            -BaseUrl "https://gateway.example.com/v1" -ModelId "deepseek-v4-flash-response" -CodexHome $script:codexHome | Out-Null
        $file = Join-Path $script:codexHome "relay\native-providers\profiles\$($script:profileB).json"
        $raw = Get-Content -Raw -LiteralPath $file
        Test-SecretPresentInText -Text $raw -Secret $script:secret | Should -BeFalse
        # secret 值不得出现；JSON 键名不得是 secret 字段（env 名后缀 _API_KEY 是 credential_source 的预期引用，不属于键名检查范围）
        $obj = $raw | ConvertFrom-Json
        foreach ($forbiddenKey in @("api_key", "apiKey", "secret", "secret_value", "credential_value")) {
            @($obj.PSObject.Properties.Name) -contains $forbiddenKey | Should -BeFalse
        }
        $obj.PSObject.Properties.Name | Should -Contain "credential_source"
    }

    It "NP-PROFILE-003: same worker can hold multiple profiles" {
        $all = Get-ProviderProfiles -WorkerId $script:workerId -CodexHome $script:codexHome
        $ids = @($all | ForEach-Object { $_.profile_id })
        $ids | Should -Contain $script:profileA
        $ids | Should -Contain $script:profileB
    }

    It "NP-PROFILE-004: profile id conflict fails closed" {
        { New-ProviderProfile -WorkerId $script:workerId -ProfileId $script:profileA `
            -BaseUrl "https://example.com/v1" -ModelId "deepseek-v4-flash-response" -CodexHome $script:codexHome } |
            Should -Throw "*already exists*"
    }

    It "NP-PROFILE-005: removing one profile does not affect another" {
        Remove-ProviderProfile -ProfileId $script:profileB -CodexHome $script:codexHome | Out-Null
        $all = Get-ProviderProfiles -CodexHome $script:codexHome
        @($all | ForEach-Object { $_.profile_id }) | Should -Contain $script:profileA
        { Get-ProviderProfile -ProfileId $script:profileB -CodexHome $script:codexHome } | Should -Throw "*not found*"
    }

    It "NP-PROFILE-006: forbidden secret fields are rejected" {
        $bad = [pscustomobject]@{
            schema_version = "1.0"; profile_id = "x"; worker_id = "x"; provider_id = "x"
            base_url = "https://x"; model_id = "m"; wire_api = "responses"
            credential_source = "env:X"; managed_by = "relay-agent"
            created_at = "t"; updated_at = "t"; api_key = "sk-should-never-persist"
        }
        { Assert-ProfileSchema -Profile $bad } | Should -Throw "*forbidden secret field*"
    }

    It "NP-PROFILE-007: invalid base url / credential source are rejected" {
        { New-ProviderProfile -WorkerId $script:workerId -ProfileId ("bad-url-" + $script:suffix) `
            -BaseUrl "not-a-url" -ModelId "m" -CodexHome $script:codexHome } | Should -Throw "*base_url*"
        { New-ProviderProfile -WorkerId $script:workerId -ProfileId ("bad-cred-" + $script:suffix) `
            -BaseUrl "https://x" -ModelId "m" -CredentialSource "file:/tmp/key" -CodexHome $script:codexHome } |
            Should -Throw "*credential_source*"
    }
}

Describe "NP-CRED: credential store contract" {
    It "NP-CRED-001: stdin secret input returns the value without echoing it" {
        $reader = [System.IO.StringReader]::new($script:secret)
        [Console]::SetIn($reader)
        $value = Read-SecretFromStdin
        $value | Should -Be $script:secret
        $reader.Dispose()
    }

    It "NP-CRED-002: stdin-sourced value can be set non-interactively" {
        $reader = [System.IO.StringReader]::new($script:secret)
        [Console]::SetIn($reader)
        $value = Read-SecretFromStdin
        $reader.Dispose()
        $result = Set-Credential -Source $script:sourceA -Value $value -Scope "Process"
        $result.present | Should -BeTrue
        (Test-CredentialPresence -Source $script:sourceA -Scope "Process").present | Should -BeTrue
    }

    It "NP-CRED-004: JSON and profile outputs never contain the secret" {
        $presence = Test-CredentialPresence -Source $script:sourceA -Scope "Process"
        $json = $presence | ConvertTo-Json -Depth 3
        Test-SecretPresentInText -Text $json -Secret $script:secret | Should -BeFalse
        $file = Join-Path $script:codexHome "relay\native-providers\profiles\$($script:profileA).json"
        Test-SecretPresentInText -Text (Get-Content -Raw -LiteralPath $file) -Secret $script:secret | Should -BeFalse
    }

    It "NP-CRED-005: presence report carries source and boolean only" {
        $presence = Test-CredentialPresence -Source $script:sourceA -Scope "Process"
        $presence.present | Should -BeOfType [bool]
        $presence.source | Should -Be $script:sourceA
        $presence.detail | Should -Match "presence checked"
        ($presence.present.ToString() + $presence.source + $presence.detail) | Should -Not -Match [regex]::Escape($script:secret)
    }

    It "NP-CRED-006: removing one credential leaves other profiles' credentials intact" {
        $otherId = "cred-only-" + $script:suffix
        $otherSource = "env:" + (New-StableCredentialEnvName -ProfileId $otherId)
        Set-Credential -Source $otherSource -Value $script:secret -Scope "Process" | Out-Null
        Remove-Credential -Source $script:sourceA -Scope "Process" | Out-Null
        (Test-CredentialPresence -Source $otherSource -Scope "Process").present | Should -BeTrue
        (Test-CredentialPresence -Source $script:sourceA -Scope "Process").present | Should -BeFalse
    }

    It "NP-CRED-007: failure exceptions never contain the input secret" {
        try {
            Set-Credential -Source "not-a-valid-source" -Value $script:secret -Scope "Process"
            throw "expected failure did not happen"
        }
        catch {
            $_.Exception.Message | Should -Not -Match [regex]::Escape($script:secret)
        }
    }
}
