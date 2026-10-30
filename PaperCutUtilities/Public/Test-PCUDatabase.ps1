function Test-PCUDatabase {
    <#
    .SYNOPSIS
        Tests the PaperCut application database using settings from server.properties.
    .DESCRIPTION
        Detects the database type (SQL Server, PostgreSQL, Oracle, MySQL, or embedded
        Derby) from database.type / database.url, checks TCP reachability, and, when
        credentials are usable, attempts a real login through .NET (SqlClient for SQL
        Server, ODBC for PostgreSQL/Oracle/MySQL if a driver is installed). Encrypted
        (ENC(...)) passwords cannot be used; supply -DatabaseCredential to override. Derby
        (embedded) databases are reported as not remotely testable.
    .PARAMETER ComputerName
        Application server whose configuration to read.
    .PARAMETER DatabaseCredential
        Database credential override.
    .PARAMETER Credential
        Credential for remoting.
    .PARAMETER TimeoutSeconds
        Connection timeout.
    .PARAMETER Refresh
        Re-read the configuration.
    .EXAMPLE
        Test-PCUDatabase | Format-List
    .OUTPUTS
        PSCustomObject: DatabaseType, Host, Port, Database, TcpReachable, LoginTested, LoginSucceeded, Status, Message.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$DatabaseCredential,
        [pscredential]$Credential,
        [int]$TimeoutSeconds = 5,
        [switch]$Refresh
    )

    $raw = @(Get-PCURawConfiguration -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop)
    $url = Get-PCUEntryValue -Entries $raw -Key 'database.url', 'database.jdbc-url'
    $type = ConvertTo-PCUDatabaseType -Type (Get-PCUEntryValue -Entries $raw -Key 'database.type') -Url $url

    $result = [ordered]@{
        PSTypeName     = 'PCU.DatabaseTestResult'
        DatabaseType   = $type
        Host           = $null
        Port           = $null
        Database       = $null
        TcpReachable   = $null
        LoginTested    = $false
        LoginSucceeded = $null
        Status         = 'Unknown'
        Message        = $null
    }

    if ($type -eq 'Derby') {
        $result.Status = 'NotTestable'
        $result.Message = 'Embedded Derby database cannot be tested remotely.'
        return [pscustomobject]$result
    }

    $target = ConvertFrom-PCUJdbcUrl -Url $url
    if (-not $target) {
        $result.Status = 'Unknown'
        $result.Message = "Could not parse database URL for type $type."
        return [pscustomobject]$result
    }
    $result.Host = $target.Host; $result.Port = $target.Port; $result.Database = $target.Database

    $tcp = Test-PCUTcpPort -HostName $target.Host -Port $target.Port -TimeoutMs ($TimeoutSeconds * 1000)
    $result.TcpReachable = $tcp.Open
    if (-not $tcp.Open) {
        $result.Status = 'Unhealthy'
        $result.Message = "Cannot reach $($target.Host):$($target.Port) ($($tcp.Error))."
        return [pscustomobject]$result
    }

    $user = $null; $pass = $null
    if ($DatabaseCredential) {
        $user = $DatabaseCredential.UserName
        $pass = $DatabaseCredential.GetNetworkCredential().Password
    }
    else {
        $user = Get-PCUEntryValue -Entries $raw -Key 'database.username', 'database.user'
        $pass = Get-PCUEntryValue -Entries $raw -Key 'database.password'
    }

    if (-not $user -or -not $pass -or $pass -like 'ENC(*') {
        $result.Status = 'Healthy'
        $result.Message = 'Port reachable; login not tested (credentials missing or encrypted). Use -DatabaseCredential.'
        return [pscustomobject]$result
    }

    $login = Invoke-PCUDatabaseLogin -Type $type -Target $target -UserName $user -Password $pass -TimeoutSeconds $TimeoutSeconds
    if ($login.Skipped) {
        $result.Status = 'Healthy'
        $result.Message = $login.Message
        return [pscustomobject]$result
    }
    $result.LoginTested = $true
    $result.LoginSucceeded = [bool]$login.Success
    $result.Status = if ($login.Success) { 'Healthy' } else { 'Unhealthy' }
    $result.Message = $login.Message
    return [pscustomobject]$result
}
