# AI Tool Risk Assessment

Use this before any AI tool goes on the Approved or Limited tier. Fill in the evidence column as you go, so the decision can be checked later.

| Field | Value |
| --- | --- |
| Tool and vendor | |
| Requested by | |
| Business owner | |
| Users (group and count) | |
| Highest data class requested | Public, Internal, or Confidential |
| Reviewer | |
| Date | |

## Stop conditions

Any one of these ends the review at Not approved until it is fixed.

- The vendor trains models on customer inputs and offers no contractual way to turn that off.
- The tool needs Restricted data to do its job.
- No business owner will sign the decision record.
- The tool asks for tenant-wide application permissions to mail, files, or chats, and the vendor cannot scope them.
- The vendor will not say where data is stored or which subprocessors handle it.

## How to score

Score each question 0 (no, or unknown), 1 (partly, or only with a workaround), or 2 (yes, with evidence on file). Each section heading shows the NIST AI RMF function and the OWASP Top 10 for LLM Applications (2025) items the section covers.

### A. Use case and data (MAP, LLM02)

| # | Question | Score | Evidence |
| --- | --- | --- | --- |
| A1 | Is the business problem written down, with a way to tell whether the tool solved it? | | |
| A2 | Is the data the tool will see listed, and is its class within what the tier allows? | | |
| A3 | Does the contract keep our data out of model training? | | |
| A4 | Are retention periods for prompts, outputs, and logs stated and acceptable? | | |
| A5 | Can we delete our data on request and at contract end? | | |
| A6 | Is data stored and processed in regions we accept? | | |

### B. Identity and access (GOVERN, MANAGE, LLM06)

| # | Question | Score | Evidence |
| --- | --- | --- | --- |
| B1 | Does the tool support single sign-on with Microsoft Entra ID? | | |
| B2 | Are the requested permissions the minimum the feature needs? List each one. | | |
| B3 | Does it use delegated permissions where it can, instead of application permissions? | | |
| B4 | If it needs application permissions, can they be scoped to named sites or mailboxes (Sites.Selected for SharePoint, RBAC for Applications in Exchange Online)? | | |
| B5 | If it asks for offline_access, is there a business reason for access while the user is away? | | |
| B6 | Can the pilot be limited to an assigned group (user assignment required)? | | |
| B7 | Can the tool act on its own, such as sending mail, changing files, or calling APIs, without a person approving each action? If yes, are the limits written down? | | |

### C. Model behavior (MEASURE, LLM01, LLM05, LLM07, LLM08, LLM09)

| # | Question | Score | Evidence |
| --- | --- | --- | --- |
| C1 | Has the vendor documented how it handles prompt injection hidden in content the tool reads, such as email or documents? | | |
| C2 | Is output treated as untrusted before it reaches another system? For example, generated code and links are never run or opened automatically. | | |
| C3 | Is the system prompt free of secrets, keys, and internal details? | | |
| C4 | Does the tool show sources so users can check answers? | | |
| C5 | Did a short test with our own sample content give acceptable results? Attach the test notes. | | |
| C6 | If the tool indexes our content for retrieval, does it enforce each user's existing permissions on what it returns? | | |

### D. Vendor and supply chain (GOVERN, LLM03, LLM04)

| # | Question | Score | Evidence |
| --- | --- | --- | --- |
| D1 | Does the vendor have a current SOC 2 Type II report or ISO/IEC 27001 certificate that covers this product? | | |
| D2 | Does the vendor follow ISO/IEC 42001 or publish an AI governance program? | | |
| D3 | Are third-party models and subprocessors listed, with notice before they change? | | |
| D4 | Does the vendor explain how it protects training and fine-tuning data from tampering? | | |
| D5 | Does the contract name a security contact and a breach notice period? | | |

### E. Monitoring and exit (MANAGE, LLM10)

| # | Question | Score | Evidence |
| --- | --- | --- | --- |
| E1 | Do we get sign-in and activity logs we can send to our SIEM? | | |
| E2 | Are there usage or spending limits that stop runaway use? | | |
| E3 | Is there a named owner who reviews the tool at least once a year? | | |
| E4 | Is there an exit plan to revoke grants, delete data, and export what we need? | | |

## Decision

The maximum score is 56.

| Result | Default decision |
| --- | --- |
| 45 or more, with no 0 in section B | Approved |
| 31 to 44, or 45 or more with a 0 in section B | Limited, with written conditions |
| 30 or less, or any stop condition | Not approved |

The reviewer can move a tool down a tier for reasons the score does not capture. Moving a tool up needs the security lead's sign-off.

| Field | Value |
| --- | --- |
| Decision | Approved, Limited, or Not approved |
| Tier and highest data class allowed | |
| Conditions | |
| Next review date | |
| Business owner sign-off | |
| Security sign-off | |

## After approval

- Set appRoleAssignmentRequired to true on the app's service principal and assign the pilot group.
- After the pilot, run `./scripts/Get-AIAppConsents.ps1` and confirm the grants match what section B approved.
- Add the tool to the AI tool register with its tier, data class, and conditions.
- Put the next review date on the business owner's calendar.
