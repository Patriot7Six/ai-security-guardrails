#Requires -Version 7.2

# AIGuardrails: read, score, and plan changes to app consent in Microsoft Entra ID.
# Nothing in this module writes to a tenant. The scripts in ./scripts are the only
# code that does, and they support -WhatIf.

#region Internal helpers

function ConvertTo-AIGLookup {
    # Turns a JSON object or dictionary into a hashtable with case-insensitive keys.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [object] $InputObject
    )

    $table = @{}
    if ($null -eq $InputObject) {
        return $table
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $table[[string] $key] = $InputObject[$key]
        }
        return $table
    }
    foreach ($property in $InputObject.PSObject.Properties) {
        $table[$property.Name] = $property.Value
    }
    return $table
}

function Format-AIGTimestamp {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Value
    )

    $format = "yyyy-MM-dd HH:mm 'UTC'"
    $culture = [cultureinfo]::InvariantCulture
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString($format, $culture)
    }
    if ($Value -is [datetimeoffset]) {
        return $Value.UtcDateTime.ToString($format, $culture)
    }
    if ($Value) {
        $parsed = [datetimeoffset]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetimeoffset]::TryParse([string] $Value, $culture, $styles, [ref] $parsed)) {
            return $parsed.UtcDateTime.ToString($format, $culture)
        }
        return [string] $Value
    }
    return 'unknown'
}

function Format-AIGCount {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [string] $Singular,

        [Parameter(Mandatory)]
        [string] $Plural
    )

    if ($Count -eq 1) {
        return "1 $Singular"
    }
    return "$Count $Plural"
}

function Format-AIGCell {
    # Makes a value safe for a Markdown table cell.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    return ([string] $Text).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Invoke-AIGGraphPaged {
    # Sends a GET request to Microsoft Graph and follows @odata.nextLink to the last page.
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Uri
    )

    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        foreach ($item in @($page.value)) {
            if ($null -ne $item) {
                $results.Add($item)
            }
        }
        $next = $page.'@odata.nextLink'
    }
    return , $results.ToArray()
}

function Get-AIGRecommendedAction {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Level,

        [Parameter(Mandatory)]
        [ValidateSet('Delegated', 'Application')]
        [string] $GrantType,

        [Parameter(Mandatory)]
        [bool] $IsAIApp
    )

    $target = if ($GrantType -eq 'Application') { 'the app role assignment' } else { 'the grant' }
    switch ($Level) {
        'Critical' {
            return "Confirm the business owner and data flow today. If there is no approved use, remove $target and disable sign-in for the app."
        }
        'High' {
            $review = if ($IsAIApp) { 'Run the AI tool risk assessment this week.' } else { 'Review the business need this week.' }
            $limit = if ($GrantType -eq 'Application') {
                'Scope the permission to named sites or mailboxes (Sites.Selected for SharePoint, RBAC for Applications in Exchange Online) or remove it.'
            }
            else {
                'Require user assignment for the app or remove the grant.'
            }
            return "$review $limit"
        }
        'Medium' {
            if ($IsAIApp) {
                return 'Review at the next access review and confirm the app is on the AI tool register.'
            }
            return 'Review at the next access review.'
        }
        default {
            return 'Keep on the inventory. No change needed.'
        }
    }
}

function Get-AIGRemovalHint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Delegated', 'Application')]
        [string] $GrantType,

        [Parameter(Mandatory)]
        [string] $ServicePrincipalId,

        [Parameter(Mandatory)]
        [string[]] $GrantId
    )

    $template = if ($GrantType -eq 'Delegated') {
        'v1.0/oauth2PermissionGrants/{0}'
    }
    else {
        "v1.0/servicePrincipals/$ServicePrincipalId/appRoleAssignments/{0}"
    }
    if ($GrantId.Count -eq 1) {
        return "Invoke-MgGraphRequest -Method DELETE -Uri '$($template -f $GrantId[0])'"
    }
    $list = ($GrantId | ForEach-Object { "'$_'" }) -join ', '
    $loopUri = $template -f '$_'
    return "$list | ForEach-Object { Invoke-MgGraphRequest -Method DELETE -Uri ""$loopUri"" }"
}

