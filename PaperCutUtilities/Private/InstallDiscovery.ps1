function Get-PCUProcessCandidate {
    [CmdletBinding()]
    param()
    $paths = @()
    foreach ($p in @(Get-Process -Name 'pc-server', 'pc-app', 'pc-tray', 'pc-print*', 'pc-mobility*' -ErrorAction SilentlyContinue)) {
        try { if ($p.Path) { $paths += $p.Path } } catch { Write-Verbose "Cannot read path for process $($p.Id)" }
    }
    return $paths
}

function Get-PCUServiceCandidate {
    [CmdletBinding()]
    param()
    $paths = @()
    $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'PaperCut*' -or $_.DisplayName -like 'PaperCut*' })
    foreach ($svc in $services) {
        if ($svc.PathName -match '^\s*"([^"]+)"') { $paths += $Matches[1] }
        elseif ($svc.PathName -match '^\s*(\S+\.exe)') { $paths += $Matches[1] }
    }
    return $paths
}

function Get-PCURegistryCandidate {
    [CmdletBinding()]
    param()
    $paths = @()
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        foreach ($key in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
            if ($props -and $props.PSObject.Properties['DisplayName'] -and $props.DisplayName -like 'PaperCut*') {
                foreach ($name in 'InstallLocation', 'InstallDir') {
                    if ($props.PSObject.Properties[$name] -and $props.$name) { $paths += [string]$props.$name }
                }
            }
        }
    }
    foreach ($vendor in @(Get-ChildItem -Path 'HKLM:\SOFTWARE' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'PaperCut*' })) {
        $props = Get-ItemProperty -Path $vendor.PSPath -ErrorAction SilentlyContinue
        foreach ($name in 'InstallPath', 'InstallDir', 'InstallLocation', 'Path') {
            if ($props -and $props.PSObject.Properties[$name] -and $props.$name) { $paths += [string]$props.$name }
        }
    }
    return $paths
}

function Get-PCUDefaultCandidate {
    [CmdletBinding()]
    param()
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, 'C:\Program Files') | Where-Object { $_ } | Select-Object -Unique
    foreach ($base in $bases) {
        foreach ($product in 'PaperCut MF', 'PaperCut NG') {
            Join-Path -Path $base -ChildPath $product
        }
    }
}

function Resolve-PCUInstallRoot {
    <#
    .SYNOPSIS
        Walks up from a file or folder to the PaperCut app root, validating by server-command.exe / server.properties.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $current = $Path
    for ($i = 0; $i -lt 8 -and $current; $i++) {
        $serverDir = Join-Path -Path $current -ChildPath 'server'
        $command = Join-Path -Path (Join-Path -Path (Join-Path -Path $serverDir -ChildPath 'bin') -ChildPath 'win') -ChildPath 'server-command.exe'
        $properties = Join-Path -Path $serverDir -ChildPath 'server.properties'
        $hasCommand = Test-Path -LiteralPath $command -PathType Leaf
        $hasProperties = Test-Path -LiteralPath $properties -PathType Leaf
        if ($hasCommand -or $hasProperties) {
            return [pscustomobject]@{
                InstallPath          = $current
                ServerPath           = $serverDir
                ServerCommandPath    = $(if ($hasCommand) { $command } else { $null })
                ServerPropertiesPath = $(if ($hasProperties) { $properties } else { $null })
            }
        }
        $parent = Split-Path -Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Find-PCUInstallPath {
    <#
    .SYNOPSIS
        Core discovery logic; runs locally or inside a remote session.
    #>
    [CmdletBinding()]
    param()
    $methods = @(
        @{ Name = 'Process'; Source = { Get-PCUProcessCandidate } },
        @{ Name = 'Service'; Source = { Get-PCUServiceCandidate } },
        @{ Name = 'Registry'; Source = { Get-PCURegistryCandidate } },
        @{ Name = 'DefaultPath'; Source = { Get-PCUDefaultCandidate } }
    )
    foreach ($method in $methods) {
        $candidates = @()
        try { $candidates = @(& $method.Source) } catch { Write-Verbose "Discovery via $($method.Name) failed: $($_.Exception.Message)" }
        foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
            $root = Resolve-PCUInstallRoot -Path $candidate
            if ($root) {
                $root | Add-Member -NotePropertyName DiscoveryMethod -NotePropertyValue $method.Name -PassThru
                return
            }
        }
    }
}
