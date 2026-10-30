function ConvertFrom-PCUServerCommandHelp {
    <#
    .SYNOPSIS
        Extracts sub-command names from `server-command.exe help` output.
    #>
    [CmdletBinding()]
    param([string[]]$HelpText)
    $names = foreach ($line in $HelpText) {
        if ($line -match '^\s{1,6}([a-z][a-z0-9]*(?:-[a-z0-9]+)+)(?:\s|$)') { $Matches[1] }
    }
    return @($names | Select-Object -Unique)
}

function Get-PCUServerCommandList {
    [CmdletBinding()]
    param([string]$ComputerName)
    $key = Get-PCUCacheKey -Name 'ServerCommandList' -ComputerName $ComputerName
    if (Test-PCUCacheEntry $key) { return (Get-PCUCacheEntry $key) }
    $help = Invoke-PCUServerCommand -Command 'help' -ComputerName $ComputerName -ErrorAction Stop
    $list = ConvertFrom-PCUServerCommandHelp -HelpText $help.Output
    if ($list.Count -gt 0) { Set-PCUCacheEntry -Key $key -Value $list | Out-Null }
    return $list
}
