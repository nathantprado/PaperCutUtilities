function Get-PCUConfiguration {
    <#
    .SYNOPSIS
        Parses PaperCut server configuration files into a summary object.
    .DESCRIPTION
        Reads server.properties, security.properties, service.conf-style files (*.conf in
        server\bin\win) and other *.properties/*.conf under server\ and server\data\conf.
        Derives the database type, high-availability flag and configured ports.
        Secret values (passwords, tokens, keys) are masked unless -IncludeSecrets is used.
        Results are cached in memory.
    .PARAMETER ComputerName
        Remote computer to read from.
    .PARAMETER IncludeSecrets
        Return secret values unmasked.
    .PARAMETER Refresh
        Re-read the files instead of using the cache.
    .EXAMPLE
        Get-PCUConfiguration | Select-Object DatabaseType, HighAvailability, Ports
    .EXAMPLE
        (Get-PCUConfiguration).Entries | Where-Object File -like '*server.properties'
    .OUTPUTS
        PSCustomObject: ComputerName, DatabaseType, DatabaseUrl, HighAvailability, Ports, Entries.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [switch]$IncludeSecrets,
        [switch]$Refresh
    )

    $raw = @(Get-PCURawConfiguration -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop)

    $entries = foreach ($e in $raw) {
        $secret = Test-PCUSecretKey -Key $e.Key
        $value = $e.Value
        if ($secret -and -not $IncludeSecrets -and $value) { $value = '********' }
        [pscustomobject]@{
            File     = $e.File
            Key      = $e.Key
            Value    = $value
            IsSecret = $secret
        }
    }

    $dbUrl = Get-PCUEntryValue -Entries $raw -Key 'database.url', 'database.jdbc-url'
    $dbType = ConvertTo-PCUDatabaseType -Type (Get-PCUEntryValue -Entries $raw -Key 'database.type') -Url $dbUrl

    $haHits = @($raw | Where-Object {
            $_.Key -match '(?i)(^|[.-])(ha|cluster(ing)?)([.-]|$)' -and $_.Value -and $_.Value -notmatch '^(?i:false|no|0|n)$'
        })

    $ports = foreach ($e in $raw) {
        $num = 0
        if ($e.Key -match '(?i)port' -and [int]::TryParse($e.Value, [ref]$num) -and $num -ge 1 -and $num -le 65535) {
            [pscustomobject]@{ Key = $e.Key; Port = $num; File = $e.File }
        }
    }

    $computer = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
    [pscustomobject]@{
        PSTypeName       = 'PCU.Configuration'
        ComputerName     = $computer
        DatabaseType     = $dbType
        DatabaseUrl      = $dbUrl
        HighAvailability = ($haHits.Count -gt 0)
        Ports            = @($ports)
        Entries          = @($entries)
    }
}