function ConvertTo-AIGFinding {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $ServicePrincipal,

        [AllowNull()]
        [object] $Resource,

        [Parameter(Mandatory)]
        [string] $ResourceId,

        [Parameter(Mandatory)]
        [object] $Publisher,

        [AllowNull()]
        [object] $AIMatch,

        [Parameter(Mandatory)]
        [ValidateSet('Delegated', 'Application')]
        [string] $GrantType,

        [Parameter(Mandatory)]
        [ValidateSet('AllUsers', 'SomeUsers', 'AppOnly')]
        [string] $ConsentScope,

        [int] $UserCount = 0,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Permission,

        [Parameter(Mandatory)]
        [object] $Risk,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Note,

        [Parameter(Mandatory)]
        [string[]] $GrantId,

        [Parameter(Mandatory)]
        [string] $RemovalHint
    )

    $isAI = $null -ne $AIMatch
    $matchText = if ($isAI) { "{0} pattern '{1}' on {2}" -f $AIMatch.Strength, $AIMatch.Pattern, $AIMatch.MatchedOn } else { $null }
    $resourceName = if ($null -ne $Resource -and $Resource.displayName) { [string] $Resource.displayName } else { "Unknown resource $ResourceId" }
    $action = Get-AIGRecommendedAction -Level $Risk.Level -GrantType $GrantType -IsAIApp $isAI

    [pscustomobject]@{
        AppDisplayName       = [string] $ServicePrincipal.displayName
        AppId                = [string] $ServicePrincipal.appId
        ServicePrincipalId   = [string] $ServicePrincipal.id
        Publisher            = $Publisher.Name
        PublisherStatus      = $Publisher.Status
        IsAIApp              = $isAI
        AIMatch              = $matchText
        GrantType            = $GrantType
        Resource             = $resourceName
        ConsentScope         = $ConsentScope
        UserCount            = $UserCount
        Permissions          = [string[]] $Permission
        SensitivePermissions = [string[]] $Risk.SensitivePermissions
        Score                = $Risk.Score
        Level                = $Risk.Level
        Reasons              = [string[]] $Risk.Reasons
        Notes                = [string[]] $Note
        RecommendedAction    = $action
        RemovalHint          = $RemovalHint
        GrantIds             = [string[]] $GrantId
    }
}

#endregion

#region Collection

function Get-AIGTenantSnapshot {
    <#
    .SYNOPSIS
    Reads app consent data from the connected tenant into one snapshot object.

    .DESCRIPTION
    Needs an existing Connect-MgGraph session with Application.Read.All,
    Directory.Read.All, and Policy.Read.All. Sends GET requests only. Skips the
    app role assignment lookup for Microsoft first-party apps.

    .PARAMETER TenantLabel
    Friendly name for the report. Defaults to the tenant ID.

    .PARAMETER FirstPartyTenantIds
    Owner tenant IDs that mark an app as Microsoft first-party.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantLabel,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $FirstPartyTenantIds
    )

    $context = Get-MgContext
    if ($null -eq $context) {
        throw 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'
    }

    $select = 'id,appId,displayName,publisherName,verifiedPublisher,appOwnerOrganizationId,servicePrincipalType,accountEnabled,appRoleAssignmentRequired,appRoles'
    $servicePrincipals = Invoke-AIGGraphPaged -Uri "v1.0/servicePrincipals?`$select=$select&`$top=999"
    $grants = Invoke-AIGGraphPaged -Uri 'v1.0/oauth2PermissionGrants'

    $assignments = [System.Collections.Generic.List[object]]::new()
    foreach ($servicePrincipal in $servicePrincipals) {
        if (Test-AIGFirstParty -ServicePrincipal $servicePrincipal -FirstPartyTenantIds $FirstPartyTenantIds) {
            continue
        }
        foreach ($assignment in (Invoke-AIGGraphPaged -Uri "v1.0/servicePrincipals/$($servicePrincipal.id)/appRoleAssignments")) {
            $assignments.Add($assignment)
        }
    }

    $authorizationPolicy = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/authorizationPolicy' -OutputType PSObject
    $adminConsentRequestPolicy = Invoke-MgGraphRequest -Method GET -Uri 'v1.0/policies/adminConsentRequestPolicy' -OutputType PSObject

    $label = if ($TenantLabel) { $TenantLabel } else { [string] $context.TenantId }
    $capturedAt = [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)

    [pscustomobject]@{
        schemaVersion             = 1
        tenantId                  = [string] $context.TenantId
        tenantLabel               = $label
        capturedAt                = $capturedAt
        servicePrincipals         = $servicePrincipals
        oauth2PermissionGrants    = $grants
        appRoleAssignments        = $assignments.ToArray()
        authorizationPolicy       = $authorizationPolicy
        adminConsentRequestPolicy = $adminConsentRequestPolicy
    }
}

function Import-AIGTenantSnapshot {
    <#
    .SYNOPSIS
    Loads a snapshot JSON file and checks that every required section is present.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Snapshot not found: $Path"
    }
    $snapshot = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20
    $required = @(
        'schemaVersion'
        'tenantId'
        'servicePrincipals'
        'oauth2PermissionGrants'
        'appRoleAssignments'
        'authorizationPolicy'
        'adminConsentRequestPolicy'
    )
    $present = @($snapshot.PSObject.Properties.Name)
    $missing = @($required | Where-Object { $present -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "Snapshot $Path is missing: $($missing -join ', ')"
    }
    return $snapshot
}

#endregion

#region Analysis

function Test-AIGFirstParty {
    <#
    .SYNOPSIS
    True when the app is owned by one of the Microsoft first-party tenants.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object] $ServicePrincipal,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $FirstPartyTenantIds
    )

    $owner = [string] $ServicePrincipal.appOwnerOrganizationId
    if ([string]::IsNullOrWhiteSpace($owner)) {
        return $false
    }
    return ($FirstPartyTenantIds -contains $owner)
}

