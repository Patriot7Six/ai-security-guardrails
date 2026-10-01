#Requires -Version 7.2
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares variables between BeforeAll and It blocks.')]
param()

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/AIGuardrails/AIGuardrails.psd1') -Force
    $snapshotPath = Join-Path -Path $repoRoot -ChildPath 'samples/contoso-tenant.json'
    $snapshot = Import-AIGTenantSnapshot -Path $snapshotPath
    $watchlist = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/ai-app-watchlist.json') -Raw | ConvertFrom-Json
    $riskConfig = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/permission-risk.json') -Raw | ConvertFrom-Json
}

Describe 'Get-AIGPermissionGrantPolicyUpdate' {
    It 'drops self consent entries and keeps owned resource entries for Disabled' {
        $current = @(
            'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
            'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
            'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-chat'
        )
        $result = Get-AIGPermissionGrantPolicyUpdate -Current $current -Mode Disabled
        $result.Count | Should -Be 2
        $result | Should -Not -Contain 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
        $result[0] | Should -BeExactly 'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
    }

    It 'puts the low impact policy first for LowRiskVerified' {
        $current = @(
            'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
            'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
        )
        $result = Get-AIGPermissionGrantPolicyUpdate -Current $current -Mode LowRiskVerified
        $result.Count | Should -Be 2
        $result[0] | Should -BeExactly 'managePermissionGrantsForSelf.microsoft-user-default-low'
    }

    It 'returns an empty list when only a self consent entry was assigned' {
        $result = Get-AIGPermissionGrantPolicyUpdate -Current @('ManagePermissionGrantsForSelf.microsoft-user-default-legacy') -Mode Disabled
        $result.Count | Should -Be 0
    }

    It 'removes duplicate entries without regard to case' {
        $result = Get-AIGPermissionGrantPolicyUpdate -Current @('ManagePermissionGrantsForOwnedResource.x', 'managePermissionGrantsForOwnedResource.X') -Mode Disabled
        $result.Count | Should -Be 1
    }
}

Describe 'Get-AIGUserConsentState' {
    It 'reads the legacy setting in the sample tenant as AllApps' {
        (Get-AIGUserConsentState -AuthorizationPolicy $snapshot.authorizationPolicy).Mode | Should -Be 'AllApps'
    }

    It 'reports <Expected> for <Assigned>' -ForEach @(
        @{
            Assigned = 'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
            Expected = 'Disabled'
        }
        @{
            Assigned = 'ManagePermissionGrantsForSelf.microsoft-user-default-low'
            Expected = 'LowRiskVerified'
        }
        @{
            Assigned = 'managePermissionGrantsForSelf.microsoft-user-default-recommended'
            Expected = 'MicrosoftManaged'
        }
        @{
            Assigned = 'ManagePermissionGrantsForSelf.contoso-custom-policy'
            Expected = 'Custom'
        }
    ) {
        $policy = [pscustomobject]@{
            defaultUserRolePermissions = [pscustomobject]@{
                permissionGrantPoliciesAssigned = @($Assigned)
            }
        }
        (Get-AIGUserConsentState -AuthorizationPolicy $policy).Mode | Should -Be $Expected
    }
}

Describe 'Test-AIGAIApp' {
    It 'checks vendor patterns before generic ones' {
        $servicePrincipal = [pscustomobject]@{
            displayName       = 'Example OpenAI Connector'
            publisherName     = 'Example Corp'
            verifiedPublisher = $null
        }
        $result = Test-AIGAIApp -ServicePrincipal $servicePrincipal -Watchlist $watchlist
        $result.Strength | Should -Be 'Vendor'
        $result.Pattern | Should -Be '\bOpenAI\b'
        $result.MatchedOn | Should -Be 'displayName'
    }

    It 'matches on the publisher name when the display name has no AI terms' {
        $servicePrincipal = $snapshot.servicePrincipals | Where-Object { $_.displayName -eq 'DataChat Analyst' }
        $result = Test-AIGAIApp -ServicePrincipal $servicePrincipal -Watchlist $watchlist
        $result.Strength | Should -Be 'Name'
        $result.MatchedOn | Should -Be 'publisherName'
    }

    It 'does not match the letters AI inside a longer word' {
        $servicePrincipal = [pscustomobject]@{
            displayName       = 'Daily Training Portal'
            publisherName     = 'Maintain Corp'
            verifiedPublisher = $null
        }
        Test-AIGAIApp -ServicePrincipal $servicePrincipal -Watchlist $watchlist | Should -BeNullOrEmpty
    }
}

