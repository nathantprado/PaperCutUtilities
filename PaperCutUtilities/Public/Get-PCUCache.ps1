function Get-PCUCache {
    <#
    .SYNOPSIS
        Lists entries in the in-memory PCU cache (values of API keys are never shown).
    .EXAMPLE
        Get-PCUCache
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$Name)
    foreach ($k in ($script:PCUCache.Keys | Sort-Object)) {
        $parts = $k -split '\|', 2
        if ($Name -and $parts[0] -notlike $Name) { continue }
        $value = $script:PCUCache[$k].Value
        if ($parts[0] -like 'ApiKey:*') { $value = '********' }
        [pscustomobject]@{ Name = $parts[0]; Scope = $parts[1]; CachedAt = $script:PCUCache[$k].CachedAt; Value = $value }
    }
}
