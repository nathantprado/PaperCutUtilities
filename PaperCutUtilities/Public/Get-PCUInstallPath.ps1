function Get-PCUInstallPath {
    <#
    .SYNOPSIS
        Locates the PaperCut MF/NG application server installation.
    .DESCRIPTION
        Tries, in order: running PaperCut processes (their executable path), Windows
        services (ImagePath), the registry (Uninstall and HKLM\SOFTWARE\PaperCut* keys),
        then default install folders. A location is only accepted if it contains
        server\bin\win\server-command.exe or server\server.properties. The method that
        succeeded is reported in the DiscoveryMethod property. Results are cached.
    .PARAMETER ComputerName
        Remote computer to query via PowerShell remoting. Defaults to the local machine.
    .PARAMETER Credential
        Credential for remoting.
    .PARAMETER Refresh
        Ignore the cached value and discover again.
    .EXAMPLE
        Get-PCUInstallPath

        InstallPath          : C:\Program Files\PaperCut MF
        DiscoveryMethod      : Service
    .EXAMPLE
        (Get-PCUInstallPath -ComputerName print01 -Refresh).ServerCommandPath
    .OUTPUTS
        PSCustomObject with ComputerName, InstallPath, ServerPath, ServerCommandPath,
        ServerPropertiesPath, DiscoveryMethod.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [switch]$Refresh
    )

    $key = Get-PCUCacheKey -Name 'InstallPath' -ComputerName $ComputerName
    if (-not $Refresh -and (Test-PCUCacheEntry $key)) { return (Get-PCUCacheEntry $key) }

    $functions = 'Get-PCUProcessCandidate', 'Get-PCUServiceCandidate', 'Get-PCURegistryCandidate',
    'Get-PCUDefaultCandidate', 'Resolve-PCUInstallRoot', 'Find-PCUInstallPath'
    $found = Invoke-PCURemote -ComputerName $ComputerName -Credential $Credential -Function $functions -ScriptBlock { Find-PCUInstallPath }

    if (-not $found) {
        $target = if ($ComputerName) { $ComputerName } else { 'the local computer' }
        $err = New-Object System.Management.Automation.ErrorRecord (
            (New-Object System.IO.FileNotFoundException "PaperCut installation not found on $target (checked processes, services, registry, default paths)."),
            'PCUInstallNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $target)
        $PSCmdlet.WriteError($err)
        return
    }

    $computer = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
    $result = [pscustomobject]@{
        PSTypeName           = 'PCU.InstallPath'
        ComputerName         = $computer
        InstallPath          = $found.InstallPath
        ServerPath           = $found.ServerPath
        ServerCommandPath    = $found.ServerCommandPath
        ServerPropertiesPath = $found.ServerPropertiesPath
        DiscoveryMethod      = $found.DiscoveryMethod
    }
    Set-PCUCacheEntry -Key $key -Value $result | Out-Null
    return $result
}
