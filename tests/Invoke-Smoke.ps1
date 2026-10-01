#Requires -Version 7.2
<#
.SYNOPSIS
Runs the offline demo end to end and checks the results with plain assertions.

.DESCRIPTION
Covers the same ground as the Pester suite for machines without Pester, and
also runs both scripts in a child process to check their console output and
exit codes. CI runs it after the Pester suite. Exits with code 1 if any check
fails and with code 0 when all checks pass.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/AIGuardrails/AIGuardrails.psd1') -Force

$script:failures = [System.Collections.Generic.List[string]]::new()
$script:checks = 0

function Assert-AIGCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Condition
    )

    $script:checks++
    if (-not $Condition) {
        $script:failures.Add($Name)
    }
}

$snapshotPath = Join-Path -Path $repoRoot -ChildPath 'samples/contoso-tenant.json'
$snapshot = Import-AIGTenantSnapshot -Path $snapshotPath
$watchlist = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/ai-app-watchlist.json') -Raw | ConvertFrom-Json
$riskConfig = Get-Content -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'config/permission-risk.json') -Raw | ConvertFrom-Json

# Consent policy update
$current = @(
    'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
    'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
    'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-chat'
)
$disabled = Get-AIGPermissionGrantPolicyUpdate -Current $current -Mode Disabled
Assert-AIGCheck -Name 'Disabled keeps both owned resource entries' -Condition ($disabled.Count -eq 2)
Assert-AIGCheck -Name 'Disabled drops the legacy self entry' -Condition ($disabled -notcontains $current[0])
Assert-AIGCheck -Name 'Disabled keeps the original casing' -Condition ($disabled[0] -ceq $current[1])
$low = Get-AIGPermissionGrantPolicyUpdate -Current $current -Mode LowRiskVerified
Assert-AIGCheck -Name 'LowRiskVerified puts the low impact policy first' -Condition ($low[0] -ceq 'managePermissionGrantsForSelf.microsoft-user-default-low')
Assert-AIGCheck -Name 'LowRiskVerified keeps the owned resource entries' -Condition ($low.Count -eq 3)
$selfOnly = Get-AIGPermissionGrantPolicyUpdate -Current @($current[0]) -Mode Disabled
Assert-AIGCheck -Name 'Disabled with only a self entry returns an empty list' -Condition ($selfOnly.Count -eq 0)
$dedupe = Get-AIGPermissionGrantPolicyUpdate -Current @('ManagePermissionGrantsForOwnedResource.x', 'managePermissionGrantsForOwnedResource.X') -Mode Disabled
Assert-AIGCheck -Name 'Duplicate entries are removed without regard to case' -Condition ($dedupe.Count -eq 1)

# User consent state
Assert-AIGCheck -Name 'Sample tenant reads as AllApps' -Condition ((Get-AIGUserConsentState -AuthorizationPolicy $snapshot.authorizationPolicy).Mode -eq 'AllApps')
$cases = [ordered]@{
    'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team' = 'Disabled'
    'ManagePermissionGrantsForSelf.microsoft-user-default-low'                                 = 'LowRiskVerified'
    'managePermissionGrantsForSelf.microsoft-user-default-recommended'                         = 'MicrosoftManaged'
    'ManagePermissionGrantsForSelf.contoso-custom-policy'                                      = 'Custom'
}
foreach ($case in $cases.GetEnumerator()) {
    $policy = [pscustomobject]@{
        defaultUserRolePermissions = [pscustomobject]@{
            permissionGrantPoliciesAssigned = @($case.Key)
        }
    }
    $mode = (Get-AIGUserConsentState -AuthorizationPolicy $policy).Mode
    Assert-AIGCheck -Name "Consent state for $($case.Key) is $($case.Value)" -Condition ($mode -eq $case.Value)
}

# AI app matching
$vendorApp = [pscustomobject]@{
    displayName       = 'Example OpenAI Connector'
    publisherName     = 'Example Corp'
    verifiedPublisher = $null
}
$vendorMatch = Test-AIGAIApp -ServicePrincipal $vendorApp -Watchlist $watchlist
Assert-AIGCheck -Name 'Vendor pattern wins over generic patterns' -Condition ($vendorMatch.Strength -eq 'Vendor' -and $vendorMatch.Pattern -eq '\bOpenAI\b')
$dataChat = $snapshot.servicePrincipals | Where-Object { $_.displayName -eq 'DataChat Analyst' }
$publisherMatch = Test-AIGAIApp -ServicePrincipal $dataChat -Watchlist $watchlist
Assert-AIGCheck -Name 'Publisher name match for DataChat Analyst' -Condition ($publisherMatch.MatchedOn -eq 'publisherName')
$plainApp = [pscustomobject]@{
    displayName       = 'Daily Training Portal'
    publisherName     = 'Maintain Corp'
    verifiedPublisher = $null
}
Assert-AIGCheck -Name 'No match on AI letters inside a word' -Condition ($null -eq (Test-AIGAIApp -ServicePrincipal $plainApp -Watchlist $watchlist))

