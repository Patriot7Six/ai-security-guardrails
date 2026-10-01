# Copilot oversharing check

Microsoft 365 Copilot answers from content the signed-in user can already open. It does not change permissions. A site shared too broadly years ago becomes easy to find once Copilot is on. Run this check before a broad rollout.

Feature names, licensing, and preview status change often. Each item below was checked against Microsoft Learn in October 2026. Confirm it again before you act.

## 1. Find content shared too broadly

- Run the SharePoint Advanced Management data access governance reports. The sharing links report shows the sites where users created the most "Anyone", "People in your organization", and "Specific people" links. A separate report covers content shared with "Everyone except external users".
- Start with sites that hold Confidential or Restricted data (see [the policy](../policy/AI-Acceptable-Use-Policy.md)) and appear in either report.
- Ask each site owner to confirm the intended audience. Remove "Everyone except external users" where nobody meant to grant it.

## 2. Keep sensitive sites out of Copilot while you fix them

- Restricted Content Discovery keeps a site out of Copilot and organization-wide search results. It does not change permissions. People with access can still open the content directly, and users can still find content they own or recently worked on. It does not cover OneDrive. It is a SharePoint Advanced Management feature, so check licensing first.
- Restricted SharePoint Search was the earlier stopgap. Microsoft describes it as temporary, blocked new enablement starting July 31, 2026, and points customers to Restricted Content Discovery.

## 3. Use labels and DLP

- Copilot returns content protected by an encrypting sensitivity label only when the user has both the View and Extract usage rights. A label that withholds Extract keeps that content out of Copilot answers for those users.
- A Microsoft Purview DLP policy with the Microsoft 365 Copilot location can stop Copilot from processing items that carry specific sensitivity labels.
- The same location can block a response when the prompt contains sensitive information types. That option was in preview when this was written.

## 4. Watch AI use

Microsoft Purview Data Security Posture Management now covers AI apps and agents, Copilot included. The older DSPM for AI page is labeled classic. Microsoft describes it as a central place to secure data for AI apps and monitor AI use.

## 5. Roll out in waves

- Start with a pilot group whose sites already passed steps 1 through 3.
- Add departments as their site owners confirm audiences.
- Run the data access governance reports again before each wave.
- Run `./scripts/Get-AIAppConsents.ps1` at the same time to catch other AI tools users connected.
