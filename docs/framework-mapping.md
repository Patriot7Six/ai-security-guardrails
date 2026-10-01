# Framework mapping

This shows where each part of the kit contributes to three references: the NIST AI Risk Management Framework (AI RMF 1.0), its Generative AI Profile (NIST AI 600-1), and the OWASP Top 10 for LLM Applications 2025. Using the kit does not make an organization compliant with any of them.

## By component

| Part of the kit | AI RMF function | OWASP 2025 | NIST AI 600-1 risks |
| --- | --- | --- | --- |
| Consent inventory (`Get-AIAppConsents.ps1`) | MAP, MEASURE | LLM02, LLM06 | Data Privacy, Information Security |
| Consent hardening (`Set-AppConsentPolicy.ps1`) | MANAGE | LLM06 | Information Security |
| Acceptable use policy | GOVERN | LLM02, LLM05, LLM09 | Data Privacy, Confabulation, Human-AI Configuration, Information Integrity |
| Risk assessment | GOVERN, MAP, MEASURE, MANAGE | LLM01 to LLM10 | Value Chain and Component Integration, Information Security, Data Privacy, Confabulation |
| Copilot oversharing check | MAP, MANAGE | LLM02, LLM08 | Data Privacy, Information Security |

## By OWASP item

| OWASP 2025 | Where the kit covers it |
| --- | --- |
| LLM01 Prompt Injection | Assessment C1 |
| LLM02 Sensitive Information Disclosure | Policy sections 4 and 5, assessment section A, consent inventory |
| LLM03 Supply Chain | Assessment section D |
| LLM04 Data and Model Poisoning | Assessment D4 |
| LLM05 Improper Output Handling | Policy section 6, assessment C2 |
| LLM06 Excessive Agency | Consent inventory and hardening, assessment B2, B3, B4, and B7 |
| LLM07 System Prompt Leakage | Assessment C3 |
| LLM08 Vector and Embedding Weaknesses | Assessment C6, Copilot oversharing check |
| LLM09 Misinformation | Policy section 6, assessment C4 and C5 |
| LLM10 Unbounded Consumption | Assessment E2 |

## By AI RMF function

| Function | Where the kit covers it |
| --- | --- |
| GOVERN | Acceptable use policy, AI tool register, assessment stop conditions, section D, and the decision record |
| MAP | Consent inventory, assessment section A, Copilot oversharing check steps 1 and 2 |
| MEASURE | Scoring in `config/permission-risk.json`, assessment section C |
| MANAGE | Consent hardening, removal commands in the report, assessment section E, Copilot rollout waves |
