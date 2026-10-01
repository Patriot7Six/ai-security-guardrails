# AI Acceptable Use Policy (template)

| Field | Value |
| --- | --- |
| Owner | [Security team] |
| Approved by | [CISO or equivalent] |
| Effective date | [Date] |
| Review cycle | Every 6 months, and when a major tool or law changes |
| Related | AI tool register, AI Tool Risk Assessment, data classification standard, general acceptable use policy |

This is a template. Replace the bracketed items, and have Legal and HR review it before adoption.

## 1. Purpose

AI tools can save people real time. They also open new ways for customer data, credentials, and internal plans to leave the company. This policy sets which tools people can use, what data can go into them, and how to ask for a new one.

## 2. Scope

This policy covers employees, contractors, and anyone else with a company account. It applies to any tool that generates or summarizes text, code, images, audio, or video. That includes web apps, desktop and phone apps, browser extensions, and AI features added to tools the company already uses.

## 3. Approved tools

Every AI tool sits in one of three tiers. The AI tool register at [link] lists each tool, its tier, the highest data class it may handle, and any conditions.

| Tier | What it means |
| --- | --- |
| Approved | Reviewed and under contract. Sign in with your company account. Use it for data up to the class the register allows. |
| Limited | Allowed for a named group or pilot, under the conditions in the register. |
| Not approved | Do not use it for company work. |

A tool that is not in the register is not approved.

## 4. What data can go where

| Data class | Examples | Allowed in |
| --- | --- | --- |
| Public | Published marketing copy, public web pages, press releases | Any Approved or Limited tool |
| Internal | Internal procedures, meeting notes without customer or employee details, draft documents | Approved tools, signed in with a company account |
| Confidential | Customer account data, network diagrams and device configurations, security findings, employee records, contracts | Only Approved tools the register clears for Confidential data |
| Restricted | Passwords, keys, and tokens. Full payment card numbers. Data a law or regulation restricts (see below). Legal holds. Law enforcement and court requests. | No AI tool, unless the register records a written exception for that specific use |

[List the regulated data types that apply to your business, such as protected health information (PHI) under HIPAA, controlled unclassified information (CUI) for federal contractors, or customer proprietary network information (CPNI) for telecommunications carriers. Confirm the list with Legal.]

When you are unsure of the class, treat the data as the higher class and ask [security contact].

## 5. Accounts and access

- Sign in to approved tools with company single sign-on. Do not create a separate account with your company email and a password.
- If a tool asks for access to your mail, files, calendar, or chats, stop at the consent prompt and submit a request instead (section 10). The tenant sends these requests to an admin for review.
- Do not create API keys for an AI service for company work without approval from [security team].
- Where a tool lets you opt out of the vendor training on your inputs, opt out, unless the register says the contract already covers it.
- Install only the AI browser extensions the register lists. An extension can read every page you open.

## 6. Using AI output

- You own anything you send, publish, or commit, whether or not an AI tool helped write it.
- Check facts, numbers, citations, and code before you use them. AI tools can give confident answers that are wrong.
- AI-generated code goes through the same review as any other code before it reaches production.
- Label AI-generated content where the audience would expect to know, such as customer-facing images or recordings.

## 7. Prohibited uses

- Creating fake images, audio, or video of a real person, including coworkers and customers.
- Impersonating the company, a customer, or a coworker.
- Generating malware, phishing content, or tools to get around security controls, outside approved security testing.
- Making decisions about hiring, firing, credit, or service eligibility on AI output alone.
- Using an AI note-taker in a meeting without telling everyone at the start.
- Using a personal AI account for company work.

## 8. AI-driven attacks

Attackers use AI to write convincing phishing messages and to fake voices and video. Treat urgency as a warning sign.

- Verify any request for money, credentials, an MFA approval, or a change to payment or account details through a second channel you already trust. Call back on a number from the company directory, not one in the message.
- Report anything suspicious right away (section 11), even if you are not sure.

## 9. Monitoring and enforcement

The company monitors AI tool use on company devices and accounts. That includes app consent records, data loss prevention (DLP) alerts, and web traffic to AI services. DLP rules may block Confidential or Restricted data from reaching AI tools. Violations are handled under [the disciplinary policy].

## 10. Requesting a new tool

Submit a request at [link] with the tool name, the business problem, the data it will touch, and who will use it. Security runs the AI Tool Risk Assessment and records the decision in the register. The target turnaround for a standard request is [10 business days].

## 11. Reporting

Report suspected misuse, data shared with the wrong tool, or a suspicious AI-generated message to [security contact or ticket queue]. [Confirm with HR.] Prompt, good-faith self-reports are handled as training matters.

## 12. Exceptions

An exception needs written approval from [security team] and the data owner, an end date, and an entry in the register.

## 13. Definitions

| Term | Meaning |
| --- | --- |
| AI tool | Software that produces text, code, images, audio, or video from a prompt, including AI features inside other products |
| AI tool register | The list of reviewed tools, with each tool's tier, allowed data class, and conditions |
| Consent prompt | A sign-in screen that asks you to let an app access your account data |
| DLP | Data loss prevention. Rules that detect sensitive data and can block it from leaving approved systems. |
