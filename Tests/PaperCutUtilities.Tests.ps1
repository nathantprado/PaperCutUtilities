BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../PaperCutUtilities/PaperCutUtilities.psd1'
    Import-Module $script:ModulePath -Force

    function New-FakeInstall {
        param([string]$Properties = "database.type=Internal`nserver.port=9191")
        $root = Join-Path ([IO.Path]::GetTempPath()) ("pcu-" + [guid]::NewGuid())
        $win = Join-Path $root 'server/bin/win'
        New-Item -ItemType Directory -Path $win -Force | Out-Null
        Set-Content -Path (Join-Path $win 'server-command.exe') -Value 'x'
        Set-Content -Path (Join-Path $root 'server/server.properties') -Value $Properties
        $root
    }
}

AfterAll { Remove-Module PaperCutUtilities -ErrorAction SilentlyContinue }

Describe 'Module' {
    It 'exports the expected functions' {
        $names = (Get-Command -Module PaperCutUtilities).Name
        foreach ($n in 'Get-PCUInstallPath', 'Get-PCUApiKey', 'Invoke-PCUServerCommand', 'Get-PCUConfiguration', 'Get-PCUServer',
            'Test-PCUConnectivity', 'Test-PCUDatabase', 'Get-PCUHealth', 'Clear-PCUCache', 'Get-PCUCache') {
            $names | Should -Contain $n
        }
    }
    It 'has comment-based help for every public function' {
        foreach ($c in Get-Command -Module PaperCutUtilities) { (Get-Help $c.Name).Synopsis | Should -Not -BeNullOrEmpty }
    }
}

Describe 'Get-PCUInstallPath' {
    BeforeEach { Clear-PCUCache }
    It 'prefers process over service and reports the method' {
        $root = New-FakeInstall
        InModuleScope PaperCutUtilities -Parameters @{ Root = $root } {
            param($Root)
            Mock Get-PCUProcessCandidate { Join-Path $Root 'server/bin/win/pc-server.exe' }
            Mock Get-PCUServiceCandidate { 'C:\nope\x.exe' }
            Mock Get-PCURegistryCandidate { @() }
            Mock Get-PCUDefaultCandidate { @() }
            $r = Get-PCUInstallPath
            $r.InstallPath | Should -Be $Root
            $r.DiscoveryMethod | Should -Be 'Process'
            $r.ServerCommandPath | Should -BeLike '*server-command.exe'
        }
    }
    It 'falls through to service, then registry, then default' {
        $root = New-FakeInstall
        InModuleScope PaperCutUtilities -Parameters @{ Root = $root } {
            param($Root)
            Mock Get-PCUProcessCandidate { @() }
            Mock Get-PCUServiceCandidate { @() }
            Mock Get-PCURegistryCandidate { @() }
            Mock Get-PCUDefaultCandidate { $Root }
            (Get-PCUInstallPath).DiscoveryMethod | Should -Be 'DefaultPath'
            Clear-PCUCache
            Mock Get-PCURegistryCandidate { $Root }
            (Get-PCUInstallPath).DiscoveryMethod | Should -Be 'Registry'
            Clear-PCUCache
            Mock Get-PCUServiceCandidate { $Root }
            (Get-PCUInstallPath).DiscoveryMethod | Should -Be 'Service'
        }
    }
    It 'errors when nothing valid is found' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCUProcessCandidate { @() }
            Mock Get-PCUServiceCandidate { @() }
            Mock Get-PCURegistryCandidate { @() }
            Mock Get-PCUDefaultCandidate { Join-Path ([IO.Path]::GetTempPath()) 'does-not-exist' }
            { Get-PCUInstallPath -ErrorAction Stop } | Should -Throw '*not found*'
        }
    }
    It 'caches and honours -Refresh' {
        $root = New-FakeInstall
        InModuleScope PaperCutUtilities -Parameters @{ Root = $root } {
            param($Root)
            Mock Get-PCUProcessCandidate { $Root }
            Mock Get-PCUServiceCandidate { @() }
            Mock Get-PCURegistryCandidate { @() }
            Mock Get-PCUDefaultCandidate { @() }
            Get-PCUInstallPath | Out-Null
            Get-PCUInstallPath | Out-Null
            Should -Invoke Get-PCUProcessCandidate -Times 1 -Exactly
            Get-PCUInstallPath -Refresh | Out-Null
            Should -Invoke Get-PCUProcessCandidate -Times 2 -Exactly
        }
    }
}