# Scoring
$capped = Measure-AIGPermissionRisk -GrantType Application -Permission @('full_access_as_app', 'Directory.ReadWrite.All', 'Mail.ReadWrite') -RiskConfig $riskConfig -UnverifiedPublisher
Assert-AIGCheck -Name 'Score caps at 100' -Condition ($capped.Score -eq 100)
$basic = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('openid', 'profile', 'User.Read', 'offline_access') -RiskConfig $riskConfig
Assert-AIGCheck -Name 'Basic sign-in scopes score 0' -Condition ($basic.Score -eq 0 -and $basic.Level -eq 'Low')
$withoutOffline = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('Mail.Read') -RiskConfig $riskConfig
$withOffline = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('Mail.Read', 'offline_access') -RiskConfig $riskConfig
Assert-AIGCheck -Name 'offline_access adds 10 next to a sensitive permission' -Condition (($withOffline.Score - $withoutOffline.Score) -eq 10)
$lowerCase = Measure-AIGPermissionRisk -GrantType Delegated -Permission @('mail.read') -RiskConfig $riskConfig
Assert-AIGCheck -Name 'Permission names match without regard to case' -Condition ($lowerCase.Score -eq 30)

# Findings against the sample tenant
$findings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig)
$allFindings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig -IncludeNonAI)
Assert-AIGCheck -Name 'Seven AI findings' -Condition ($findings.Count -eq 7)
Assert-AIGCheck -Name 'Nine findings with -IncludeNonAI' -Condition ($allFindings.Count -eq 9)
Assert-AIGCheck -Name 'Microsoft Teams is skipped as first-party' -Condition ($allFindings.AppDisplayName -notcontains 'Microsoft Teams')
$expected = [ordered]@{
    'SupportBot GPT Connector'   = 'Critical/90'
    'InboxPilot AI'              = 'Critical/85'
    'DataChat Analyst'           = 'Critical/80'
    'Summarize Everything'       = 'High/65'
    'Contoso CareDesk Assistant' = 'High/55'
    'NoteGenie AI Meeting Notes' = 'Medium/40'
    'FieldOps Scheduler'         = 'Medium/35'
    'Payroll Portal SSO'         = 'Low/15'
    'QuickDraft AI Writer'       = 'Low/0'
}
foreach ($entry in $expected.GetEnumerator()) {
    $finding = $allFindings | Where-Object { $_.AppDisplayName -eq $entry.Key }
    $actual = if ($finding) { "$($finding.Level)/$($finding.Score)" } else { 'missing' }
    Assert-AIGCheck -Name "$($entry.Key) scores $($entry.Value) (got $actual)" -Condition ($actual -eq $entry.Value)
}
$scores = @($findings.Score)
Assert-AIGCheck -Name 'Findings sort by score, highest first' -Condition (($scores -join ',') -eq (@($scores | Sort-Object -Descending) -join ','))
$careDesk = $findings | Where-Object { $_.AppDisplayName -eq 'Contoso CareDesk Assistant' }
Assert-AIGCheck -Name 'In-tenant app is Internal' -Condition ($careDesk.PublisherStatus -eq 'Internal')
$noteGenie = $findings | Where-Object { $_.AppDisplayName -eq 'NoteGenie AI Meeting Notes' }
Assert-AIGCheck -Name 'NoteGenie has 12 distinct users' -Condition ($noteGenie.UserCount -eq 12)
$dataChatFinding = $findings | Where-Object { $_.AppDisplayName -eq 'DataChat Analyst' }
Assert-AIGCheck -Name 'DataChat has 14 distinct users' -Condition ($dataChatFinding.UserCount -eq 14)
$supportBot = $findings | Where-Object { $_.AppDisplayName -eq 'SupportBot GPT Connector' }
Assert-AIGCheck -Name 'App role resolves to full_access_as_app' -Condition ($supportBot.Permissions -contains 'full_access_as_app' -and $supportBot.GrantType -eq 'Application')
Assert-AIGCheck -Name 'EWS retirement note on full_access_as_app' -Condition (@($supportBot.Notes).Count -eq 1 -and $supportBot.Notes[0] -like '*Exchange Web Services*')

# Admin consent workflow body
$body = Get-AIGAdminConsentRequestPolicyBody -ReviewerUserId ([guid] '11111111-2222-4333-8444-555555555555')
Assert-AIGCheck -Name 'Workflow body is enabled with a 7 day default' -Condition ($body.isEnabled -and $body.requestDurationInDays -eq 7)
Assert-AIGCheck -Name 'Workflow reviewer uses a /users query' -Condition ($body.reviewers.Count -eq 1 -and $body.reviewers[0].query -eq '/users/11111111-2222-4333-8444-555555555555' -and $body.reviewers[0].queryType -eq 'MicrosoftGraph')
$rejected = $false
try {
    $null = Get-AIGAdminConsentRequestPolicyBody -ReviewerUserId ([guid]::NewGuid()) -RequestDurationInDays 0
}
catch {
    $rejected = $true
}
Assert-AIGCheck -Name 'Workflow body rejects 0 days' -Condition $rejected

