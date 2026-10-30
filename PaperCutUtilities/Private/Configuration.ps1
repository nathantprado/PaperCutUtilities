function Test-PCUSecretKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    return ($Key -match '(?i)(password|passwd|secret|token|api[._-]?key|credential|passphrase|private|\.key$|^key$)')
}

function Read-PCUPropertiesFile {
    <#
    .SYNOPSIS
        Parses a Java-style .properties / .conf file (key=value, # and ! comments) into entries.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith('#') -or $trim.StartsWith('!')) { continue }
        $idx = $trim.IndexOf('=')
        if ($idx -lt 1) { continue }
        [pscustomobject]@{
            File  = $Path
            Key   = $trim.Substring(0, $idx).Trim()
            Value = $trim.Substring($idx + 1).Trim()
        }
    }
}

function Read-PCUConfigFiles {
    <#
    .SYNOPSIS
        Reads every PaperCut config file under an install; runs locally or remotely.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ServerPath)
    $files = @()
    $files += @(Get-ChildItem -Path (Join-Path $ServerPath '*.properties') -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -Path (Join-Path (Join-Path (Join-Path $ServerPath 'bin') 'win') '*.conf') -ErrorAction SilentlyContinue)
    $dataConf = Join-Path (Join-Path $ServerPath 'data') 'conf'
    $files += @(Get-ChildItem -Path (Join-Path $dataConf '*.properties') -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem -Path (Join-Path $dataConf '*.conf') -ErrorAction SilentlyContinue)
    foreach ($f in ($files | Sort-Object FullName -Unique)) {
        Read-PCUPropertiesFile -Path $f.FullName
    }
}

function Get-PCURawConfiguration {
    <#
    .SYNOPSIS
        Cached, unmasked config entries (internal use only).
    #>
    [CmdletBinding()]
    param([string]$ComputerName, [pscredential]$Credential, [switch]$Refresh)
    $key = Get-PCUCacheKey -Name 'RawConfiguration' -ComputerName $ComputerName
    if (-not $Refresh -and (Test-PCUCacheEntry $key)) { return (Get-PCUCacheEntry $key) }
    $install = Get-PCUInstallPath -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop
    $entries = @(Invoke-PCURemote -ComputerName $ComputerName -Credential $Credential `
            -Function 'Read-PCUPropertiesFile', 'Read-PCUConfigFiles' -ArgumentList @($install.ServerPath) `
            -ScriptBlock { param($ServerPath) Read-PCUConfigFiles -ServerPath $ServerPath })
    Set-PCUCacheEntry -Key $key -Value $entries | Out-Null
    return $entries
}

function Get-PCUEntryValue {
    [CmdletBinding()]
    param($Entries, [string[]]$Key)
    foreach ($k in $Key) {
        $hit = @($Entries | Where-Object { $_.Key -ieq $k } | Select-Object -First 1)
        if ($hit.Count -gt 0) { return $hit[0].Value }
    }
    return $null
}

function ConvertTo-PCUDatabaseType {
    [CmdletBinding()]
    param([string]$Type, [string]$Url)
    $text = ('{0} {1}' -f $Type, $Url)
    switch -Regex ($text) {
        'sqlserver|mssql|jtds:sqlserver' { return 'SQLServer' }
        'postgres' { return 'PostgreSQL' }
        'oracle' { return 'Oracle' }
        'mysql|mariadb' { return 'MySQL' }
        'derby|internal|embedded' { return 'Derby' }
    }
    if (-not $Type -and -not $Url) { return 'Derby' }
    return 'Unknown'
}
