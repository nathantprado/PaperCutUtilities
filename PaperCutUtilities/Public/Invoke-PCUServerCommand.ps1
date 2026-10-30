function Invoke-PCUServerCommand {
    <#
    .SYNOPSIS
        Runs PaperCut's server-command.exe and returns its output and exit code.
    .DESCRIPTION
        Wraps server-command.exe from the discovered install path. The -Command parameter
        tab-completes using the command list parsed from `server-command.exe help`
        (cached; use Clear-PCUCache to rebuild).
    .PARAMETER Command
        The server-command sub-command, e.g. get-config, list-user-accounts.
    .PARAMETER Arguments
        Arguments passed to the sub-command.
    .PARAMETER ComputerName
        Remote computer to run on via PowerShell remoting.
    .PARAMETER Credential
        Credential for remoting.
    .PARAMETER Refresh
        Re-discover the install path.
    .EXAMPLE
        Invoke-PCUServerCommand -Command get-config -Arguments 'system.name'
    .OUTPUTS
        PSCustomObject with Command, Arguments, ExitCode, Output, Success.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Command,
        [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Arguments = @(),
        [string]$ComputerName,
        [pscredential]$Credential,
        [switch]$Refresh
    )

    $install = Get-PCUInstallPath -ComputerName $ComputerName -Credential $Credential -Refresh:$Refresh -ErrorAction Stop
    if (-not $install.ServerCommandPath) {
        throw "server-command.exe was not found under $($install.InstallPath)."
    }
    $result = Invoke-PCURemote -ComputerName $ComputerName -Credential $Credential -ArgumentList @($install.ServerCommandPath, (@($Command) + @($Arguments))) -ScriptBlock {
        param($Exe, $CommandArgs)
        $out = & $Exe @CommandArgs 2>&1 | ForEach-Object { "$_" }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($out) }
    }
    [pscustomobject]@{
        PSTypeName = 'PCU.ServerCommandResult'
        Command    = $Command
        Arguments  = $Arguments
        ExitCode   = $result.ExitCode
        Output     = $result.Output
        Success    = ($result.ExitCode -eq 0)
    }
}
