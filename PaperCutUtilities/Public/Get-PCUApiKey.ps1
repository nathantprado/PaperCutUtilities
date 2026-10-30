function Get-PCUApiKey {
    <#
    .SYNOPSIS
        Retrieves a PaperCut API key via server-command.exe.
    .DESCRIPTION
        Health  : the Health Monitoring API key (config key health.api.key).
        XmlRpc  : the XML Web Services auth token (config key auth.webservices.auth-token).
        The value is cached in memory only, returned as a SecureString unless
        -AsPlainText is specified, and is never written to output streams or disk.
    .PARAMETER Type
        Health or XmlRpc.
    .PARAMETER AsPlainText
        Return a plain string instead of a SecureString.
    .PARAMETER ComputerName
        Remote computer to query.
    .PARAMETER Refresh
        Bypass the cache.
    .EXAMPLE
        $key = Get-PCUApiKey -Type Health -AsPlainText
    .OUTPUTS
        System.Security.SecureString (default) or System.String.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString], [string])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Value originates from server-command output and is wrapped immediately.')]
    param(
        [Parameter(Mandatory)][ValidateSet('Health', 'XmlRpc')][string]$Type,
        [switch]$AsPlainText,
        [string]$ComputerName,
        [pscredential]$Credential,
        [switch]$Refresh
    )

    $configKey = switch ($Type) {
        'Health' { 'health.api.key' }
        'XmlRpc' { 'auth.webservices.auth-token' }
    }
    $cacheKey = Get-PCUCacheKey -Name "ApiKey:$Type" -ComputerName $ComputerName
    $value = $null
    if (-not $Refresh -and (Test-PCUCacheEntry $cacheKey)) {
        $value = Get-PCUCacheEntry $cacheKey
    }
    else {
        $res = Invoke-PCUServerCommand -Command 'get-config' -Arguments $configKey -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
        if (-not $res.Success) { throw "server-command get-config $configKey failed (exit code $($res.ExitCode))." }
        $value = (@($res.Output) | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
        if ($value) { $value = $value.Trim() }
        if (-not $value) { throw "No $Type API key is configured ($configKey is empty)." }
        Set-PCUCacheEntry -Key $cacheKey -Value $value | Out-Null
    }
    if ($AsPlainText) { return $value }
    return (ConvertTo-SecureString -String $value -AsPlainText -Force)
}
