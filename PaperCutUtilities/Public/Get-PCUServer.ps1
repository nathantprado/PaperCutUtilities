function Get-PCUServer {
    <#
    .SYNOPSIS
        Discovers PaperCut servers and their roles.
    .DESCRIPTION
        Builds a server inventory (Application, Secondary, Site, PrintDeploy,
        MobilityPrint, DocumentProcessing) from: the PaperCut services on the target
        computer, hostnames referenced by configuration keys (e.g. site-server,
        secondary, print-deploy, mobility, document-processing), and any servers supplied
        via -AdditionalServer. Hostname, IP addresses and roles are cached.
    .PARAMETER ComputerName
        The application server (or any PaperCut host) to inspect. Defaults to local.
    .PARAMETER AdditionalServer
        Hashtable of extra servers, e.g. @{ 'site01' = 'Site'; 'pd01' = 'PrintDeploy','MobilityPrint' }.
    .PARAMETER Refresh
        Rebuild the inventory instead of using the cache.
    .EXAMPLE
        Get-PCUServer | Format-Table HostName, Roles, IPAddress
    .OUTPUTS
        PSCustomObject: HostName, IPAddress, Roles, Sources.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [hashtable]$AdditionalServer,
        [switch]$Refresh
    )

    $cacheKey = Get-PCUCacheKey -Name 'Servers' -ComputerName $ComputerName
    if (-not $Refresh -and -not $AdditionalServer -and (Test-PCUCacheEntry $cacheKey)) {
        return (Get-PCUCacheEntry $cacheKey)
    }

    $map = @{}
    $add = {
        param($Name, $Role, $Source)
        $k = $Name.ToLowerInvariant()
        if (-not $map.ContainsKey($k)) { $map[$k] = @{ Name = $Name; Roles = @(); Sources = @() } }
        if ($Role -and $map[$k].Roles -notcontains $Role) { $map[$k].Roles += $Role }
        if ($map[$k].Sources -notcontains $Source) { $map[$k].Sources += $Source }
    }

    $self = if ($ComputerName) { $ComputerName } else { [System.Net.Dns]::GetHostName() }
    & $add $self 'Application' 'Install'

    $services = @(Invoke-PCURemote -ComputerName $ComputerName -Credential $Credential -Function 'Get-PCUServiceInfo' -ScriptBlock { Get-PCUServiceInfo })
    foreach ($svc in $services) {
        $text = '{0} {1} {2}' -f $svc.Name, $svc.DisplayName, $svc.PathName
        foreach ($role in $script:PCURoleServicePatterns.Keys) {
            if ($text -match $script:PCURoleServicePatterns[$role] -and $role -ne 'Application') { & $add $self $role 'Service' }
        }
    }

    $raw = @(Get-PCURawConfiguration -ComputerName $ComputerName -Credential $Credential -ErrorAction SilentlyContinue)
    foreach ($e in $raw) {
        foreach ($role in $script:PCURoleConfigPatterns.Keys) {
            if ($e.Key -match $script:PCURoleConfigPatterns[$role] -and $e.Key -notmatch '(?i)(password|secret|token|key$)') {
                $hostName = ConvertTo-PCUHostName -Value $e.Value
                if ($hostName -and $hostName -notmatch '^(true|false|yes|no|\d+)$') { & $add $hostName $role 'Configuration' }
            }
        }
    }

    foreach ($name in @($AdditionalServer.Keys)) {
        $roles = @($AdditionalServer[$name])
        if ($roles.Count -eq 0) { & $add $name $null 'Specified' }
        foreach ($r in $roles) { & $add $name $r 'Specified' }
    }

    $servers = foreach ($k in ($map.Keys | Sort-Object)) {
        $info = Resolve-PCUHostInfo -Name $map[$k].Name
        [pscustomobject]@{
            PSTypeName = 'PCU.Server'
            HostName   = $info.HostName
            IPAddress  = @($info.IPAddress)
            Roles      = @($map[$k].Roles)
            Sources    = @($map[$k].Sources)
        }
    }
    $servers = @($servers)
    Set-PCUCacheEntry -Key $cacheKey -Value $servers | Out-Null
    return $servers
}
