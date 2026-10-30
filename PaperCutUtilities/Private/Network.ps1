$script:PCURoleServicePatterns = [ordered]@{
    'Application'        = 'Application Server|pc-server'
    'Secondary'          = 'Secondary'
    'Site'               = 'Site Server|sitesvr|pc-site'
    'PrintDeploy'        = 'Print ?Deploy'
    'MobilityPrint'      = 'Mobility'
    'DocumentProcessing' = 'Document ?Processing|pc-doc'
}

$script:PCURoleConfigPatterns = [ordered]@{
    'Secondary'          = 'secondary'
    'Site'               = 'site-?server|site\.server'
    'PrintDeploy'        = 'print-?deploy'
    'MobilityPrint'      = 'mobility'
    'DocumentProcessing' = 'document-?processing'
}

function Get-PCUServiceInfo {
    [CmdletBinding()]
    param()
    Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'PaperCut*' -or $_.DisplayName -like 'PaperCut*' -or $_.Name -like 'pc-*' } |
        ForEach-Object { [pscustomobject]@{ Name = $_.Name; DisplayName = $_.DisplayName; State = $_.State; PathName = $_.PathName } }
}

function Resolve-PCUHostInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $ips = @()
    $fqdn = $Name
    try {
        $entry = [System.Net.Dns]::GetHostEntry($Name)
        $fqdn = $entry.HostName
        $ips = @($entry.AddressList | ForEach-Object { $_.IPAddressToString })
    }
    catch { Write-Verbose "DNS lookup failed for ${Name}: $($_.Exception.Message)" }
    [pscustomobject]@{ HostName = $fqdn; IPAddress = $ips }
}

function ConvertTo-PCUHostName {
    [CmdletBinding()]
    param([string]$Value)
    if (-not $Value) { return $null }
    $v = $Value.Trim()
    if ($v -match '^[a-z][a-z0-9+.-]*://') {
        try { return ([uri]$v).Host } catch { return $null }
    }
    $v = ($v -split '[:/,;\s]')[0]
    if ($v -match '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') { return $v }
    return $null
}

function Test-PCUTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $ar = $client.BeginConnect($HostName, $Port, $null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($ar)
            return [pscustomobject]@{ Open = $true; ResponseMs = $sw.ElapsedMilliseconds; Error = $null }
        }
        return [pscustomobject]@{ Open = $false; ResponseMs = $null; Error = 'Timed out' }
    }
    catch {
        return [pscustomobject]@{ Open = $false; ResponseMs = $null; Error = $_.Exception.Message }
    }
    finally { $client.Close() }
}
