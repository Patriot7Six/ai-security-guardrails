# CLAUDE.md

Notes for Claude Code working in this repo.

## What this is

A public portfolio repo. A PowerShell kit inventories AI app consent in Microsoft Entra ID, scores it, and plans the consent hardening. A policy template, a risk assessment, and supporting docs sit alongside it. All tenant data is synthetic. Anything here may come up in an interview, so every claim has to be defensible.

## Commands

```powershell
pwsh ./tests/Invoke-Smoke.ps1
pwsh -c 'Invoke-Pester ./tests -Output Detailed'
pwsh -c 'Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1'
pwsh ./scripts/Get-AIAppConsents.ps1 -SnapshotPath ./samples/contoso-tenant.json -OutputDirectory ./samples/sample-report
```

The smoke test needs no Pester. Pester tests need Pester 5.5 or later. The last command regenerates the committed sample report. Run it after any change to scoring, the fixture, or report text.

## Rules

- Ask before running either script without `-SnapshotPath`. That mode signs in to a real tenant.
- Never commit real tenant data. `*.snapshot.json` and `out/` are ignored for that reason.
- Do not name a real employer, customer, or prospective employer anywhere in the repo.
- Graph calls use `Invoke-MgGraphRequest` with v1.0 URLs. Check every endpoint, permission, and property against Microsoft Learn before adding it.
- Keep PSScriptAnalyzer clean at Error and Warning. That means no `Write-Host`, no aliases, singular nouns, and `ShouldProcess` for anything that changes state.
- ASCII only in every file.
- Prose in docs, the README, and generated report text uses plain words, with no em dashes and no semicolons.
- Expected scores live in three places: `tests/AIGuardrails.Tests.ps1`, `tests/Invoke-Smoke.ps1`, and `samples/sample-report`. Change them together.
