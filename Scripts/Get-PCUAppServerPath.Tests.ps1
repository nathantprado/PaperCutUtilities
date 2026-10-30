BeforeAll {
    . (Join-Path $PSScriptRoot 'Get-PCUAppServerPath.ps1')
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($ClassName, $Filter) }
    }
}

Describe 'ConvertTo-PCUAppServerRoot' {
    It 'parses a quoted path with arguments' {
        ConvertTo-PCUAppServerRoot '"C:\Program Files\PaperCut MF\server\bin\win\pc-server.exe" -service' |
            Should -Be 'C:\Program Files\PaperCut MF'
    }
    It 'parses an unquoted path with arguments' {
        ConvertTo-PCUAppServerRoot 'D:\PaperCut MF\server\bin\win\pc-server.exe -service' |
            Should -Be 'D:\PaperCut MF'
    }
    It 'parses a bare exe path on a non-default drive' {
        ConvertTo-PCUAppServerRoot 'E:\PaperCut MF\server\bin\win\pc-server.exe' | Should -Be 'E:\PaperCut MF'
    }
    It 'returns null for empty or unrelated input' {
        ConvertTo-PCUAppServerRoot '' | Should -BeNullOrEmpty
        ConvertTo-PCUAppServerRoot 'C:\Other\app.exe' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PCUAppServerPath' {
    BeforeEach {
        Mock Get-Process { }
        Mock Get-CimInstance { throw 'cim down' }
        Mock Get-ItemProperty { throw 'no key' }
        Mock Test-Path { $LiteralPath -like '*\server' }
    }

    It 'uses the running process first' {
        Mock Get-Process { [pscustomobject]@{ Path = 'D:\PaperCut MF\server\bin\win\pc-server.exe' } }
        Get-PCUAppServerPath | Should -Be 'D:\PaperCut MF'
        Should -Invoke Get-CimInstance -Times 0
    }
    It 'falls back to the CIM service when the process is stopped' {
        Mock Get-Process { throw 'not running' }
        Mock Get-CimInstance { [pscustomobject]@{ PathName = '"E:\PaperCut MF\server\bin\win\pc-server.exe" -service' } }
        Get-PCUAppServerPath | Should -Be 'E:\PaperCut MF'
    }
    It 'falls back to the registry when CIM fails' {
        Mock Get-ItemProperty { [pscustomobject]@{ ImagePath = '"D:\PaperCut MF\server\bin\win\pc-server.exe" -service' } }
        Get-PCUAppServerPath | Should -Be 'D:\PaperCut MF'
    }
    It 'ignores stale entries whose server folder is missing' {
        Mock Get-ItemProperty { [pscustomobject]@{ ImagePath = '"D:\Old\server\bin\win\pc-server.exe"' } }
        Mock Test-Path { $false }
        Get-PCUAppServerPath -WarningAction SilentlyContinue | Should -BeNullOrEmpty
    }
    It 'warns and returns null when nothing is found' {
        Mock Test-Path { $false }
        $result = Get-PCUAppServerPath -WarningVariable w -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $w | Should -Not -BeNullOrEmpty
    }
}
