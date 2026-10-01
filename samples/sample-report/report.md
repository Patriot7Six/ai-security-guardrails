# AI app consent report: Contoso

Tenant `a1b2c3d4-0000-4000-8000-00000000c0f1`. Snapshot captured 2026-09-28 15:00 UTC. Report generated 2026-10-01 19:16 UTC.

## Consent posture

| Setting | Current | Target |
| --- | --- | --- |
| User consent | Users can consent to any app for permissions that do not need admin consent. This is the legacy setting. | Off, or limited to verified publishers and low impact permissions |
| Admin consent workflow | Off | On, with named reviewers |

## Summary

| Level | Findings |
| --- | ---: |
| Critical | 3 |
| High | 2 |
| Medium | 1 |
| Low | 1 |

7 findings across 7 apps. 3 apps have unverified publishers. 2 delegated grants cover every user in the tenant. 1 app holds application permissions.

## Findings

| Level | Score | App | Publisher | Grant | Resource | Who | Sensitive permissions |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Critical | 90 | SupportBot GPT Connector | SupportBot Labs (Verified) | Application | Office 365 Exchange Online | App only | full_access_as_app |
| Critical | 85 | InboxPilot AI | InboxPilot (Unverified) | Delegated | Microsoft Graph | All users | Mail.ReadWrite, Mail.Send |
| Critical | 80 | DataChat Analyst | DataChat LLM Labs (Unverified) | Delegated | Microsoft Graph | 14 users | Files.Read.All, Sites.Read.All, User.Read.All |
| High | 65 | Summarize Everything | Summarize Everything Inc (Unverified) | Delegated | Microsoft Graph | 3 users | Files.Read.All, Mail.Read |
| High | 55 | Contoso CareDesk Assistant | Contoso (Internal) | Delegated | Microsoft Graph | All users | Mail.ReadWrite |
| Medium | 40 | NoteGenie AI Meeting Notes | NoteGenie Inc (Verified) | Delegated | Microsoft Graph | 12 users | Calendars.Read, OnlineMeetings.Read |
| Low | 0 | QuickDraft AI Writer | QuickDraft Software (Verified) | Delegated | Microsoft Graph | 1 user | None |

### SupportBot GPT Connector

Critical, score 90. Application permissions on Office 365 Exchange Online, app only. Publisher SupportBot Labs (verified). Matched the AI watchlist (Name pattern '\bGPT\b' on displayName).

Granted permissions are full_access_as_app.

Score reasons:

- full_access_as_app is the highest weighted permission (90)
- Runs as the app with no signed-in user and reaches data across the tenant unless scoped

full_access_as_app is an Exchange Web Services (EWS) permission. Microsoft's EWS retirement in Exchange Online starts blocking non-Microsoft apps on October 1, 2026, in phases, and fully disables EWS in April 2027. Confirm the app has moved to Microsoft Graph, then remove this grant.

Confirm the business owner and data flow today. If there is no approved use, remove the app role assignment and disable sign-in for the app.

### InboxPilot AI

Critical, score 85. Delegated permissions on Microsoft Graph, all users. Publisher InboxPilot (unverified). Matched the AI watchlist (Name pattern '\bAI\b' on displayName).

Granted permissions are Mail.ReadWrite, Mail.Send, offline_access, openid, profile, User.Read.

Score reasons:

- Mail.ReadWrite is the highest weighted permission (40)
- 1 more sensitive permission (+5)
- Consent granted for every user in the tenant (+15)
- Publisher is not verified (+15)
- offline_access gives the app refresh tokens, so it can reach this data while the user is away (+10)

Confirm the business owner and data flow today. If there is no approved use, remove the grant and disable sign-in for the app.

### DataChat Analyst

Critical, score 80. Delegated permissions on Microsoft Graph, 14 users. Publisher DataChat LLM Labs (unverified). Matched the AI watchlist (Name pattern '\bLLM\b' on publisherName).

Granted permissions are Files.Read.All, offline_access, Sites.Read.All, User.Read, User.Read.All.

Score reasons:

- Files.Read.All is the highest weighted permission (35)
- 2 more sensitive permissions (+10)
- Publisher is not verified (+15)
- offline_access gives the app refresh tokens, so it can reach this data while the user is away (+10)
- 14 users consented, at or above the threshold of 10 (+10)

Confirm the business owner and data flow today. If there is no approved use, remove the grant and disable sign-in for the app.

### Summarize Everything

High, score 65. Delegated permissions on Microsoft Graph, 3 users. Publisher Summarize Everything Inc (unverified). Matched the AI watchlist (Name pattern 'Summar' on displayName).

Granted permissions are Files.Read.All, Mail.Read, offline_access, User.Read.

Score reasons:

- Files.Read.All is the highest weighted permission (35)
- 1 more sensitive permission (+5)
- Publisher is not verified (+15)
- offline_access gives the app refresh tokens, so it can reach this data while the user is away (+10)

