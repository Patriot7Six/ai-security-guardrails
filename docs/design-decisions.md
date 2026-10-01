# Design decisions

## Read-only unless you ask

The inventory script requests read scopes only and sends GET requests only. All writes live in `Set-AppConsentPolicy.ps1`, which declares `ConfirmImpact = 'High'`, supports `-WhatIf`, and has a plan mode that never signs in. A live run reads the policy back after each write to confirm it took.

## Raw Graph requests through Invoke-MgGraphRequest

The code calls Microsoft Graph v1.0 URLs directly instead of the generated SDK cmdlets. Only the `Microsoft.Graph.Authentication` module is needed, and every request in the code matches an endpoint on Microsoft Learn, which makes review and least-privilege checks simpler.

## Snapshot first, analysis offline

Collection and analysis are separate steps. Analysis runs against a JSON snapshot, so it can be tested without a tenant, run again after a weight change, and reproduced later. The trade-off is that a snapshot holds directory data and needs the same care as any export.

## Keep the owned resource entries

`permissionGrantPoliciesAssigned` holds two kinds of entries. `managePermissionGrantsForSelf.*` controls user consent. `ManagePermissionGrantsForOwnedResource.*` controls resource-specific consent for teams and chats. A PATCH replaces the whole list, so writing only the new user consent value would also change who can consent in Teams. The script removes only the self entries and keeps the rest. Graph returns these IDs with a capital M while the docs show a lowercase m, so every comparison ignores case.

## Microsoft managed consent is reported only

Entra offers a "Let Microsoft manage your consent settings" option, and Microsoft Learn lists `microsoft-user-default-recommended` as a Microsoft managed policy. I could not find a Microsoft page that says the portal option writes that ID, so the hardening script does not offer it. The inventory reports `MicrosoftManaged` when it sees that policy assigned.

## AI detection is a heuristic

Name patterns catch apps that call themselves AI. They miss AI features inside general apps, and they flag some apps that are not AI tools. Vendor matches are checked first and count as stronger than generic matches. Every match needs a person to look at it. `-IncludeNonAI` scores every non-Microsoft app, which gives the full grant inventory.

## Scoring a person can check

The score is a sum of weights and fixed modifiers, and every point shows up in the finding's reasons. A reviewer who disagrees with a score can see which weight to change. Application permissions weigh more than the same delegated permission because they run with no signed-in user and reach every mailbox or site unless scoped.

## Microsoft first-party apps are skipped

Apps owned by the Microsoft services tenant (f8cdef31-a31e-4b4a-93e4-5f571e91255a) or the Microsoft corporate tenant (72f988bf-86f1-41af-91ab-2d7cd011db47) are left out. These are the owner tenant IDs Microsoft publishes for verifying first-party apps. The live collector also skips the per-app role assignment request for them, which cuts the number of calls.

## EWS permissions get a retirement note

Microsoft's EWS retirement in Exchange Online starts blocking non-Microsoft apps on October 1, 2026, in phases, and fully disables EWS in April 2027. An app that still holds full_access_as_app or EWS.AccessAsUser.All either stops working by April 2027 or has moved to Graph and left a stale grant behind. The finding carries a note that says so. The score does not change.

## Limits

- Consent grants are one path. Browser use without sign-in, browser extensions, personal API keys, and AI features inside approved apps need other controls, such as Defender for Cloud Apps discovery, browser management, and contract terms.
- Weights match on the permission name only, so a same-named scope on a non-Microsoft API scores the same as the Graph one.
- The live collector makes one request per non-Microsoft service principal to read application permissions. Large tenants take longer.
- Admin consent workflow reviewers are user object IDs only. Group and role reviewer formats are not implemented.
