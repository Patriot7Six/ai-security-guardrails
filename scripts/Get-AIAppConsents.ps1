#Requires -Version 7.2
<#
.SYNOPSIS
Inventories the apps that hold consent in a Microsoft Entra ID tenant and flags the AI tools among them.

.DESCRIPTION
Reads service principals, delegated permission grants, application permission
assignments, the user consent setting, and the admin consent workflow. Scores
each grant and writes findings.csv, findings.json, and report.md.

This script never writes to the tenant. A live run signs in with read-only
Microsoft Graph scopes and sends GET requests only. An offline run reads a
snapshot file and makes no network calls.

.PARAMETER SnapshotPath
Snapshot JSON to analyze offline, such as ./samples/contoso-tenant.json.

.PARAMETER TenantId
Tenant to sign in to for a live run. Defaults to the account's home tenant.

.PARAMETER TenantLabel
Friendly tenant name for the report.

.PARAMETER SaveSnapshotPath
Where to save the live snapshot for later offline runs. The file holds
directory data, so keep it out of source control.

.PARAMETER OutputDirectory
Folder for the report files. Defaults to ./out.

.PARAMETER IncludeNonAI
Score every non-Microsoft app, not only the ones that match the AI watchlist.

.PARAMETER WatchlistPath
Alternate AI watchlist. Defaults to config/ai-app-watchlist.json.

.PARAMETER RiskConfigPath
Alternate permission weights. Defaults to config/permission-risk.json.

.PARAMETER PassThru
Also write the findings to the pipeline.

.EXAMPLE
./scripts/Get-AIAppConsents.ps1 -SnapshotPath ./samples/contoso-tenant.json -OutputDirectory ./out

.EXAMPLE
./scripts/Get-AIAppConsents.ps1 -TenantId contoso.onmicrosoft.com -SaveSnapshotPath ./contoso.snapshot.json
#>
[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Offline')]
    [string] $SnapshotPath,

    [Parameter(ParameterSetName = 'Live')]
    [string] $TenantId,

    [Parameter(ParameterSetName = 'Live')]
    [string] $TenantLabel,

    [Parameter(ParameterSetName = 'Live')]
    [string] $SaveSnapshotPath,

    [string] $OutputDirectory = './out',

    [switch] $IncludeNonAI,

    [string] $WatchlistPath,

    [string] $RiskConfigPath,

    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src/AIGuardrails/AIGuardrails.psd1') -Force

if (-not $WatchlistPath) {
    $WatchlistPath = Join-Path -Path $repoRoot -ChildPath 'config/ai-app-watchlist.json'
}
if (-not $RiskConfigPath) {
    $RiskConfigPath = Join-Path -Path $repoRoot -ChildPath 'config/permission-risk.json'
}
$watchlist = Get-Content -LiteralPath $WatchlistPath -Raw | ConvertFrom-Json
$riskConfig = Get-Content -LiteralPath $RiskConfigPath -Raw | ConvertFrom-Json

if ($PSCmdlet.ParameterSetName -eq 'Offline') {
    $snapshot = Import-AIGTenantSnapshot -Path $SnapshotPath
}
else {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'A live run needs the Microsoft.Graph.Authentication module. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }
    Import-Module -Name Microsoft.Graph.Authentication
    $connect = @{
        Scopes    = @('Application.Read.All', 'Directory.Read.All', 'Policy.Read.All')
        NoWelcome = $true
    }
    if ($TenantId) {
        $connect.TenantId = $TenantId
    }
    $null = Connect-MgGraph @connect
    $snapshot = Get-AIGTenantSnapshot -TenantLabel $TenantLabel -FirstPartyTenantIds @($watchlist.firstPartyTenantIds)
    if ($SaveSnapshotPath) {
        $snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SaveSnapshotPath -Encoding utf8
        Write-Warning "Saved the snapshot to $SaveSnapshotPath. It holds directory data such as app names and user object IDs. Store it like any other directory export and keep it out of source control."
    }
}

$findings = @(Get-AIGConsentFinding -Snapshot $snapshot -Watchlist $watchlist -RiskConfig $riskConfig -IncludeNonAI:$IncludeNonAI)
$paths = Export-AIGReport -Finding $findings -Snapshot $snapshot -OutputDirectory $OutputDirectory
$consent = Get-AIGUserConsentState -AuthorizationPolicy $snapshot.authorizationPolicy
$workflowState = if ($snapshot.adminConsentRequestPolicy.isEnabled) { 'on' } else { 'off' }

$byLevel = foreach ($level in 'Critical', 'High', 'Medium', 'Low') {
    "$level $(@($findings | Where-Object { $_.Level -eq $level }).Count)"
}

# Plain lines, so the summary also shows up in CI logs and redirected output.
"User consent: $($consent.Mode). $($consent.Description)" | Out-Host
"Admin consent workflow: $workflowState." | Out-Host
"Findings: $($findings.Count) ($($byLevel -join ', '))." | Out-Host
"Report: $($paths.Markdown)" | Out-Host

if ($PassThru) {
    $findings
}
