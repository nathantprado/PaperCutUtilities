function ConvertFrom-PCUJdbcUrl {
    <#
    .SYNOPSIS
        Parses a JDBC URL (SQL Server, PostgreSQL, Oracle, MySQL) into host/port/database.
    #>
    [CmdletBinding()]
    param([string]$Url)
    if (-not $Url) { return $null }
    $r = @{ Host = $null; Port = $null; Database = $null; Type = $null }
    if ($Url -match '^jdbc:(?:jtds:)?sqlserver://([^:;/\\]+)(?:\\([^:;]+))?(?::(\d+))?(.*)$') {
        $r.Type = 'SQLServer'; $r.Host = $Matches[1]; $r.Instance = $Matches[2]
        $r.Port = if ($Matches[3]) { [int]$Matches[3] } else { 1433 }
        if ($Matches[4] -match '(?i)database(?:Name)?=([^;]+)') { $r.Database = $Matches[1] }
    }
    elseif ($Url -match '^jdbc:postgresql://([^:/]+)(?::(\d+))?/([^?]+)') {
        $r.Type = 'PostgreSQL'; $r.Host = $Matches[1]; $r.Database = $Matches[3]
        $r.Port = if ($Matches[2]) { [int]$Matches[2] } else { 5432 }
    }
    elseif ($Url -match '^jdbc:oracle:thin:@(?://)?([^:/]+)(?::(\d+))?[:/]([^?]+)') {
        $r.Type = 'Oracle'; $r.Host = $Matches[1]; $r.Database = $Matches[3]
        $r.Port = if ($Matches[2]) { [int]$Matches[2] } else { 1521 }
    }
    elseif ($Url -match '^jdbc:(?:mysql|mariadb)://([^:/]+)(?::(\d+))?/([^?]+)') {
        $r.Type = 'MySQL'; $r.Host = $Matches[1]; $r.Database = $Matches[3]
        $r.Port = if ($Matches[2]) { [int]$Matches[2] } else { 3306 }
    }
    else { return $null }
    return [pscustomobject]$r
}

function Invoke-PCUDatabaseLogin {
    <#
    .SYNOPSIS
        Attempts a real login using .NET providers. Isolated so tests can mock it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('SQLServer', 'PostgreSQL', 'Oracle', 'MySQL')][string]$Type,
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Password,
        [int]$TimeoutSeconds = 5
    )
    $conn = $null
    try {
        switch ($Type) {
            'SQLServer' {
                $server = $Target.Host
                if ($Target.PSObject.Properties['Instance'] -and $Target.Instance) { $server = '{0}\{1}' -f $Target.Host, $Target.Instance }
                else { $server = '{0},{1}' -f $Target.Host, $Target.Port }
                $sb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
                $sb['Data Source'] = $server
                $sb['Initial Catalog'] = $Target.Database
                $sb['User ID'] = $UserName
                $sb['Password'] = $Password
                $sb['Connect Timeout'] = $TimeoutSeconds
                $conn = New-Object System.Data.SqlClient.SqlConnection $sb.ConnectionString
            }
            default {
                $drivers = @{ PostgreSQL = 'PostgreSQL Unicode*', 'PostgreSQL ANSI*'; Oracle = 'Oracle in*'; MySQL = 'MySQL ODBC*' }[$Type]
                $installed = @()
                if (Get-Command Get-OdbcDriver -ErrorAction SilentlyContinue) { $installed = @(Get-OdbcDriver | ForEach-Object { $_.Name }) }
                $driver = $installed | Where-Object { $n = $_; $drivers | Where-Object { $n -like $_ } } | Select-Object -First 1
                if (-not $driver) { return [pscustomobject]@{ Success = $false; Message = "No ODBC driver installed for $Type; TCP reachability only." ; Skipped = $true } }
                $cs = switch ($Type) {
                    'Oracle' { 'Driver={{{0}}};Dbq={1}:{2}/{3};Uid={4};Pwd={5};' -f $driver, $Target.Host, $Target.Port, $Target.Database, $UserName, $Password }
                    default { 'Driver={{{0}}};Server={1};Port={2};Database={3};Uid={4};Pwd={5};' -f $driver, $Target.Host, $Target.Port, $Target.Database, $UserName, $Password }
                }
                $conn = New-Object System.Data.Odbc.OdbcConnection $cs
                $conn.ConnectionTimeout = $TimeoutSeconds
            }
        }
        $conn.Open()
        return [pscustomobject]@{ Success = $true; Message = 'Login succeeded.'; Skipped = $false }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message; Skipped = $false }
    }
    finally { if ($conn) { $conn.Dispose() } }
}