function Test-AIGAIApp {
    <#
    .SYNOPSIS
    Checks an app's display name and publisher against the AI watchlist.

    .OUTPUTS
    An object with Strength (Vendor or Name), Pattern, and MatchedOn, or $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $ServicePrincipal,

        [Parameter(Mandatory)]
        [object] $Watchlist
    )

    $fields = [ordered]@{
        displayName       = [string] $ServicePrincipal.displayName
        publisherName     = [string] $ServicePrincipal.publisherName
        verifiedPublisher = [string] $ServicePrincipal.verifiedPublisher.displayName
    }
    $passes = @(
        [pscustomobject]@{
            Strength = 'Vendor'
            Patterns = @($Watchlist.vendorPatterns)
        }
        [pscustomobject]@{
            Strength = 'Name'
            Patterns = @($Watchlist.genericPatterns)
        }
    )

    foreach ($pass in $passes) {
        foreach ($pattern in $pass.Patterns) {
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                continue
            }
            foreach ($field in $fields.GetEnumerator()) {
                if ($field.Value -and $field.Value -match $pattern) {
                    return [pscustomobject]@{
                        Strength  = $pass.Strength
                        Pattern   = [string] $pattern
                        MatchedOn = $field.Key
                    }
                }
            }
        }
    }
    return $null
}

function Get-AIGPublisherInfo {
    <#
    .SYNOPSIS
    Returns the publisher name and whether it is Internal, Verified, or Unverified.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $ServicePrincipal,

        [Parameter(Mandatory)]
        [string] $TenantId
    )

    $verified = [string] $ServicePrincipal.verifiedPublisher.displayName
    $name = if ($verified) {
        $verified
    }
    elseif ($ServicePrincipal.publisherName) {
        [string] $ServicePrincipal.publisherName
    }
    else {
        'Unknown'
    }
    $status = if ([string] $ServicePrincipal.appOwnerOrganizationId -eq $TenantId) {
        'Internal'
    }
    elseif ($verified) {
        'Verified'
    }
    else {
        'Unverified'
    }

    [pscustomobject]@{
        Name   = $name
        Status = $status
    }
}

function Measure-AIGPermissionRisk {
    <#
    .SYNOPSIS
    Scores one grant from the permissions it holds and how it was granted.

    .DESCRIPTION
    Starts from the weight of the highest weighted permission, then adds points
    for each extra sensitive permission, tenant-wide consent, an unverified
    publisher, offline_access next to a sensitive permission, and a large number
    of consenting users. Every point added is listed in Reasons.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Delegated', 'Application')]
        [string] $GrantType,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Permission,

        [Parameter(Mandatory)]
        [object] $RiskConfig,

        [switch] $TenantWide,

        [ValidateRange('NonNegative')]
        [int] $UserCount = 0,

        [switch] $UnverifiedPublisher
    )

    $weightSource = if ($GrantType -eq 'Application') { $RiskConfig.application } else { $RiskConfig.delegated }
    $weights = ConvertTo-AIGLookup -InputObject $weightSource
    $modifiers = $RiskConfig.modifiers
    $reasons = [System.Collections.Generic.List[string]]::new()

    $byWeight = @{
        Expression = { [int] $weights[$_] }
        Descending = $true
    }
    $sensitive = [string[]] @(
        $Permission |
            Where-Object { $_ -and $weights.ContainsKey($_) -and [int] $weights[$_] -gt 0 } |
            Sort-Object -Property $byWeight, { $_ } -Unique
    )

    $score = 0
    if ($sensitive.Count -gt 0) {
        $top = $sensitive[0]
        $score = [int] $weights[$top]
        $reasons.Add("$top is the highest weighted permission ($score)")
        $extra = $sensitive.Count - 1
        if ($extra -gt 0) {
            $add = $extra * [int] $modifiers.additionalSensitivePermission
            $score += $add
            $noun = if ($extra -eq 1) { 'permission' } else { 'permissions' }
            $reasons.Add("$extra more sensitive $noun (+$add)")
        }
        if ($GrantType -eq 'Application') {
            $reasons.Add('Runs as the app with no signed-in user and reaches data across the tenant unless scoped')
        }
    }
    else {
        $reasons.Add('No permissions on the sensitive list')
    }

    if ($TenantWide) {
        $add = [int] $modifiers.tenantWideConsent
        $score += $add
        $reasons.Add("Consent granted for every user in the tenant (+$add)")
    }
    if ($UnverifiedPublisher) {
        $add = [int] $modifiers.unverifiedPublisher
        $score += $add
        $reasons.Add("Publisher is not verified (+$add)")
    }
    if ($sensitive.Count -gt 0 -and $Permission -contains 'offline_access') {
        $add = [int] $modifiers.offlineAccessWithDataScope
        $score += $add
        $reasons.Add("offline_access gives the app refresh tokens, so it can reach this data while the user is away (+$add)")
    }
    $threshold = [int] $modifiers.manyUsersThreshold
    if ($threshold -gt 0 -and $UserCount -ge $threshold) {
        $add = [int] $modifiers.manyUsers
        $score += $add
        $reasons.Add("$UserCount users consented, at or above the threshold of $threshold (+$add)")
    }

    $score = [math]::Min(100, $score)
    $levels = $RiskConfig.levels
    $level = if ($score -ge [int] $levels.Critical) {
        'Critical'
    }
    elseif ($score -ge [int] $levels.High) {
        'High'
    }
    elseif ($score -ge [int] $levels.Medium) {
        'Medium'
    }
    else {
        'Low'
    }

    [pscustomobject]@{
        Score                = $score
        Level                = $level
        SensitivePermissions = $sensitive
        Reasons              = [string[]] $reasons.ToArray()
    }
}