Describe 'Measure-AIGPermissionRisk' {
    It 'caps the score at 100' {
        $risk = Measure-AIGPermissionRisk -GrantType Application -Permission @('full_access_as_app', 'Directory.ReadWrite.All', 'Mail.ReadWrite') -RiskConfig $riskConfig -UnverifiedPublisher
        $risk.Score | Should -Be 100
        $risk.Level | Should -Be 'Critical'
    }

    It 'scores 0 when no permission is on the sensitive list' {
        $risk = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('openid', 'profile', 'User.Read', 'offline_access') -RiskConfig $riskConfig
        $risk.Score | Should -Be 0
        $risk.Level | Should -Be 'Low'
    }

    It 'adds the offline_access points only next to a sensitive permission' {
        $withoutOffline = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('Mail.Read') -RiskConfig $riskConfig
        $withOffline = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('Mail.Read', 'offline_access') -RiskConfig $riskConfig
        ($withOffline.Score - $withoutOffline.Score) | Should -Be 10
    }

    It 'matches permission names without regard to case' {
        (Measure-AIGPermissionRisk -GrantType Delegated -Permission @('mail.read') -RiskConfig $riskConfig).Score | Should -Be 30
    }
}

Describe 'Get-AIGConsentFinding against the sample tenant' {
    BeforeAll {
        $findings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig)
        $allFindings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig -IncludeNonAI)
    }

    It 'returns one finding per AI app' {
        $findings.Count | Should -Be 7
    }

    It 'adds the two non-AI apps with -IncludeNonAI' {
        $allFindings.Count | Should -Be 9
    }

    It 'skips Microsoft first-party apps' {
        $allFindings.AppDisplayName | Should -Not -Contain 'Microsoft Teams'
    }

    It 'scores <App> at <Score> (<Level>)' -ForEach @(
        @{
            App   = 'SupportBot GPT Connector'
            Score = 90
            Level = 'Critical'
        }
        @{
            App   = 'InboxPilot AI'
            Score = 85
            Level = 'Critical'
        }
        @{
            App   = 'DataChat Analyst'
            Score = 80
            Level = 'Critical'
        }
        @{
            App   = 'Summarize Everything'
            Score = 65
            Level = 'High'
        }
        @{
            App   = 'Contoso CareDesk Assistant'
            Score = 55
            Level = 'High'
        }
        @{
            App   = 'NoteGenie AI Meeting Notes'
            Score = 40
            Level = 'Medium'
        }
        @{
            App   = 'FieldOps Scheduler'
            Score = 35
            Level = 'Medium'
        }
        @{
            App   = 'Payroll Portal SSO'
            Score = 15
            Level = 'Low'
        }
        @{
            App   = 'QuickDraft AI Writer'
            Score = 0
            Level = 'Low'
        }
    ) {
        $finding = $allFindings | Where-Object { $_.AppDisplayName -eq $App }
        $finding | Should -Not -BeNullOrEmpty
        $finding.Score | Should -Be $Score
        $finding.Level | Should -Be $Level
    }

    It 'sorts by score, highest first' {
        $scores = @($findings.Score)
        $sorted = @($scores | Sort-Object -Descending)
        ($scores -join ',') | Should -Be ($sorted -join ',')
    }

    It 'marks the app registered in this tenant as Internal' {
        ($findings | Where-Object { $_.AppDisplayName -eq 'Contoso CareDesk Assistant' }).PublisherStatus | Should -Be 'Internal'
    }

    It 'counts distinct consenting users' {
        ($findings | Where-Object { $_.AppDisplayName -eq 'NoteGenie AI Meeting Notes' }).UserCount | Should -Be 12
        ($findings | Where-Object { $_.AppDisplayName -eq 'DataChat Analyst' }).UserCount | Should -Be 14
    }

    It 'resolves application permission names from the resource app roles' {
        $supportBot = $findings | Where-Object { $_.AppDisplayName -eq 'SupportBot GPT Connector' }
        $supportBot.GrantType | Should -Be 'Application'
        $supportBot.Permissions | Should -Contain 'full_access_as_app'
    }

    It 'adds the EWS retirement note to the full_access_as_app finding' {
        $supportBot = $findings | Where-Object { $_.AppDisplayName -eq 'SupportBot GPT Connector' }
        @($supportBot.Notes).Count | Should -Be 1
        $supportBot.Notes[0] | Should -BeLike '*Exchange Web Services*'
    }
}

