@{
    RootModule            = 'PaperCutUtilities.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = '3f6c0a3e-7b5d-4c1e-9a52-6d8e2b7f1c40'
    Author                = 'Nathan Prado'
    Description           = 'Utilities for discovering, configuring, and health-checking PaperCut MF/NG deployments.'
    PowerShellVersion     = '5.1'
    FunctionsToExport     = @(
        'Clear-PCUCache'
        'Get-PCUApiKey'
        'Get-PCUCache'
        'Get-PCUConfiguration'
        'Get-PCUHealth'
        'Get-PCUInstallPath'
        'Get-PCUServer'
        'Invoke-PCUServerCommand'
        'Test-PCUConnectivity'
        'Test-PCUDatabase'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags       = @('PaperCut', 'Print', 'Administration')
            ProjectUri = 'https://github.com/nathantprado/PaperCutUtilities'
        }
    }
}
