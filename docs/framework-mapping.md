# Framework mapping

This shows where each part of the kit contributes to three references: the NIST AI Risk Management Framework (AI RMF 1.0), its Generative AI Profile (NIST AI 600-1, July 2024), and the OWASP Top 10 for LLM Applications 2026 edition. OWASP renumbered most items in 2026, so IDs from the 2025 edition do not match the IDs below. Using the kit does not make an organization compliant with any of them.

## By component

| Part of the kit | AI RMF function | OWASP 2026 | NIST AI 600-1 risks |
| --- | --- | --- | --- |
| Consent inventory (`Get-AIAppConsents.ps1`) | GOVERN, MAP, MEASURE | LLM02, LLM03 | Data Privacy, Information Security, Value Chain and Component Integration |
| Consent hardening (`Set-AppConsentPolicy.ps1`) | MANAGE | LLM03 | Data Privacy, Information Security |
| Acceptable use policy | GOVERN | LLM02, LLM07, LLM10 | Data Privacy, Information Security, Confabulation, Human-AI Configuration, Information Integrity |
| Risk assessment | GOVERN, MAP, MEASURE, MANAGE | LLM01 to LLM10 | Value Chain and Component Integration, Information Security, Data Privacy, Confabulation |
| Copilot oversharing check | MAP, MEASURE, MANAGE | LLM02, LLM09 | Data Privacy, Information Security |

## By OWASP item

| OWASP 2026 | Where the kit covers it |
| --- | --- |
| LLM01 Prompt Injection | Assessment C1 |
| LLM02 Sensitive Information Disclosure | Policy sections 4 and 5, assessment section A, consent inventory, Copilot oversharing check |
| LLM03 Excessive Agency | Consent inventory and hardening, assessment B2, B3, B4, and B7 |
| LLM04 Supply Chain | Assessment section D |
| LLM05 Data and Model Poisoning | Assessment D4 |
| LLM06 Unbounded Consumption | Assessment E2 |
| LLM07 Misinformation | Policy section 6, assessment C4 and C5 |
| LLM08 Hidden Context Exposure | Assessment C3 |
| LLM09 Vector and Embedding Weaknesses | Assessment C6, Copilot oversharing check |
| LLM10 Improper Output Handling | Assessment C2, and the AI-generated code review bullet in policy section 6 |

LLM08 is the 2026 name for what the 2025 edition called System Prompt Leakage. The 2026 scope is broader, so assessment C3 covers only the system prompt part of it.

## By AI RMF function

| Function | Where the kit covers it |
| --- | --- |
| GOVERN | Acceptable use policy, AI tool register, assessment stop conditions, sections B and D, the decision record, and the consent inventory (GOVERN 1.6 covers inventories of AI systems) |
| MAP | Consent inventory, assessment section A, Copilot oversharing check step 1 |
| MEASURE | Scoring in `config/permission-risk.json`, assessment section C, Copilot oversharing check step 4 |
| MANAGE | Consent hardening, removal commands in the report, assessment sections B and E, Copilot oversharing check steps 2 and 3 and the rollout waves |