function Get-AIGConsentFinding {
    <#
    .SYNOPSIS
    Turns a snapshot into scored findings, one per app and resource API.

    .DESCRIPTION
    Groups delegated grants by client app and resource, and application
    permission assignments the same way. Skips Microsoft first-party apps.
    Returns only apps that match the AI watchlist unless -IncludeNonAI is set.
    Output is sorted by score, highest first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Snapshot,

        [Parameter(Mandatory)]
        [object] $Watchlist,

        [Parameter(Mandatory)]
        [object] $RiskConfig,

        [switch] $IncludeNonAI
    )

    $firstPartyIds = [string[]] @($Watchlist.firstPartyTenantIds | Where-Object { $_ })
    $retiring = ConvertTo-AIGLookup -InputObject $RiskConfig.retiringPermissions
    $tenantId = [string] $Snapshot.tenantId
    $servicePrincipalById = @{}
    foreach ($servicePrincipal in @($Snapshot.servicePrincipals)) {
        if ($null -ne $servicePrincipal) {
            $servicePrincipalById[[string] $servicePrincipal.id] = $servicePrincipal
        }
    }
    $findings = [System.Collections.Generic.List[object]]::new()

    # Delegated grants: one finding per client app and resource API.
    $delegatedGroups = @($Snapshot.oauth2PermissionGrants | Where-Object { $null -ne $_ }) | Group-Object -Property clientId, resourceId
    foreach ($group in $delegatedGroups) {
        $grants = @($group.Group)
        $client = $servicePrincipalById[[string] $grants[0].clientId]
        if ($null -eq $client) {
            Write-Warning "Skipped delegated grant $($grants[0].id). Client $($grants[0].clientId) is not in the snapshot."
            continue
        }
        if (Test-AIGFirstParty -ServicePrincipal $client -FirstPartyTenantIds $firstPartyIds) {
            continue
        }
        $aiMatch = Test-AIGAIApp -ServicePrincipal $client -Watchlist $Watchlist
        if ($null -eq $aiMatch -and -not $IncludeNonAI) {
            continue
        }

        $resourceId = [string] $grants[0].resourceId
        $scopes = [string[]] @($grants | ForEach-Object { ([string] $_.scope) -split '\s+' } | Where-Object { $_ } | Sort-Object -Unique)
        $tenantWide = @($grants | Where-Object { $_.consentType -eq 'AllPrincipals' }).Count -gt 0
        $userCount = @($grants | Where-Object { $_.consentType -eq 'Principal' -and $_.principalId } | ForEach-Object { [string] $_.principalId } | Sort-Object -Unique).Count
        $publisher = Get-AIGPublisherInfo -ServicePrincipal $client -TenantId $tenantId
        $riskArgs = @{
            GrantType           = 'Delegated'
            Permission          = $scopes
            RiskConfig          = $RiskConfig
            TenantWide          = $tenantWide
            UserCount           = $userCount
            UnverifiedPublisher = ($publisher.Status -eq 'Unverified')
        }
        $risk = Measure-AIGPermissionRisk @riskArgs
        $grantIds = [string[]] @($grants | ForEach-Object { [string] $_.id })
        $findingArgs = @{
            ServicePrincipal = $client
            Resource         = $servicePrincipalById[$resourceId]
            ResourceId       = $resourceId
            Publisher        = $publisher
            AIMatch          = $aiMatch
            GrantType        = 'Delegated'
            ConsentScope     = if ($tenantWide) { 'AllUsers' } else { 'SomeUsers' }
            UserCount        = $userCount
            Permission       = $scopes
            Risk             = $risk
            Note             = [string[]] @($scopes | Where-Object { $retiring.ContainsKey($_) } | ForEach-Object { [string] $retiring[$_] })
            GrantId          = $grantIds
            RemovalHint      = Get-AIGRemovalHint -GrantType Delegated -ServicePrincipalId ([string] $client.id) -GrantId $grantIds
        }
        $findings.Add((ConvertTo-AIGFinding @findingArgs))
    }

    # Application permissions: one finding per client app and resource API.
    $applicationGroups = @($Snapshot.appRoleAssignments | Where-Object { $null -ne $_ }) | Group-Object -Property principalId, resourceId
    foreach ($group in $applicationGroups) {
        $assignments = @($group.Group)
        $client = $servicePrincipalById[[string] $assignments[0].principalId]
        if ($null -eq $client) {
            Write-Warning "Skipped app role assignment $($assignments[0].id). Principal $($assignments[0].principalId) is not in the snapshot."
            continue
        }
        if (Test-AIGFirstParty -ServicePrincipal $client -FirstPartyTenantIds $firstPartyIds) {
            continue
        }
        $aiMatch = Test-AIGAIApp -ServicePrincipal $client -Watchlist $Watchlist
        if ($null -eq $aiMatch -and -not $IncludeNonAI) {
            continue
        }

        $resourceId = [string] $assignments[0].resourceId
        $resource = $servicePrincipalById[$resourceId]
        $roleValues = foreach ($assignment in $assignments) {
            $role = $null
            if ($null -ne $resource) {
                $role = @($resource.appRoles) | Where-Object { $null -ne $_ -and [string] $_.id -eq [string] $assignment.appRoleId } | Select-Object -First 1
            }
            if ($null -ne $role -and $role.value) { [string] $role.value } else { "unknown-role:$($assignment.appRoleId)" }
        }
        $roles = [string[]] @($roleValues | Sort-Object -Unique)
        $publisher = Get-AIGPublisherInfo -ServicePrincipal $client -TenantId $tenantId
        $risk = Measure-AIGPermissionRisk -GrantType Application -Permission $roles -RiskConfig $RiskConfig -UnverifiedPublisher:($publisher.Status -eq 'Unverified')
        $grantIds = [string[]] @($assignments | ForEach-Object { [string] $_.id })
        $findingArgs = @{
            ServicePrincipal = $client
            Resource         = $resource
            ResourceId       = $resourceId
            Publisher        = $publisher
            AIMatch          = $aiMatch
            GrantType        = 'Application'
            ConsentScope     = 'AppOnly'
            UserCount        = 0
            Permission       = $roles
            Risk             = $risk
            Note             = [string[]] @($roles | Where-Object { $retiring.ContainsKey($_) } | ForEach-Object { [string] $retiring[$_] })
            GrantId          = $grantIds
            RemovalHint      = Get-AIGRemovalHint -GrantType Application -ServicePrincipalId ([string] $client.id) -GrantId $grantIds
        }
        $findings.Add((ConvertTo-AIGFinding @findingArgs))
    }

    $byScore = @{
        Expression = 'Score'
        Descending = $true
    }
    $findings | Sort-Object -Property $byScore, 'AppDisplayName', 'GrantType'
}

