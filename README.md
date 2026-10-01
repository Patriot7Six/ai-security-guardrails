# AI Security Guardrails

[![ci](https://github.com/Patriot7Six/ai-security-guardrails/actions/workflows/ci.yml/badge.svg)](https://github.com/Patriot7Six/ai-security-guardrails/actions/workflows/ci.yml)

A starter kit for putting guardrails around AI tools in a Microsoft 365 tenant. It finds the AI apps people have already connected through OAuth consent, scores what each one can reach, closes the consent path that let them in, and gives the security team a policy and a review checklist for what comes next.

Everything here runs offline against a synthetic tenant called Contoso, the fictional company Microsoft uses in its own docs. No real tenant data is included.

## Why start with consent

Most AI tools reach company data the same way. A user signs in with a work account, sees a consent prompt, and clicks Accept. In a tenant still on the legacy user consent setting, that click gives a third party ongoing access to the user's mail, files, or chats. It happens without a ticket or a review, and IT often never sees it.

The kit works the problem in three steps:

1. Find what is already connected, and decide what stays.
2. Close the consent path, so new access goes through a person.
3. Publish a clear policy and a fast way to request a tool, so people ask instead of working around the controls.

## What's inside

| Path | What it does |
| --- | --- |
| `scripts/Get-AIAppConsents.ps1` | Read-only inventory of delegated and application grants. Flags likely AI apps, scores each grant, and writes CSV, JSON, and a Markdown report. |
| `scripts/Set-AppConsentPolicy.ps1` | Turns user consent off or limits it to verified publishers and low impact permissions, and turns on the admin consent workflow. Plan mode and `-WhatIf` show the change first. |
| `src/AIGuardrails/` | The PowerShell module behind both scripts. |
| `config/` | The AI app watchlist and the permission weights. Edit both to fit your tenant. |
| `policy/AI-Acceptable-Use-Policy.md` | Policy template with tool tiers and a data class table. |
| `assessments/AI-Tool-Risk-Assessment.md` | Review checklist for a new AI tool, mapped to NIST AI RMF and the OWASP Top 10 for LLM Applications. |
| `docs/copilot-oversharing-check.md` | What to check before a broad Microsoft 365 Copilot rollout. |
| `docs/framework-mapping.md` | Which part of the kit covers which framework item. |
| `docs/design-decisions.md` | Why the code works the way it does, and its limits. |
| `samples/` | The synthetic tenant snapshot and the report generated from it. |
| `tests/` | Pester tests and a smoke test that needs no Pester. |

## Quick start

Needs PowerShell 7.2 or later. The offline demo needs nothing else.

```powershell
git clone https://github.com/Patriot7Six/ai-security-guardrails.git
cd ai-security-guardrails
./scripts/Get-AIAppConsents.ps1 -SnapshotPath ./samples/contoso-tenant.json -OutputDirectory ./out
./scripts/Set-AppConsentPolicy.ps1 -SnapshotPath ./samples/contoso-tenant.json -UserConsent LowRiskVerified
```

The first command writes `out/report.md`, `out/findings.csv`, and `out/findings.json`, then prints a summary:

```text
User consent: AllApps. Users can consent to any app for permissions that do not need admin consent. This is the legacy setting.
Admin consent workflow: off.
Findings: 7 (Critical 3, High 2, Medium 1, Low 1).
Report: ./out/report.md
```

The second command prints the exact Microsoft Graph request it would send, without signing in. A committed copy of the report is in [samples/sample-report](samples/sample-report/report.md).

In the sample tenant the report flags an unverified mail assistant with tenant-wide Mail.ReadWrite and Mail.Send, an analytics app that only its publisher name ties to AI, and a support bot holding full_access_as_app, an Exchange Web Services permission Microsoft is retiring in Exchange Online.

## Run it against a tenant

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
./scripts/Get-AIAppConsents.ps1 -TenantId contoso.onmicrosoft.com -SaveSnapshotPath ./contoso.snapshot.json
```

The inventory signs in with three delegated read scopes and sends GET requests only.

| Scope | Used for |
| --- | --- |
| Application.Read.All | Service principals and their application permission assignments |
| Directory.Read.All | Delegated permission grants. Microsoft lists it as the least privileged scope for that call. |
| Policy.Read.All | The authorization policy and the admin consent request policy |

These scopes need admin consent for the Microsoft Graph Command Line Tools app the first time. Sign in with a read-only role. Microsoft's API pages list Global Reader for the grant, service principal, and admin consent policy reads.

A snapshot is a copy of directory data, including app names, publishers, and user object IDs. Store it like any other directory export. `.gitignore` excludes `*.snapshot.json` and `out/`, so neither lands in a commit by accident. A saved snapshot can be analyzed again offline with `-SnapshotPath`.

## Close the consent path

`Set-AppConsentPolicy.ps1` makes two changes, separately or together.

- `-UserConsent Disabled` turns user consent off. `-UserConsent LowRiskVerified` lets users consent only to apps from verified publishers or apps registered in your tenant, for permissions you classify as low impact.
- `-EnableAdminConsentWorkflow -ReviewerUserId <object-id>` gives users a way to request an app instead of hitting a dead end.

```powershell
# Plan against a snapshot. Never signs in.
./scripts/Set-AppConsentPolicy.ps1 -SnapshotPath ./contoso.snapshot.json -UserConsent LowRiskVerified -EnableAdminConsentWorkflow -ReviewerUserId <object-id>

# Live with -WhatIf. Signs in and reads the current policy, writes nothing.
./scripts/Set-AppConsentPolicy.ps1 -UserConsent LowRiskVerified -EnableAdminConsentWorkflow -ReviewerUserId <object-id> -WhatIf

# Live. Asks before each write, then reads the policy back to confirm.
./scripts/Set-AppConsentPolicy.ps1 -UserConsent LowRiskVerified -EnableAdminConsentWorkflow -ReviewerUserId <object-id>
```

Before a live run:

- A PATCH to `permissionGrantPoliciesAssigned` replaces the whole list. The script keeps every `ManagePermissionGrantsForOwnedResource` entry already there, so resource-specific consent for teams and chats does not change as a side effect.
- Changing user consent needs the Privileged Role Administrator role or higher.
- For the admin consent workflow, Microsoft's setup guide calls for Global Administrator, while the Graph API reference lists Cloud Application Administrator and Application Administrator. Try the lower role first.
- `LowRiskVerified` depends on your permission classifications. Microsoft names openid, profile, email, and offline_access as the minimum for basic sign-in, which makes them a reasonable first set to classify as low impact.
- Entra also offers a Microsoft managed consent option. The script does not set it. If a tenant has the `microsoft-user-default-recommended` policy assigned, the inventory reports `MicrosoftManaged`.
- Reviewers are user object IDs. Group and role reviewers are not supported yet.

## How scoring works

Each finding is one app's grants on one resource API, delegated or application. The score starts at the weight of the highest weighted permission and adds points from this table. Scores cap at 100.

| Factor | Points |
| --- | --- |
| Highest weighted permission | Its weight in `config/permission-risk.json` |
| Each additional sensitive permission | +5 |
| Delegated consent for every user in the tenant | +15 |
| Publisher not verified | +15 |
| offline_access next to a sensitive permission | +10 |
| 10 or more users consented individually | +10 |

Levels are Critical at 80 and up, High from 50 to 79, Medium from 25 to 49, and Low below 25. Application permissions carry higher weights than the same delegated permission, because they run with no signed-in user and reach every mailbox or site unless scoped.

Every finding lists the reasons behind its score, so a reviewer can check the math and change a weight. The weights are a starting point. Tune them to your own data classification.

## How AI apps are detected

`config/ai-app-watchlist.json` holds two lists of patterns, checked against each app's display name, publisher name, and verified publisher name. Vendor patterns (OpenAI, Anthropic, Otter, and others) are checked first and count as the stronger match. Generic patterns (AI, GPT, LLM, Assistant, Summar, and others) catch the rest. Matching is a heuristic, and every match needs a person to look at it. Run with `-IncludeNonAI` to score every non-Microsoft app in the tenant.

Microsoft first-party apps are skipped, identified by the owner tenant IDs Microsoft publishes.

## Framework mapping

The policy, the assessment, and the scripts map to the NIST AI Risk Management Framework (AI RMF 1.0), its Generative AI Profile (NIST AI 600-1), and the OWASP Top 10 for LLM Applications 2025. See [docs/framework-mapping.md](docs/framework-mapping.md). The mapping shows where each part contributes. Using the kit does not make an organization compliant with any of them.

## Tests

```powershell
./tests/Invoke-Smoke.ps1                    # plain assertions, no Pester needed
Invoke-Pester ./tests -Output Detailed      # Pester 5.5 or later
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

CI runs all three on every push to main and every pull request.

## What this does not cover

Consent grants are one path. The kit does not see:

- AI tools used in a browser with no sign-in, where people paste text. Defender for Cloud Apps discovery or web gateway logs cover that.
- Browser extensions. Manage those with your browser policy.
- API keys created on personal accounts with an AI vendor.
- AI features added to apps you already approved.

[docs/design-decisions.md](docs/design-decisions.md) covers these limits and the reasoning behind the code.

## About

Built by Bradley Baker ([bradbaker-it.com](https://bradbaker-it.com)). It draws on my work administering Microsoft 365 Copilot and app consent governance for a 4,300-user regulated tenant. All data here is synthetic.

MIT License. See [LICENSE](LICENSE).
