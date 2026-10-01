@{
    RootModule           = 'AIGuardrails.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '3f6c2a9e-8b41-4d7a-9e25-6c1d0b7a4f83'
    Author               = 'Bradley Baker'
    Copyright            = '(c) 2026 Bradley Baker. MIT License.'
    Description          = 'Inventory, scoring, and consent hardening for AI apps in Microsoft Entra ID.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Get-AIGTenantSnapshot'
        'Import-AIGTenantSnapshot'
        'Test-AIGFirstParty'
        'Test-AIGAIApp'
        'Get-AIGPublisherInfo'
        'Measure-AIGPermissionRisk'
        'Get-AIGConsentFinding'
        'Get-AIGUserConsentState'
        'Get-AIGPermissionGrantPolicyUpdate'
        'Get-AIGAdminConsentRequestPolicyBody'
        'Export-AIGReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('EntraID', 'MicrosoftGraph', 'AI', 'Security', 'Consent', 'OAuth')
            LicenseUri = 'https://github.com/Patriot7Six/ai-security-guardrails/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Patriot7Six/ai-security-guardrails'
        }
    }
}
