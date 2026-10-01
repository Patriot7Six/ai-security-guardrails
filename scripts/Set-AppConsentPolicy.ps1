#Requires -Version 7.2
<#
.SYNOPSIS
Restricts user consent and turns on the admin consent workflow in Microsoft Entra ID.

.DESCRIPTION
Plan mode (-SnapshotPath) shows the exact Microsoft Graph requests this script
would send, using the policy in a snapshot. It never signs in.

A live run signs in with only the write scopes the change needs, reads the
current policy, shows the change, and asks before each write. It then reads
the policy back to confirm. -WhatIf signs in and reads but writes nothing.

The user consent change keeps every ManagePermissionGrantsForOwnedResource
entry already assigned, so resource-specific consent for teams and chats
stays as it is.

.PARAMETER UserConsent
Disabled turns user consent off. LowRiskVerified lets users consent only to
apps from verified publishers or this tenant, for permissions classified as
low impact.

.PARAMETER EnableAdminConsentWorkflow
Turns on the admin consent workflow so users can request apps they cannot
consent to.

.PARAMETER ReviewerUserId
Object IDs of the users who review consent requests.

.PARAMETER RequestDurationInDays
Days a request stays open before it expires. The script defaults to 7 and
accepts 1 to 365. Microsoft documents neither a default nor a range.

.PARAMETER TenantId
Tenant to sign in to for a live run.

.PARAMETER SnapshotPath
Snapshot to plan against. Runs in plan mode.

.EXAMPLE
./scripts/Set-AppConsentPolicy.ps1 -SnapshotPath ./samples/contoso-tenant.json -UserConsent LowRiskVerified

.EXAMPLE
./scripts/Set-AppConsentPolicy.ps1 -UserConsent Disabled -EnableAdminConsentWorkflow -ReviewerUserId 00000000-0000-0000-0000-000000000000 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Live')]
param(
    [ValidateSet('Disabled', 'LowRiskVerified')]
    [string] $UserConsent,

    [switch] $EnableAdminConsentWorkflow,

    [guid[]] $ReviewerUserId,

    [ValidateRange(1, 365)]
    [int] $RequestDurationInDays = 7,

    [Parameter(ParameterSetName = 'Live')]
    [string] $TenantId,

    [Parameter(Mandatory, ParameterSetName = 'Plan')]
    [string] $SnapshotPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/AIGuardrails/AIGuardrails.psd1') -Force

if (-not $UserConsent -and -not $EnableAdminConsentWorkflow) {
    throw 'Nothing to change. Pass -UserConsent, -EnableAdminConsentWorkflow, or both.'
}
if ($EnableAdminConsentWorkflow -and @($ReviewerUserId).Count -eq 0) {
    throw '-EnableAdminConsentWorkflow needs at least one -ReviewerUserId. Without a reviewer, requests have nowhere to go.'
}

$live = $PSCmdlet.ParameterSetName -eq 'Live'
if ($live) {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'A live run needs the Microsoft.Graph.Authentication module. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }
    Import-Module -Name Microsoft.Graph.Authentication
    $scopes = [System.Collections.Generic.List[string]]::new()
    if ($UserConsent) {
        $scopes.Add('Policy.ReadWrite.Authorization')
    }
    if ($EnableAdminConsentWorkflow) {
        $scopes.Add('Policy.ReadWrite.ConsentRequest')
    }
    $connect = @{
        Scopes    = $scopes.ToArray()
        NoWelcome = $true
    }
    if ($TenantId) {
        $connect.TenantId = $TenantId
    }
    $null = Connect-MgGraph @connect
}
else {
    $snapshot = Import-AIGTenantSnapshot -Path $SnapshotPath
    'Plan mode. Nothing is sent to Microsoft Graph.' | Out-Host
}

if ($UserConsent) {
    $authorizationPolicy = if ($live) {
        Invoke-MgGraphRequest -Method GET -Uri '/v1.0/policies/authorizationPolicy' -OutputType PSObject
    }
    else {
        $snapshot.authorizationPolicy
    }
    $before = Get-AIGUserConsentState -AuthorizationPolicy $authorizationPolicy
    $current = [string[]] @($authorizationPolicy.defaultUserRolePermissions.permissionGrantPoliciesAssigned | Where-Object { $_ })
    $updated = Get-AIGPermissionGrantPolicyUpdate -Current $current -Mode $UserConsent
    $body = @{
        defaultUserRolePermissions = @{
            permissionGrantPoliciesAssigned = [string[]] $updated
        }
    }
    $bodyJson = $body | ConvertTo-Json -Depth 5

    "User consent now: $($before.Mode). $($before.Description)" | Out-Host
    'Planned request: PATCH /v1.0/policies/authorizationPolicy' | Out-Host
    $bodyJson | Out-Host

    if ($live -and $PSCmdlet.ShouldProcess('authorizationPolicy', "Set user consent to $UserConsent")) {
        $null = Invoke-MgGraphRequest -Method PATCH -Uri '/v1.0/policies/authorizationPolicy' -Body $bodyJson -ContentType 'application/json'
        $after = Invoke-MgGraphRequest -Method GET -Uri '/v1.0/policies/authorizationPolicy' -OutputType PSObject
        $afterState = Get-AIGUserConsentState -AuthorizationPolicy $after
        "User consent after the change: $($afterState.Mode)." | Out-Host
        if ($afterState.Mode -ne $UserConsent) {
            Write-Warning "Expected $UserConsent but read back $($afterState.Mode). Check the policy in the Entra admin center."
        }
    }
}

if ($EnableAdminConsentWorkflow) {
    $workflowBefore = if ($live) {
        Invoke-MgGraphRequest -Method GET -Uri '/v1.0/policies/adminConsentRequestPolicy' -OutputType PSObject
    }
    else {
        $snapshot.adminConsentRequestPolicy
    }
    $workflowState = if ($workflowBefore.isEnabled) { 'on' } else { 'off' }
    $workflowBody = Get-AIGAdminConsentRequestPolicyBody -ReviewerUserId $ReviewerUserId -RequestDurationInDays $RequestDurationInDays
    $workflowJson = $workflowBody | ConvertTo-Json -Depth 5

    "Admin consent workflow now: $workflowState." | Out-Host
    'Planned request: PUT /v1.0/policies/adminConsentRequestPolicy' | Out-Host
    $workflowJson | Out-Host

    if ($live -and $PSCmdlet.ShouldProcess('adminConsentRequestPolicy', 'Turn on the admin consent workflow')) {
        $null = Invoke-MgGraphRequest -Method PUT -Uri '/v1.0/policies/adminConsentRequestPolicy' -Body $workflowJson -ContentType 'application/json'
        $workflowAfter = Invoke-MgGraphRequest -Method GET -Uri '/v1.0/policies/adminConsentRequestPolicy' -OutputType PSObject
        "Admin consent workflow after the change: enabled $($workflowAfter.isEnabled), $(@($workflowAfter.reviewers).Count) reviewer(s)." | Out-Host
        if (-not $workflowAfter.isEnabled) {
            Write-Warning 'The admin consent workflow still reads as off. Check the policy in the Entra admin center.'
        }
    }
}
