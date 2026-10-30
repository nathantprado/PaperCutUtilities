function Get-PCUCacheKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ComputerName
    )
    if ([string]::IsNullOrEmpty($ComputerName) -or (Test-PCULocalComputer $ComputerName)) {
        $scope = 'local'
    }
    else {
        $scope = $ComputerName.ToLowerInvariant()
    }
    return '{0}|{1}' -f $Name, $scope
}

function Get-PCUCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    if ($script:PCUCache.ContainsKey($Key)) { return $script:PCUCache[$Key].Value }
    return $null
}

function Test-PCUCacheEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    return $script:PCUCache.ContainsKey($Key)
}

function Set-PCUCacheEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Key,
        $Value
    )
    if ($PSCmdlet.ShouldProcess($Key, 'Cache value')) {
        $script:PCUCache[$Key] = [pscustomobject]@{ Value = $Value; CachedAt = Get-Date }
    }
    return $Value
}

function Test-PCULocalComputer {
    [CmdletBinding()]
    param([string]$ComputerName)
    if ([string]::IsNullOrEmpty($ComputerName)) { return $true }
    $localNames = @('.', 'localhost', '127.0.0.1', '::1', $env:COMPUTERNAME, [System.Net.Dns]::GetHostName())
    return ($localNames | Where-Object { $_ -and $_ -ieq $ComputerName } | Measure-Object).Count -gt 0
}
