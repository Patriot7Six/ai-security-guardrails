# Copilot oversharing check

Microsoft 365 Copilot grounds its answers in data the signed-in user already has permission to access. Content that user cannot open is not returned. A site shared too broadly becomes easy to find once Copilot is on. Run this check before a broad rollout.

Feature names, licensing, and preview status change often. Each item below was checked against Microsoft Learn pages last updated between June and September 2026. Confirm it again before you act.

## 1. Find content shared too broadly

- Run the SharePoint Advanced Management data access governance reports. Start with the snapshot report "Site permissions across your organization", which shows current exposure whatever the date of the sharing.
- Then run the two activity reports. They cover the last 28 days and list up to 100 sites each. The Sharing links reports show the sites with the most new "Anyone", "People in the organization", and externally shared "Specific people" links. A separate report covers content shared with "Everyone except external users".
- Microsoft says these features come with at least one Microsoft Copilot license assigned, or with SharePoint Advanced Management.
- Start with sites that hold Confidential or Restricted data (see [the policy](../policy/AI-Acceptable-Use-Policy.md)) and appear in any report.
- Use site access reviews to ask each site owner to confirm the intended audience. Remove "Everyone except external users" where nobody meant to grant it.
- For a site that needs immediate lockdown, use restricted access control to limit access to a specific group.

## 2. Keep sensitive sites out of Copilot results while you fix them

- Restricted Content Discovery limits discovery of a site's content in organization-wide search and Copilot responses. It does not change permissions, so people with access can still open the content directly. Users can still find content they own or recently interacted with, and searches that start inside the site are not affected. It does not support OneDrive. Large sites can take more than a week to update. Microsoft describes it as a temporary governance control. It needs a Copilot license and SharePoint Advanced Management.
- Restricted SharePoint Search was the earlier stopgap. Microsoft says it is retiring, blocks new enablement starting July 31, 2026, and points customers to Restricted Content Discovery.

## 3. Use labels and DLP

- For an encrypting sensitivity label, Copilot returns the data only when the user has both the View and Extract usage rights. If a label withholds Extract, Copilot does not summarize that content but can reference it with a link. Files open in an Office app and the active Edge tab are documented exceptions.
- A Microsoft Purview DLP policy with the Microsoft 365 Copilot and Copilot Chat location can stop Copilot from using items that carry specific sensitivity labels. The items can still appear in the citations of a response.
- The same location can block a response when the prompt contains sensitive information types. Microsoft labels that option preview and still rolling out to tenants, as of its September 2026 update. A single rule cannot use both a sensitive information type condition and a sensitivity label condition.

## 4. Watch AI use

Microsoft Purview Data Security Posture Management now covers AI apps and agents. The older DSPM for AI page is labeled classic and describes a central management location to secure data for AI apps and monitor AI use.

## 5. Roll out in waves

Microsoft's deployment guidance describes a path of identifying high-risk sites and files, applying interim access restrictions if needed, fixing access issues, and enforcing guardrails. It does not define waves. The waves below are this kit's own design.

- Start with a pilot group whose sites already passed steps 1 through 3.
- Add departments as their site owners confirm audiences through site access reviews.
- Run the data access governance reports again before each wave.
- Apply site lifecycle policies, such as ownership, inactive-site, and attestation policies, to keep the result.
- Run `./scripts/Get-AIAppConsents.ps1` at the same time to catch other AI tools users connected.