#endregion

#region Consent policy

function Get-AIGUserConsentState {
    <#
    .SYNOPSIS
    Reads the user consent setting from an authorizationPolicy object.

    .OUTPUTS
    Mode is Disabled, AllApps, LowRiskVerified, MicrosoftManaged, or Custom.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $AuthorizationPolicy
    )

    # Graph returns these IDs with a capital M. Compare without regard to case.
    $assigned = @($AuthorizationPolicy.defaultUserRolePermissions.permissionGrantPoliciesAssigned | Where-Object { $_ })
    $self = @($assigned | Where-Object { $_ -like 'managePermissionGrantsForSelf.*' })
    $other = @($assigned | Where-Object { $_ -notlike 'managePermissionGrantsForSelf.*' })

    $mode = if ($self.Count -eq 0) {
        'Disabled'
    }
    elseif (@($self | Where-Object { $_ -like '*.microsoft-user-default-legacy' }).Count -gt 0) {
        'AllApps'
    }
    elseif ($self.Count -eq 1 -and $self[0] -like '*.microsoft-user-default-low') {
        'LowRiskVerified'
    }
    elseif ($self.Count -eq 1 -and $self[0] -like '*.microsoft-user-default-recommended') {
        'MicrosoftManaged'
    }
    else {
        'Custom'
    }

    $description = switch ($mode) {
        'Disabled' { 'Users cannot consent to apps.' }
        'AllApps' { 'Users can consent to any app for permissions that do not need admin consent. This is the legacy setting.' }
        'LowRiskVerified' { 'Users can consent only to apps from verified publishers or apps registered in this tenant, and only for permissions classified as low impact.' }
        'MicrosoftManaged' { 'Users can consent under the Microsoft managed policy (microsoft-user-default-recommended). Microsoft maintains its conditions.' }
        default { 'Users can consent under a custom permission grant policy. Review its conditions.' }
    }

    [pscustomobject]@{
        Mode          = $mode
        Description   = $description
        SelfPolicies  = [string[]] $self
        OtherPolicies = [string[]] $other
    }
}

