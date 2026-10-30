function Invoke-PCURemote {
    <#
    .SYNOPSIS
        Runs a script block locally, or on a remote computer via Invoke-Command.
    .DESCRIPTION
        Functions named in -Function are serialized into the remote session so the
        script block can call module-private helpers.
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [string[]]$Function = @()
    )

    if (Test-PCULocalComputer $ComputerName) {
        return (& $ScriptBlock @ArgumentList)
    }

    $definitions = foreach ($name in $Function) {
        'function {0} {{{1}{2}{1}}}' -f $name, [Environment]::NewLine, (Get-Command -Name $name -CommandType Function).Definition
    }
    $wrapper = {
        param($Definitions, $BlockText, $BlockArgs)
        . ([scriptblock]::Create($Definitions))
        & ([scriptblock]::Create($BlockText)) @BlockArgs
    }
    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = $wrapper
        ArgumentList = @(($definitions -join [Environment]::NewLine), $ScriptBlock.ToString(), $ArgumentList)
        ErrorAction  = 'Stop'
    }
    if ($Credential) { $invokeParams['Credential'] = $Credential }
    Invoke-Command @invokeParams
}
