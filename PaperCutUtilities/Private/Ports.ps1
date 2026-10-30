function Get-PCUDefaultPort {
    [CmdletBinding()]
    param([string[]]$Role)
    # Defaults per role; 9191/9192 are the PaperCut HTTP/HTTPS ports.
    $table = @{
        'Application'        = @(9191, 9192)
        'Secondary'          = @(9191, 9192)
        'Site'               = @(9191, 9192)
        'PrintDeploy'        = @(9191, 9192)
        'MobilityPrint'      = @(9163, 9164)
        'DocumentProcessing' = @(9191, 9192)
    }
    $ports = foreach ($r in $Role) { if ($table.ContainsKey($r)) { $table[$r] } }
    if (-not $ports) { $ports = @(9191, 9192) }
    return @($ports | Select-Object -Unique)
}
