function Invoke-PCUHealthApi {
    <#
    .SYNOPSIS
        Calls the PaperCut Health Monitoring API (/api/health) on HTTP port 9191, then HTTPS 9192.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$Key
    )
    $headers = @{ Authorization = $Key }
    $lastError = $null
    foreach ($base in "http://${HostName}:9191", "https://${HostName}:9192") {
        try {
            $r = Invoke-RestMethod -Uri "$base/api/health" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
            return [pscustomobject]@{ Success = $true; Message = "Health API responded at $base."; Response = $r }
        }
        catch { $lastError = $_.Exception.Message }
    }
    return [pscustomobject]@{ Success = $false; Message = "Health API failed: $lastError"; Response = $null }
}