Describe 'Get-AIGAdminConsentRequestPolicyBody' {
    It 'builds a request body with user reviewers' {
        $body = Get-AIGAdminConsentRequestPolicyBody -ReviewerUserId ([guid] '11111111-2222-4333-8444-555555555555')
        $body.isEnabled | Should -BeTrue
        $body.requestDurationInDays | Should -Be 7
        $body.reviewers.Count | Should -Be 1
        $body.reviewers[0].query | Should -Be '/users/11111111-2222-4333-8444-555555555555'
        $body.reviewers[0].queryType | Should -Be 'MicrosoftGraph'
    }

    It 'rejects a request duration of 0 days' {
        { Get-AIGAdminConsentRequestPolicyBody -ReviewerUserId ([guid]::NewGuid()) -RequestDurationInDays 0 } | Should -Throw
    }
}

Describe 'Import-AIGTenantSnapshot' {
    It 'rejects a snapshot that is missing a required section' {
        $path = Join-Path -Path $TestDrive -ChildPath 'broken.json'
        Set-Content -LiteralPath $path -Value '{"schemaVersion": 1, "tenantId": "x"}'
        { Import-AIGTenantSnapshot -Path $path } | Should -Throw -ExpectedMessage '*servicePrincipals*'
    }
}

Describe 'Export-AIGReport' {
    BeforeAll {
        $findings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig)
        $paths = Export-AIGReport -Finding $findings -Snapshot $snapshot -OutputDirectory (Join-Path -Path $TestDrive -ChildPath 'report')
    }

    It 'writes CSV, JSON, and Markdown files' {
        $paths.Csv | Should -Exist
        $paths.Json | Should -Exist
        $paths.Markdown | Should -Exist
    }

    It 'writes one CSV row per finding' {
        @(Import-Csv -LiteralPath $paths.Csv).Count | Should -Be 7
    }

    It 'reports the legacy consent setting' {
        Get-Content -LiteralPath $paths.Markdown -Raw | Should -Match 'legacy setting'
    }

    It 'keeps the report in plain ASCII' {
        Get-Content -LiteralPath $paths.Markdown -Raw | Should -Not -Match '[^\x00-\x7F]'
    }

    It 'writes a CSV header when there are no findings' {
        $emptyPaths = Export-AIGReport -Finding @() -Snapshot $snapshot -OutputDirectory (Join-Path -Path $TestDrive -ChildPath 'empty')
        Get-Content -LiteralPath $emptyPaths.Csv -Raw | Should -Match '"Level"'
    }
}

Describe 'Scripts in offline mode' {
    BeforeAll {
        $inventoryScript = Join-Path -Path $repoRoot -ChildPath 'scripts/Get-AIAppConsents.ps1'
        $policyScript = Join-Path -Path $repoRoot -ChildPath 'scripts/Set-AppConsentPolicy.ps1'
    }

    It 'Get-AIAppConsents.ps1 writes a report from a snapshot' {
        $outDir = Join-Path -Path $TestDrive -ChildPath 'script-out'
        & $inventoryScript -SnapshotPath $snapshotPath -OutputDirectory $outDir
        Join-Path -Path $outDir -ChildPath 'report.md' | Should -Exist
    }

    It 'Get-AIAppConsents.ps1 returns findings with -PassThru' {
        $result = @(& $inventoryScript -SnapshotPath $snapshotPath -OutputDirectory (Join-Path -Path $TestDrive -ChildPath 'passthru') -PassThru)
        $result.Count | Should -Be 7
    }

    It 'Set-AppConsentPolicy.ps1 stops when there is nothing to change' {
        { & $policyScript -SnapshotPath $snapshotPath } | Should -Throw -ExpectedMessage '*Nothing to change*'
    }

    It 'Set-AppConsentPolicy.ps1 stops when the workflow has no reviewer' {
        { & $policyScript -SnapshotPath $snapshotPath -EnableAdminConsentWorkflow } | Should -Throw -ExpectedMessage '*ReviewerUserId*'
    }

    It 'Set-AppConsentPolicy.ps1 plans a change without signing in' {
        { & $policyScript -SnapshotPath $snapshotPath -UserConsent LowRiskVerified -EnableAdminConsentWorkflow -ReviewerUserId ([guid]::NewGuid()) } | Should -Not -Throw
    }
}