function Get-AIGPermissionGrantPolicyUpdate {
    <#
    .SYNOPSIS
    Builds the new permissionGrantPoliciesAssigned list for a user consent change.

    .DESCRIPTION
    Removes every managePermissionGrantsForSelf entry and keeps everything else,
    including the ManagePermissionGrantsForOwnedResource entries that control
    resource-specific consent for teams and chats. A PATCH replaces the whole
    list, so dropping those entries would change Teams consent as a side effect.
    For LowRiskVerified, adds the built-in microsoft-user-default-low policy.
    An empty list turns user consent off.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Current,

        [Parameter(Mandatory)]
        [ValidateSet('Disabled', 'LowRiskVerified')]
        [string] $Mode
    )

    $kept = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Current)) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }
        if ($entry -like 'managePermissionGrantsForSelf.*') {
            continue
        }
        if ($seen.Add($entry)) {
            $kept.Add($entry)
        }
    }
    if ($Mode -eq 'LowRiskVerified') {
        $kept.Insert(0, 'managePermissionGrantsForSelf.microsoft-user-default-low')
    }
    return , $kept.ToArray()
}

function Get-AIGAdminConsentRequestPolicyBody {
    <#
    .SYNOPSIS
    Builds the PUT body for v1.0/policies/adminConsentRequestPolicy.

    .PARAMETER ReviewerUserId
    Object IDs of the users who review requests. Group and role reviewers are not
    supported here.

    .PARAMETER RequestDurationInDays
    Days a request stays open. The 1 to 365 range is a local sanity check.
    Microsoft Graph does not document a range for this property.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [guid[]] $ReviewerUserId,

        [ValidateRange(1, 365)]
        [int] $RequestDurationInDays = 7,

        [bool] $NotifyReviewers = $true,

        [bool] $RemindersEnabled = $true
    )

    $reviewers = @(
        foreach ($id in $ReviewerUserId) {
            [ordered]@{
                query     = "/users/$id"
                queryType = 'MicrosoftGraph'
            }
        }
    )

    return [ordered]@{
        isEnabled             = $true
        notifyReviewers       = $NotifyReviewers
        remindersEnabled      = $RemindersEnabled
        requestDurationInDays = $RequestDurationInDays
        reviewers             = $reviewers
    }
}

#endregion

#region Reporting