Run the AI tool risk assessment this week. Require user assignment for the app or remove the grant.

### Contoso CareDesk Assistant

High, score 55. Delegated permissions on Microsoft Graph, all users. Publisher Contoso (internal). Matched the AI watchlist (Name pattern 'Assistant' on displayName).

Granted permissions are Mail.ReadWrite, openid, profile, User.Read.

Score reasons:

- Mail.ReadWrite is the highest weighted permission (40)
- Consent granted for every user in the tenant (+15)

Run the AI tool risk assessment this week. Require user assignment for the app or remove the grant.

### NoteGenie AI Meeting Notes

Medium, score 40. Delegated permissions on Microsoft Graph, 12 users. Publisher NoteGenie Inc (verified). Matched the AI watchlist (Name pattern '\bAI\b' on displayName).

Granted permissions are Calendars.Read, offline_access, OnlineMeetings.Read, User.Read.

Score reasons:

- Calendars.Read is the highest weighted permission (15)
- 1 more sensitive permission (+5)
- offline_access gives the app refresh tokens, so it can reach this data while the user is away (+10)
- 12 users consented, at or above the threshold of 10 (+10)

Review at the next access review and confirm the app is on the AI tool register.

### QuickDraft AI Writer

Low, score 0. Delegated permissions on Microsoft Graph, 1 user. Publisher QuickDraft Software (verified). Matched the AI watchlist (Name pattern '\bAI\b' on displayName).

Granted permissions are offline_access, openid, profile, User.Read.

Score reasons:

- No permissions on the sensitive list

Keep on the inventory. No change needed.

## What to do next

1. Close the open consent path first. If you remove grants while users can still consent, the same apps can come back. Plan the change against this snapshot with `./scripts/Set-AppConsentPolicy.ps1 -SnapshotPath <snapshot> -UserConsent LowRiskVerified`, then run it live with `-WhatIf` before the real change.
2. Turn on the admin consent workflow with named reviewers, so a user who hits a blocked prompt can ask for access instead of looking for a workaround. Add `-EnableAdminConsentWorkflow -ReviewerUserId <object-id>` to the same command.
3. Work the Critical findings today. Confirm a business owner for each app and remove the access where there is none. The commands are in the next section.
4. Run each High finding through `assessments/AI-Tool-Risk-Assessment.md` this week.
5. Record every AI app you keep in the AI tool register, with its tier and the data class it may use.
6. Run this report again after the changes, then on a schedule, to catch new grants.

## Removal commands

These cover the Critical and High findings. findings.json has a removal command for every finding. Review each command before you run it, and close user consent first so users cannot grant the same access again.

Access tokens an app already holds keep working until they expire. For Critical findings the block below also disables sign-in for the app.

```powershell
Connect-MgGraph -Scopes 'DelegatedPermissionGrant.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All'

# SupportBot GPT Connector (Critical, 90)
Invoke-MgGraphRequest -Method DELETE -Uri 'v1.0/servicePrincipals/5e000000-0000-4000-8000-000000000010/appRoleAssignments/syn-assign-supportbot-exo'
Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/servicePrincipals/5e000000-0000-4000-8000-000000000010' -Body @{ accountEnabled = $false }

# InboxPilot AI (Critical, 85)
Invoke-MgGraphRequest -Method DELETE -Uri 'v1.0/oauth2PermissionGrants/syn-grant-inboxpilot-all'
Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/servicePrincipals/5e000000-0000-4000-8000-000000000011' -Body @{ accountEnabled = $false }

# DataChat Analyst (Critical, 80)
'syn-grant-datachat-u01', 'syn-grant-datachat-u02', 'syn-grant-datachat-u03', 'syn-grant-datachat-u04', 'syn-grant-datachat-u05', 'syn-grant-datachat-u06', 'syn-grant-datachat-u07', 'syn-grant-datachat-u08', 'syn-grant-datachat-u09', 'syn-grant-datachat-u10', 'syn-grant-datachat-u11', 'syn-grant-datachat-u12', 'syn-grant-datachat-u13', 'syn-grant-datachat-u14' | ForEach-Object { Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/oauth2PermissionGrants/$_" }
Invoke-MgGraphRequest -Method PATCH -Uri 'v1.0/servicePrincipals/5e000000-0000-4000-8000-000000000012' -Body @{ accountEnabled = $false }

# Summarize Everything (High, 65)
'syn-grant-summarize-u15', 'syn-grant-summarize-u16', 'syn-grant-summarize-u17' | ForEach-Object { Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/oauth2PermissionGrants/$_" }

# Contoso CareDesk Assistant (High, 55)
Invoke-MgGraphRequest -Method DELETE -Uri 'v1.0/oauth2PermissionGrants/syn-grant-caredesk-all'
```
