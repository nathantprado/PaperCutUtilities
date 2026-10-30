function ConvertTo-PCUAppServerRoot {
    <#
    .SYNOPSIS
    Extracts the PaperCut MF root directory from an executable path or service command line.

    .DESCRIPTION
    Handles quoted paths and trailing arguments (e.g. "C:\Program Files\PaperCut MF\server\bin\win\pc-server.exe" -service)
    and returns the directory that contains the \server folder, or $null if the input cannot be parsed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Path
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

        $exe = $null
        if ($Path -match '^\s*"([^"]+)"') {
            $exe = $Matches[1]
        }
        elseif ($Path -match '^\s*(.+?\.exe)(?:\s|$)') {
            $exe = $Matches[1]
        }
        else {
            $exe = $Path.Trim()
        }

        if ($exe -match '^(.*?)[\\/]server(?:[\\/].*)?$') {
            return $Matches[1]
        }
        return $null
    }
}

function Get-PCUAppServerPath {
    <#
    .SYNOPSIS
    Resolves the root installation directory of the PaperCut MF application server.

    .DESCRIPTION
    Checks, in order: the running pc-server process, the PCAppServer service (CIM),
    the PCAppServer service registry key, and known default install locations.
    The first candidate that contains a \server directory is returned. If none is
    found, a warning is written and $null is returned.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $isValid = {
        param($root)
        $root -and (Test-Path -LiteralPath ("$($root.TrimEnd('\','/'))\server") -PathType Container)
    }

    # 1. Live process
    try {
        foreach ($proc in @(Get-Process -Name 'pc-server' -ErrorAction Stop)) {
            $root = ConvertTo-PCUAppServerRoot -Path $proc.Path
            if (& $isValid $root) { return $root }
        }
    }
    catch {
        Write-Verbose "Process lookup failed: $($_.Exception.Message)"
    }

    # 2. CIM service definition
    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='PCAppServer'" -ErrorAction Stop
        foreach ($s in @($svc)) {
            $root = ConvertTo-PCUAppServerRoot -Path $s.PathName
            if (& $isValid $root) { return $root }
        }
    }
    catch {
        Write-Verbose "CIM lookup failed: $($_.Exception.Message)"
    }

    # 3. Registry
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\PCAppServer' -Name 'ImagePath' -ErrorAction Stop
        $root = ConvertTo-PCUAppServerRoot -Path $reg.ImagePath
        if (& $isValid $root) { return $root }
    }
    catch {
        Write-Verbose "Registry lookup failed: $($_.Exception.Message)"
    }

    # 4. Known default paths
    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
        Where-Object { $_ } | Select-Object -Unique
    foreach ($base in $bases) {
        foreach ($name in 'PaperCut MF', 'PaperCut NG') {
            $root = Join-Path $base $name
            if (& $isValid $root) { return $root }
        }
    }

    Write-Warning 'Unable to resolve the PaperCut MF application server installation path.'
    return $null
}
