function Test-PCUConnectivity {
    <#
    .SYNOPSIS
        Tests TCP connectivity to PaperCut servers on default and configured ports.
    .DESCRIPTION
        For each discovered server (see Get-PCUServer) tests the default ports for its
        roles (9191/9192 and role-specific ports). Custom ports found in the target
        computer's configuration files, plus any -Port values, are tested too.
    .PARAMETER ComputerName
        PaperCut host used for discovery and for reading configured ports.
    .PARAMETER Server
        Explicit server host names to test instead of discovery.
    .PARAMETER Port
        Additional ports to test on every server.
    .PARAMETER TimeoutMs
        Per-connection timeout in milliseconds.
    .PARAMETER Refresh
        Refresh discovery caches.
    .EXAMPLE
        Test-PCUConnectivity | Where-Object { -not $_.Open }
    .OUTPUTS
        PSCustomObject: Server, IPAddress, Roles, Port, PortSource, Open, ResponseMs, Error.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [string[]]$Server,
        [int[]]$Port = @(),
        [ValidateRange(100, 60000)][int]$TimeoutMs = 2000,
        [switch]$Refresh
    )

    if ($Server) {
        $targets = foreach ($s in $Server) {
            $info = Resolve-PCUHostInfo -Name $s
            [pscustomobject]@{ HostName = $s; IPAddress = @($info.IPAddress); Roles = @('Application') }
        }
    }
    else {
        $targets = @(Get-PCUServer -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh)
    }

    $customPorts = @()
    try {
        $cfg = Get-PCUConfiguration -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop
        $customPorts = @($cfg.Ports | Where-Object { $_.Key -notmatch '^(?i)(database|db)[.-]' } | ForEach-Object { $_.Port })
    }
    catch { Write-Verbose "Configured ports unavailable: $($_.Exception.Message)" }

    foreach ($t in $targets) {
        $isConfigHost = (-not $Server) -and ($t.Roles -contains 'Application')
        $planned = @{}
        foreach ($p in (Get-PCUDefaultPort -Role $t.Roles)) { $planned[[int]$p] = 'Default' }
        if ($isConfigHost) {
            foreach ($p in $customPorts) { if (-not $planned.ContainsKey([int]$p)) { $planned[[int]$p] = 'Configured' } }
        }
        foreach ($p in $Port) { if (-not $planned.ContainsKey([int]$p)) { $planned[[int]$p] = 'Specified' } }

        foreach ($p in ($planned.Keys | Sort-Object)) {
            $r = Test-PCUTcpPort -HostName $t.HostName -Port $p -TimeoutMs $TimeoutMs
            [pscustomobject]@{
                PSTypeName = 'PCU.ConnectivityResult'
                Server     = $t.HostName
                IPAddress  = $t.IPAddress
                Roles      = $t.Roles
                Port       = $p
                PortSource = $planned[$p]
                Open       = $r.Open
                ResponseMs = $r.ResponseMs
                Error      = $r.Error
            }
        }
    }
}