# Report files
$workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('aig-smoke-' + [guid]::NewGuid().ToString('N'))
$paths = Export-AIGReport -Finding $findings -Snapshot $snapshot -OutputDirectory (Join-Path -Path $workDir -ChildPath 'report')
foreach ($file in $paths.Csv, $paths.Json, $paths.Markdown) {
    Assert-AIGCheck -Name "Report file exists: $(Split-Path -Path $file -Leaf)" -Condition (Test-Path -LiteralPath $file)
}
Assert-AIGCheck -Name 'CSV has one row per finding' -Condition (@(Import-Csv -LiteralPath $paths.Csv).Count -eq 7)
$markdown = Get-Content -LiteralPath $paths.Markdown -Raw
Assert-AIGCheck -Name 'Report names the legacy setting' -Condition ($markdown -match 'legacy setting')
Assert-AIGCheck -Name 'Report is plain ASCII' -Condition ($markdown -notmatch '[^\x00-\x7F]')
$emptyPaths = Export-AIGReport -Finding @() -Snapshot $snapshot -OutputDirectory (Join-Path -Path $workDir -ChildPath 'empty')
Assert-AIGCheck -Name 'Empty CSV still has a header' -Condition ((Get-Content -LiteralPath $emptyPaths.Csv -Raw) -match '"Level"')

# Scripts, run in a child process to check console output and exit codes
$pwsh = (Get-Process -Id $PID).Path
$inventoryScript = Join-Path -Path $repoRoot -ChildPath 'scripts/Get-AIAppConsents.ps1'
$policyScript = Join-Path -Path $repoRoot -ChildPath 'scripts/Set-AppConsentPolicy.ps1'
$scriptOut = Join-Path -Path $workDir -ChildPath 'script-out'

$inventoryOutput = (& $pwsh -NoLogo -NoProfile -File $inventoryScript -SnapshotPath $snapshotPath -OutputDirectory $scriptOut 2>&1) -join "`n"
Assert-AIGCheck -Name 'Inventory script exits 0' -Condition ($LASTEXITCODE -eq 0)
Assert-AIGCheck -Name 'Inventory script prints the consent mode' -Condition ($inventoryOutput -match 'User consent: AllApps')
Assert-AIGCheck -Name 'Inventory script prints the finding counts' -Condition ($inventoryOutput -match 'Findings: 7 \(Critical 3, High 2, Medium 1, Low 1\)')
foreach ($file in 'findings.csv', 'findings.json', 'report.md') {
    Assert-AIGCheck -Name "Inventory script writes $file" -Condition (Test-Path -LiteralPath (Join-Path -Path $scriptOut -ChildPath $file))
}

$planOutput = (& $pwsh -NoLogo -NoProfile -File $policyScript -SnapshotPath $snapshotPath -UserConsent LowRiskVerified 2>&1) -join "`n"
Assert-AIGCheck -Name 'Plan mode exits 0' -Condition ($LASTEXITCODE -eq 0)
Assert-AIGCheck -Name 'Plan mode says nothing is sent' -Condition ($planOutput -match 'Nothing is sent')
Assert-AIGCheck -Name 'Plan mode shows the low impact policy' -Condition ($planOutput -match 'microsoft-user-default-low')
Assert-AIGCheck -Name 'Plan mode keeps the team entry' -Condition ($planOutput -match 'permissions-for-team')

$disableOutput = (& $pwsh -NoLogo -NoProfile -File $policyScript -SnapshotPath $snapshotPath -UserConsent Disabled 2>&1) -join "`n"
Assert-AIGCheck -Name 'Disabled plan drops the legacy entry from the body' -Condition (($disableOutput -split 'Planned request')[1] -notmatch 'default-legacy')

$null = & $pwsh -NoLogo -NoProfile -File $policyScript -SnapshotPath $snapshotPath 2>&1
Assert-AIGCheck -Name 'Plan mode with nothing to change exits non-zero' -Condition ($LASTEXITCODE -ne 0)
$null = & $pwsh -NoLogo -NoProfile -File $policyScript -SnapshotPath $snapshotPath -EnableAdminConsentWorkflow 2>&1
Assert-AIGCheck -Name 'Workflow without a reviewer exits non-zero' -Condition ($LASTEXITCODE -ne 0)

Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue

"$($script:checks - $script:failures.Count) of $($script:checks) checks passed." | Out-Host
if ($script:failures.Count -gt 0) {
    $script:failures | ForEach-Object { "FAILED: $_" } | Out-Host
    exit 1
}

# The last child process above exits non-zero on purpose. Exit 0 here so a
# caller that reads $LASTEXITCODE, as the GitHub Actions pwsh shell does, gets
# the result of the checks and not the exit code of that child.
exit 0
