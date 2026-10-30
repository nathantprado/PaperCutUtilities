#Requires -Version 5.1
Set-StrictMode -Version 2.0

# In-memory cache shared by all PCU functions. Never persisted to disk.
$script:PCUCache = @{}

$privateFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($privateFiles + $publicFiles)) {
    . $file.FullName
}

Export-ModuleMember -Function $publicFiles.BaseName

# Tab completion for Invoke-PCUServerCommand -Command, built from `server-command.exe help`.
Register-ArgumentCompleter -CommandName Invoke-PCUServerCommand -ParameterName Command -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $params = @{}
    if ($fakeBoundParameters.ContainsKey('ComputerName')) { $params['ComputerName'] = $fakeBoundParameters['ComputerName'] }
    $commands = @()
    try { $commands = @(Get-PCUServerCommandList @params) } catch { $commands = @() }
    $commands | Where-Object { $_ -like "$wordToComplete*" } | Sort-Object | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