function Export-AIGReport {
    <#
    .SYNOPSIS
    Writes findings.csv, findings.json, and report.md for a set of findings.

    .OUTPUTS
    An object with the Csv, Json, and Markdown paths.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Finding,

        [Parameter(Mandatory)]
        [object] $Snapshot,

        [Parameter(Mandatory)]
        [string] $OutputDirectory
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    }
    $csvPath = Join-Path -Path $OutputDirectory -ChildPath 'findings.csv'
    $jsonPath = Join-Path -Path $OutputDirectory -ChildPath 'findings.json'
    $markdownPath = Join-Path -Path $OutputDirectory -ChildPath 'report.md'

    $label = if ($Snapshot.tenantLabel) { [string] $Snapshot.tenantLabel } else { [string] $Snapshot.tenantId }
    $capturedAt = Format-AIGTimestamp -Value $Snapshot.capturedAt
    $generatedAt = Format-AIGTimestamp -Value ([datetime]::UtcNow)
    $consent = Get-AIGUserConsentState -AuthorizationPolicy $Snapshot.authorizationPolicy
    $workflow = $Snapshot.adminConsentRequestPolicy
    $workflowOn = [bool] $workflow.isEnabled
    $reviewerCount = @($workflow.reviewers | Where-Object { $null -ne $_ }).Count

    $counts = [ordered]@{}
    foreach ($level in 'Critical', 'High', 'Medium', 'Low') {
        $counts[$level] = @($Finding | Where-Object { $_.Level -eq $level }).Count
    }

    # CSV: one row per finding, with arrays flattened.
    $columns = @(
        'Level', 'Score', 'AppDisplayName', 'AppId', 'ServicePrincipalId', 'Publisher', 'PublisherStatus',
        'IsAIApp', 'AIMatch', 'GrantType', 'Resource', 'ConsentScope', 'UserCount', 'Permissions',
        'SensitivePermissions', 'Reasons', 'Notes', 'RecommendedAction', 'RemovalHint', 'GrantIds'
    )
    $rows = foreach ($item in $Finding) {
        $row = [ordered]@{}
        foreach ($column in $columns) {
            $value = $item.$column
            if ($value -is [array]) {
                $separator = if ($column -in 'Reasons', 'Notes') { ' | ' } else { ' ' }
                $value = $value -join $separator
            }
            $row[$column] = $value
        }
        [pscustomobject] $row
    }
    if ($rows) {
        $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
    }
    else {
        $header = ($columns | ForEach-Object { '"{0}"' -f $_ }) -join ','
        Set-Content -LiteralPath $csvPath -Value $header -Encoding utf8
    }

    # JSON: the full result, for other tools.
    $document = [ordered]@{
        tenantLabel          = $label
        tenantId             = [string] $Snapshot.tenantId
        snapshotCapturedAt   = $capturedAt
        generatedAt          = $generatedAt
        userConsent          = [ordered]@{
            mode                            = $consent.Mode
            description                     = $consent.Description
            permissionGrantPoliciesAssigned = @($consent.SelfPolicies) + @($consent.OtherPolicies)
        }
        adminConsentWorkflow = [ordered]@{
            isEnabled     = $workflowOn
            reviewerCount = $reviewerCount
        }
        summary              = $counts
        findings             = @($Finding)
    }
    $document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8

    # Markdown: the report a person reads.
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# AI app consent report: $label")
    $lines.Add('')
    $lines.Add("Tenant ``$($Snapshot.tenantId)``. Snapshot captured $capturedAt. Report generated $generatedAt.")
    $lines.Add('')
    $lines.Add('## Consent posture')
    $lines.Add('')
    $workflowText = if (-not $workflowOn) {
        'Off'
    }
    elseif ($reviewerCount -eq 0) {
        'On, with no reviewers'
    }
    else {
        "On, $(Format-AIGCount -Count $reviewerCount -Singular 'reviewer' -Plural 'reviewers')"
    }
    $lines.Add('| Setting | Current | Target |')
    $lines.Add('| --- | --- | --- |')
    $lines.Add("| User consent | $(Format-AIGCell -Text $consent.Description) | Off, or limited to verified publishers and low impact permissions |")
    $lines.Add("| Admin consent workflow | $workflowText | On, with named reviewers |")

    $lines.Add('')
    $lines.Add('## Summary')
    $lines.Add('')
    $lines.Add('| Level | Findings |')
    $lines.Add('| --- | ---: |')
    foreach ($entry in $counts.GetEnumerator()) {
        $lines.Add("| $($entry.Key) | $($entry.Value) |")
    }
    $lines.Add('')
    $appCount = @($Finding | ForEach-Object { $_.ServicePrincipalId } | Sort-Object -Unique).Count
    $unverifiedApps = @($Finding | Where-Object { $_.PublisherStatus -eq 'Unverified' } | ForEach-Object { $_.ServicePrincipalId } | Sort-Object -Unique).Count
    $allUserGrants = @($Finding | Where-Object { $_.ConsentScope -eq 'AllUsers' }).Count
    $appOnlyApps = @($Finding | Where-Object { $_.GrantType -eq 'Application' } | ForEach-Object { $_.ServicePrincipalId } | Sort-Object -Unique).Count
    $sentences = @(
        "$(Format-AIGCount -Count $Finding.Count -Singular 'finding' -Plural 'findings') across $(Format-AIGCount -Count $appCount -Singular 'app' -Plural 'apps')."
        "$(Format-AIGCount -Count $unverifiedApps -Singular 'app has an unverified publisher' -Plural 'apps have unverified publishers')."
        "$(Format-AIGCount -Count $allUserGrants -Singular 'delegated grant covers' -Plural 'delegated grants cover') every user in the tenant."
        "$(Format-AIGCount -Count $appOnlyApps -Singular 'app holds' -Plural 'apps hold') application permissions."
    )
    $lines.Add($sentences -join ' ')

    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')
    if ($Finding.Count -eq 0) {
        $lines.Add('No findings.')
    }
    else {
        $lines.Add('| Level | Score | App | Publisher | Grant | Resource | Who | Sensitive permissions |')
        $lines.Add('| --- | ---: | --- | --- | --- | --- | --- | --- |')
        foreach ($item in $Finding) {
            $who = switch ($item.ConsentScope) {
                'AllUsers' { 'All users' }
                'AppOnly' { 'App only' }
                default { Format-AIGCount -Count $item.UserCount -Singular 'user' -Plural 'users' }
            }
            $sensitive = if (@($item.SensitivePermissions).Count -gt 0) { @($item.SensitivePermissions) -join ', ' } else { 'None' }
            $values = @(
                $item.Level
                $item.Score
                $item.AppDisplayName
                "$($item.Publisher) ($($item.PublisherStatus))"
                $item.GrantType
                $item.Resource
                $who
                $sensitive
            )
            $cells = $values | ForEach-Object { Format-AIGCell -Text ([string] $_) }
            $lines.Add('| ' + ($cells -join ' | ') + ' |')
        }

        foreach ($item in $Finding) {
            $who = switch ($item.ConsentScope) {
                'AllUsers' { 'all users' }
                'AppOnly' { 'app only' }
                default { Format-AIGCount -Count $item.UserCount -Singular 'user' -Plural 'users' }
            }
            $grantText = if ($item.GrantType -eq 'Application') { 'Application permissions' } else { 'Delegated permissions' }
            $matchText = if ($item.IsAIApp) { "Matched the AI watchlist ($($item.AIMatch))." } else { 'No AI watchlist match.' }
            $lines.Add('')
            $lines.Add("### $($item.AppDisplayName)")
            $lines.Add('')
            $lines.Add("$($item.Level), score $($item.Score). $grantText on $($item.Resource), $who. Publisher $($item.Publisher) ($($item.PublisherStatus.ToLowerInvariant())). $matchText")
            $lines.Add('')
            $lines.Add("Granted permissions are $(@($item.Permissions) -join ', ').")
            $lines.Add('')
            $lines.Add('Score reasons:')
            $lines.Add('')
            foreach ($reason in @($item.Reasons)) {
                $lines.Add("- $reason")
            }
            foreach ($note in @($item.Notes | Where-Object { $_ })) {
                $lines.Add('')
                $lines.Add($note)
            }
            $lines.Add('')
            $lines.Add($item.RecommendedAction)
        }
    }

    $lines.Add('')
    $lines.Add('## What to do next')
    $lines.Add('')
    $steps = [System.Collections.Generic.List[string]]::new()
    switch ($consent.Mode) {
        'AllApps' {
            $steps.Add('Close the open consent path first. If you remove grants while users can still consent, the same apps can come back. Plan the change against this snapshot with `./scripts/Set-AppConsentPolicy.ps1 -SnapshotPath <snapshot> -UserConsent LowRiskVerified`, then run it live with `-WhatIf` before the real change.')
        }
        'Custom' {
            $steps.Add('Review the custom user consent policy and confirm its conditions block the permissions this report flags.')
        }
        'MicrosoftManaged' {
            $steps.Add('User consent follows the Microsoft managed policy. Check its current conditions on Microsoft Learn and decide whether a stricter setting fits your data.')
        }
        default {
            $steps.Add('User consent is already restricted. Keep it that way, and check it again after tenant-wide changes.')
        }
    }
    if (-not $workflowOn) {
        $steps.Add('Turn on the admin consent workflow with named reviewers, so a user who hits a blocked prompt can ask for access instead of looking for a workaround. Add `-EnableAdminConsentWorkflow -ReviewerUserId <object-id>` to the same command.')
    }
    elseif ($reviewerCount -eq 0) {
        $steps.Add('The admin consent workflow is on with no reviewers. Add at least one so requests reach a person.')
    }
    if ($counts['Critical'] -gt 0) {
        $steps.Add('Work the Critical findings today. Confirm a business owner for each app and remove the access where there is none. The commands are in the next section.')
    }
    if ($counts['High'] -gt 0) {
        $steps.Add('Run each High finding through `assessments/AI-Tool-Risk-Assessment.md` this week.')
    }
    $steps.Add('Record every AI app you keep in the AI tool register, with its tier and the data class it may use.')
    $steps.Add('Run this report again after the changes, then on a schedule, to catch new grants.')
    $number = 0
    foreach ($step in $steps) {
        $number++
        $lines.Add("$number. $step")
    }

    $lines.Add('')
    $lines.Add('## Removal commands')
    $lines.Add('')
    $urgent = @($Finding | Where-Object { $_.Level -in 'Critical', 'High' })
    if ($urgent.Count -eq 0) {
        $lines.Add('No Critical or High findings. findings.json has a removal command for every finding.')
    }
    else {
        $scopes = [System.Collections.Generic.List[string]]::new()
        if (@($urgent | Where-Object { $_.GrantType -eq 'Delegated' }).Count -gt 0) {
            $scopes.Add("'DelegatedPermissionGrant.ReadWrite.All'")
        }
        if (@($urgent | Where-Object { $_.GrantType -eq 'Application' }).Count -gt 0) {
            $scopes.Add("'AppRoleAssignment.ReadWrite.All'")
        }
        if (@($urgent | Where-Object { $_.Level -eq 'Critical' }).Count -gt 0) {
            $scopes.Add("'Application.ReadWrite.All'")
        }
        $lines.Add('These cover the Critical and High findings. findings.json has a removal command for every finding. Review each command before you run it, and close user consent first so users cannot grant the same access again.')
        $lines.Add('')
        $lines.Add('Access tokens an app already holds keep working until they expire. For Critical findings the block below also disables sign-in for the app.')
        $lines.Add('')
        $lines.Add('```powershell')
        $lines.Add("Connect-MgGraph -Scopes $($scopes -join ', ')")
        $disabled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $urgent) {
            $lines.Add('')
            $lines.Add("# $($item.AppDisplayName) ($($item.Level), $($item.Score))")
            $lines.Add($item.RemovalHint)
            if ($item.Level -eq 'Critical' -and $disabled.Add($item.ServicePrincipalId)) {
                $lines.Add("Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/servicePrincipals/$($item.ServicePrincipalId)' -Body @{ accountEnabled = `$false }")
            }
        }
        $lines.Add('```')
    }

    Set-Content -LiteralPath $markdownPath -Value $lines -Encoding utf8

    [pscustomobject]@{
        Csv      = $csvPath
        Json     = $jsonPath
        Markdown = $markdownPath
    }
}

#endregion
