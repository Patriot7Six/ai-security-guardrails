# Design decisions

## Read-only unless you ask

The inventory script requests read scopes only and sends GET requests only. All writes live in `Set-AppConsentPolicy.ps1`, which declares `ConfirmImpact = 'High'`, supports `-WhatIf`, and has a plan mode that never signs in. A live run reads the policy back after each write to confirm it took.

## Raw Graph requests through Invoke-MgGraphRequest

The code calls Microsoft Graph v1.0 URLs directly instead of the generated SDK cmdlets. Only the `Microsoft.Graph.Authentication` module is needed, and every request in the code matches an endpoint on Microsoft Learn, which makes review and least-privilege checks simpler.

## Snapshot first, analysis offline

Collection and analysis are separate steps. Analysis runs against a JSON snapshot, so it can be tested without a tenant, run again after a weight change, and reproduced later. The trade-off is that a snapshot holds directory data and needs the same care as any export.

## Keep the owned resource entries

`permissionGrantPoliciesAssigned` holds two kinds of entries. `managePermissionGrantsForSelf.*` controls user consent. `ManagePermissionGrantsForOwnedResource.*` controls resource-specific consent for teams and chats. Microsoft Learn says to include the current owned resource entries whenever you update the list, so the script sends the full list. Writing only the new user consent value would risk changing who can consent in Teams. The script removes only the self entries and keeps the rest. Learn's request examples use a lowercase m, while its sample response and article text use a capital M, so every comparison ignores case.

## Microsoft managed consent is reported only

Entra offers a "Let Microsoft manage your consent settings" option, and Microsoft Learn lists `microsoft-user-default-recommended` as a Microsoft managed policy and calls the option the default for new tenants. I checked the current Learn pages and none says the portal option writes that ID, so the hardening script does not offer it. The inventory reports `MicrosoftManaged` when it sees that policy assigned.

## AI detection is a heuristic

Name patterns catch apps that call themselves AI. They miss AI features inside general apps, and they flag some apps that are not AI tools. Vendor matches are checked first and count as stronger than generic matches. Every match needs a person to look at it. `-IncludeNonAI` scores every non-Microsoft app, which gives the full grant inventory.

## Scoring a person can check

The score is a sum of weights and fixed modifiers, and every point shows up in the finding's reasons. A reviewer who disagrees with a score can see which weight to change. Application permissions weigh more than the same delegated permission because they run with no signed-in user and reach every mailbox or site unless scoped.

## Microsoft first-party apps are skipped

Apps owned by the Microsoft Services tenant (f8cdef31-a31e-4b4a-93e4-5f571e91255a) or the Microsoft tenant (72f988bf-86f1-41af-91ab-2d7cd011db47) are left out. Both IDs come from Microsoft's troubleshooting guidance for verifying first-party apps. That page says its app list is partial, so treat these as two known first-party owner tenants and not as a complete list. The live collector also skips the per-app role assignment request for them, which cuts the number of calls.

## EWS permissions get a retirement note

Microsoft is retiring EWS in Exchange Online in phases. Disablement starts in October 2026 and applies to all apps, Microsoft's own included. EWS is fully disabled in April 2027. Until then, an app keeps EWS access only while the tenant allows EWS and lists the app in EWSAllowedAppIDs. After April 2027 a remaining full_access_as_app or EWS.AccessAsUser.All grant is stale, and so is the grant of an app that has already moved to Graph. The finding carries a note that says so. The score does not change. A consent scan also cannot see EWS access given through Exchange role based access control for applications.

## Limits

- Consent grants are one path. Browser use without sign-in, browser extensions, personal API keys, and AI features inside approved apps need other controls, such as Defender for Cloud Apps discovery, browser management, and contract terms.
- Weights match on the permission name only, so a same-named scope on a non-Microsoft API scores the same as the Graph one.
- Permissions with no entry in `config/permission-risk.json` score 0. That includes the ones that can escalate privilege: RoleManagement.ReadWrite.Directory, AppRoleAssignment.ReadWrite.All, Application.ReadWrite.All, DelegatedPermissionGrant.ReadWrite.All, and Sites.FullControl.All. It also includes Group.ReadWrite.All, User.ReadWrite.All, the shared mailbox permissions, and the Teams send permissions. Add weights for these before you rely on the score for a tenant that uses them.
- The collector has only run against the synthetic snapshot. The live paths, including the relative request URIs and the role needed for each read, are untested against a tenant. The List servicePrincipals response can also include agentIdentityBlueprintPrincipal objects, which the scoring code does not treat specially.
- `publisherName` is not in the v1.0 servicePrincipal property table. It appears in a Microsoft List servicePrincipals example, so the collector reads it, but do not use it as a trust signal.
- The live collector makes one request per non-Microsoft service principal to read application permissions. Large tenants take longer.
- Admin consent workflow reviewers are user object IDs only. Group and role reviewer formats are not implemented.