Describe 'Cache' {
    It 'Clear-PCUCache and Get-PCUCache work' {
        InModuleScope PaperCutUtilities {
            Clear-PCUCache
            Set-PCUCacheEntry -Key 'Foo|local' -Value 1 | Out-Null
            Set-PCUCacheEntry -Key 'ApiKey:Health|local' -Value 'secret' | Out-Null
            @(Get-PCUCache).Count | Should -Be 2
            (Get-PCUCache -Name 'ApiKey:*').Value | Should -Be '********'
            Clear-PCUCache -Name 'Foo'
            @(Get-PCUCache).Count | Should -Be 1
            Clear-PCUCache
            @(Get-PCUCache).Count | Should -Be 0
        }
    }
}

Describe 'Invoke-PCUServerCommand / completer / ApiKey' {
    BeforeEach { Clear-PCUCache }
    It 'parses commands from help output' {
        InModuleScope PaperCutUtilities {
            $help = 'Usage: server-command <command>', 'Commands:', '  add-new-user  Adds', '  get-config <key>', '  list-user-accounts', 'Not a command line'
            ConvertFrom-PCUServerCommandHelp -HelpText $help | Should -Be @('add-new-user', 'get-config', 'list-user-accounts')
        }
    }
    It 'builds and caches the command list' {
        InModuleScope PaperCutUtilities {
            Mock Invoke-PCUServerCommand { [pscustomobject]@{ Output = @('  get-config', '  add-new-user') } }
            Get-PCUServerCommandList | Should -Contain 'get-config'
            Get-PCUServerCommandList | Out-Null
            Should -Invoke Invoke-PCUServerCommand -Times 1 -Exactly
        }
    }
    It 'returns Health API key as SecureString by default and plain text on request' {
        InModuleScope PaperCutUtilities {
            Mock Invoke-PCUServerCommand { [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @('', 'abc123') } }
            Get-PCUApiKey -Type Health | Should -BeOfType [securestring]
            Get-PCUApiKey -Type Health -AsPlainText | Should -Be 'abc123'
            Should -Invoke Invoke-PCUServerCommand -Times 1 -Exactly -ParameterFilter { $Arguments -eq 'health.api.key' }
        }
    }
    It 'uses the XmlRpc config key' {
        InModuleScope PaperCutUtilities {
            Mock Invoke-PCUServerCommand { [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @('tok') } }
            Get-PCUApiKey -Type XmlRpc -AsPlainText | Should -Be 'tok'
            Should -Invoke Invoke-PCUServerCommand -ParameterFilter { $Arguments -eq 'auth.webservices.auth-token' }
        }
    }
    It 'throws when the key is empty' {
        InModuleScope PaperCutUtilities {
            Mock Invoke-PCUServerCommand { [pscustomobject]@{ Success = $true; ExitCode = 0; Output = @('') } }
            { Get-PCUApiKey -Type Health } | Should -Throw '*empty*'
        }
    }
    It 'invokes server-command and returns exit code' -Skip:(-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        InModuleScope PaperCutUtilities {
            Mock Get-PCUInstallPath { [pscustomobject]@{ ServerCommandPath = (Get-Command cmd.exe).Source; InstallPath = 'x' } }
            (Invoke-PCUServerCommand -Command '/c' -Arguments 'echo hi').Output | Should -Contain 'hi'
        }
    }
}

