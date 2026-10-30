function Get-PCUHealth {
    <#
    .SYNOPSIS
        Aggregates PaperCut health: install, services, database, connectivity and the health API.
    .DESCRIPTION
        Runs each check independently and rolls up to Healthy / Degraded / Unhealthy.
        The Health Monitoring API (/api/health) is queried when a key is available via
        Get-PCUApiKey; failure to obtain a key is reported as a Skipped check, not an error.
    .PARAMETER ComputerName
        PaperCut application server to check.
    .PARAMETER SkipHealthApi
        Do not call the HTTP health API.
    .PARAMETER Refresh
        Refresh all caches first.
    .EXAMPLE
        Get-PCUHealth | Select-Object -ExpandProperty Checks
    .OUTPUTS
        PSCustomObject: ComputerName, Status, Checks.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [switch]$SkipHealthApi,
        [switch]$Refresh
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $addCheck = {
        param($Name, $Status, $Message)
        $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Message = $Message })
    }

    $install = $null
    try {
        $install = Get-PCUInstallPath -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop
        & $addCheck 'Install' 'Healthy' "$($install.InstallPath) (found via $($install.DiscoveryMethod))"
    }
    catch { & $addCheck 'Install' 'Unhealthy' $_.Exception.Message }

    if ($install) {
        try {
            $services = @(Invoke-PCURemote -ComputerName $ComputerName -Credential $Credential -Function 'Get-PCUServiceInfo' -ScriptBlock { Get-PCUServiceInfo })
            $stopped = @($services | Where-Object { $_.State -ne 'Running' })
            if ($services.Count -eq 0) { & $addCheck 'Services' 'Degraded' 'No PaperCut services found.' }
            elseif ($stopped.Count -gt 0) { & $addCheck 'Services' 'Unhealthy' ("Not running: " + (($stopped | ForEach-Object { $_.Name }) -join ', ')) }
            else { & $addCheck 'Services' 'Healthy' "$($services.Count) service(s) running." }
        }
        catch { & $addCheck 'Services' 'Degraded' $_.Exception.Message }

        try {
            $db = Test-PCUDatabase -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop
            $dbStatus = if ($db.Status -eq 'NotTestable' -or $db.Status -eq 'Unknown') { 'Degraded' } else { $db.Status }
            & $addCheck 'Database' $dbStatus "$($db.DatabaseType): $($db.Message)"
        }
        catch { & $addCheck 'Database' 'Degraded' $_.Exception.Message }

        try {
            $conn = @(Test-PCUConnectivity -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop)
            $closed = @($conn | Where-Object { -not $_.Open })
            if ($conn.Count -eq 0) { & $addCheck 'Connectivity' 'Degraded' 'No servers tested.' }
            elseif ($closed.Count -eq 0) { & $addCheck 'Connectivity' 'Healthy' "$($conn.Count) port check(s) open." }
            else {
                # Closed secondary ports (e.g. unused HTTPS) degrade; no open port on any server is unhealthy.
                $st = if (@($conn | Where-Object { $_.Open }).Count -eq 0) { 'Unhealthy' } else { 'Degraded' }
                & $addCheck 'Connectivity' $st ("Closed: " + (($closed | ForEach-Object { '{0}:{1}' -f $_.Server, $_.Port }) -join ', '))
            }
        }
        catch { & $addCheck 'Connectivity' 'Degraded' $_.Exception.Message }

        if ($SkipHealthApi) { & $addCheck 'HealthApi' 'Skipped' 'Skipped by request.' }
        else {
            try {
                $key = Get-PCUApiKey -Type Health -AsPlainText -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
                $target = if ($ComputerName) { $ComputerName } else { 'localhost' }
                $resp = Invoke-PCUHealthApi -HostName $target -Key $key
                & $addCheck 'HealthApi' $(if ($resp.Success) { 'Healthy' } else { 'Unhealthy' }) $resp.Message
            }
            catch { & $addCheck 'HealthApi' 'Skipped' "Health API not queried: $($_.Exception.Message)" }
        }
    }

    $statuses = @($checks | ForEach-Object { $_.Status })
    $overall = if ($statuses -contains 'Unhealthy') { 'Unhealthy' } elseif ($statuses -contains 'Degraded') { 'Degraded' } else { 'Healthy' }
    [pscustomobject]@{
        PSTypeName   = 'PCU.Health'
        ComputerName = $(if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME })
        Status       = $overall
        Checks       = $checks.ToArray()
    }
}
