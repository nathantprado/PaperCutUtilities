function Clear-PCUCache {
    <#
    .SYNOPSIS
        Clears the in-memory PCU cache (all entries, or those matching -Name).
    .EXAMPLE
        Clear-PCUCache
    .EXAMPLE
        Clear-PCUCache -Name 'Servers'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name = '*')
    foreach ($k in @($script:PCUCache.Keys)) {
        if (($k -split '\|', 2)[0] -like $Name -and $PSCmdlet.ShouldProcess($k, 'Remove cache entry')) {
            $script:PCUCache.Remove($k)
        }
    }
}