Describe 'Get-PCUConfiguration' {
    BeforeEach { Clear-PCUCache }
    It 'detects database, HA and ports, masking secrets' {
        $props = "database.type=SQLServer`ndatabase.url=jdbc:sqlserver://db1:1433;databaseName=pc`ndatabase.password=hunter2`nserver.port=9191`nserver.ssl-port=9999`nha.enabled=true`n# comment"
        $root = New-FakeInstall -Properties $props
        Set-Content (Join-Path $root 'server/security.properties') 'admin.token=ZZZ'
        InModuleScope PaperCutUtilities -Parameters @{ Root = $root } {
            param($Root)
            Mock Get-PCUInstallPath { [pscustomobject]@{ ServerPath = (Join-Path $Root 'server') } }
            $c = Get-PCUConfiguration
            $c.DatabaseType | Should -Be 'SQLServer'
            $c.HighAvailability | Should -BeTrue
            ($c.Ports | Where-Object Port -eq 9999).Key | Should -Be 'server.ssl-port'
            ($c.Entries | Where-Object Key -eq 'database.password').Value | Should -Be '********'
            ($c.Entries | Where-Object Key -eq 'admin.token').Value | Should -Be '********'
            (Get-PCUConfiguration -IncludeSecrets).Entries | Where-Object Key -eq 'database.password' | ForEach-Object Value | Should -Be 'hunter2'
        }
    }
    It 'defaults to Derby with no db settings' {
        $root = New-FakeInstall
        InModuleScope PaperCutUtilities -Parameters @{ Root = $root } {
            param($Root)
            Mock Get-PCUInstallPath { [pscustomobject]@{ ServerPath = (Join-Path $Root 'server') } }
            (Get-PCUConfiguration).DatabaseType | Should -Be 'Derby'
            (Get-PCUConfiguration).HighAvailability | Should -BeFalse
        }
    }
}

Describe 'Get-PCUServer' {
    BeforeEach { Clear-PCUCache }
    It 'merges service, config and specified servers with roles' {
        InModuleScope PaperCutUtilities {
            Mock Invoke-PCURemote { @([pscustomobject]@{ Name = 'PaperCut Print Deploy'; DisplayName = 'PaperCut Print Deploy'; State = 'Running'; PathName = 'x' }) }
            Mock Get-PCURawConfiguration { @([pscustomobject]@{ File = 'f'; Key = 'site-server.host'; Value = 'site01:9191' }, [pscustomobject]@{ File = 'f'; Key = 'secondary.url'; Value = 'http://sec01:9191/' }) }
            Mock Resolve-PCUHostInfo { [pscustomobject]@{ HostName = $Name; IPAddress = @('10.0.0.1') } }
            $s = Get-PCUServer -ComputerName app01 -AdditionalServer @{ 'mp01' = 'MobilityPrint' }
            ($s | Where-Object HostName -eq 'app01').Roles | Should -Contain 'PrintDeploy'
            ($s | Where-Object HostName -eq 'app01').Roles | Should -Contain 'Application'
            ($s | Where-Object HostName -eq 'site01').Roles | Should -Be @('Site')
            ($s | Where-Object HostName -eq 'sec01').Roles | Should -Be @('Secondary')
            ($s | Where-Object HostName -eq 'mp01').IPAddress | Should -Be '10.0.0.1'
        }
    }
}

Describe 'Test-PCUConnectivity' {
    BeforeEach { Clear-PCUCache }
    It 'tests default and configured ports per server' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCUServer { @([pscustomobject]@{ HostName = 'app01'; IPAddress = @('1.1.1.1'); Roles = @('Application') },
                    [pscustomobject]@{ HostName = 'mp01'; IPAddress = @('2.2.2.2'); Roles = @('MobilityPrint') }) }
            Mock Get-PCUConfiguration { [pscustomobject]@{ Ports = @([pscustomobject]@{ Key = 'server.port'; Port = 9191 }, [pscustomobject]@{ Key = 'x.port'; Port = 9500 }, [pscustomobject]@{ Key = 'database.port'; Port = 1433 }) } }
            Mock Test-PCUTcpPort { [pscustomobject]@{ Open = ($Port -ne 9192); ResponseMs = 1; Error = $null } }
            $r = @(Test-PCUConnectivity)
            ($r | Where-Object { $_.Server -eq 'app01' }).Port | Should -Be @(9191, 9192, 9500)
            ($r | Where-Object { $_.Server -eq 'app01' -and $_.Port -eq 9500 }).PortSource | Should -Be 'Configured'
            ($r | Where-Object { $_.Server -eq 'mp01' }).Port | Should -Be @(9163, 9164)
            ($r | Where-Object { $_.Port -eq 9192 }).Open | Should -Not -Contain $true
        }
    }
}

Describe 'Test-PCUDatabase' {
    BeforeEach { Clear-PCUCache }
    It 'parses JDBC URLs' {
        InModuleScope PaperCutUtilities {
            (ConvertFrom-PCUJdbcUrl 'jdbc:sqlserver://h1;databaseName=pc').Port | Should -Be 1433
            (ConvertFrom-PCUJdbcUrl 'jdbc:postgresql://h2:5433/papercut').Database | Should -Be 'papercut'
            $o = ConvertFrom-PCUJdbcUrl 'jdbc:oracle:thin:@//h3:1522/ORCL'
            $o.Host | Should -Be 'h3'; $o.Port | Should -Be 1522; $o.Database | Should -Be 'ORCL'
            (ConvertFrom-PCUJdbcUrl 'jdbc:oracle:thin:@h4:1521:SID').Database | Should -Be 'SID'
        }
    }
    It 'reports Derby as not testable' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCURawConfiguration { @([pscustomobject]@{ Key = 'database.type'; Value = 'Internal' }) }
            (Test-PCUDatabase).Status | Should -Be 'NotTestable'
        }
    }
    It 'is unhealthy when the port is closed' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCURawConfiguration { @([pscustomobject]@{ Key = 'database.type'; Value = 'PostgreSQL' }, [pscustomobject]@{ Key = 'database.url'; Value = 'jdbc:postgresql://pg:5432/pc' }) }
            Mock Test-PCUTcpPort { [pscustomobject]@{ Open = $false; ResponseMs = $null; Error = 'refused' } }
            $r = Test-PCUDatabase
            $r.DatabaseType | Should -Be 'PostgreSQL'
            $r.Status | Should -Be 'Unhealthy'
        }
    }
    It 'attempts login when credentials are plain and skips encrypted ones' {
        InModuleScope PaperCutUtilities {
            Mock Test-PCUTcpPort { [pscustomobject]@{ Open = $true; ResponseMs = 1; Error = $null } }
            Mock Invoke-PCUDatabaseLogin { [pscustomobject]@{ Success = $true; Message = 'ok'; Skipped = $false } }
            $base = @([pscustomobject]@{ Key = 'database.type'; Value = 'SQLServer' }, [pscustomobject]@{ Key = 'database.url'; Value = 'jdbc:sqlserver://sql:1433;databaseName=pc' }, [pscustomobject]@{ Key = 'database.username'; Value = 'u' })
            Mock Get-PCURawConfiguration { $base + [pscustomobject]@{ Key = 'database.password'; Value = 'p' } }
            $r = Test-PCUDatabase
            $r.LoginSucceeded | Should -BeTrue
            Mock Get-PCURawConfiguration { $base + [pscustomobject]@{ Key = 'database.password'; Value = 'ENC(abc)' } }
            (Test-PCUDatabase).LoginTested | Should -BeFalse
        }
    }
}

Describe 'Get-PCUHealth' {
    BeforeEach { Clear-PCUCache }
    It 'rolls up check statuses' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCUInstallPath { [pscustomobject]@{ InstallPath = 'C:\x'; DiscoveryMethod = 'Service' } }
            Mock Invoke-PCURemote { @([pscustomobject]@{ Name = 's'; State = 'Running' }) }
            Mock Test-PCUDatabase { [pscustomobject]@{ Status = 'Healthy'; DatabaseType = 'SQLServer'; Message = 'ok' } }
            Mock Test-PCUConnectivity { [pscustomobject]@{ Server = 'a'; Port = 9191; Open = $true }, [pscustomobject]@{ Server = 'a'; Port = 9192; Open = $false } }
            $h = Get-PCUHealth -SkipHealthApi
            $h.Status | Should -Be 'Degraded'
            ($h.Checks | Where-Object Name -eq 'HealthApi').Status | Should -Be 'Skipped'
        }
    }
    It 'is unhealthy when install is missing' {
        InModuleScope PaperCutUtilities {
            Mock Get-PCUInstallPath { throw 'not found' }
            (Get-PCUHealth).Status | Should -Be 'Unhealthy'
        }
    }
}
