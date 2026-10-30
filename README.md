# PaperCutUtilities

PowerShell 5.1+ module (`PCU` prefix) for discovering, inspecting and health-checking a PaperCut MF/NG deployment. Local-first; most functions accept `-ComputerName` (PowerShell remoting) and `-Credential`.

```powershell
Import-Module ./PaperCutUtilities/PaperCutUtilities.psd1
Get-PCUInstallPath            # how/where PaperCut was found
Get-PCUConfiguration          # DB type, HA, ports; secrets masked
Get-PCUServer                 # servers + roles + IPs
Test-PCUConnectivity          # default + configured ports per server
Test-PCUDatabase              # SQL Server / PostgreSQL / Oracle / Derby detection
Get-PCUHealth                 # rolled-up health
```

## Functions

| Function | Purpose |
|---|---|
| `Get-PCUInstallPath` | Finds the app server: running processes → services (ImagePath) → registry → default paths. Validates `server-command.exe` / `server.properties`; reports `DiscoveryMethod`. |
| `Invoke-PCUServerCommand` | Wraps `server-command.exe`; `-Command` tab-completes from `server-command.exe help`. |
| `Get-PCUApiKey -Type Health\|XmlRpc` | Fetches an API key via `server-command get-config` (SecureString by default; cached in memory only). |
| `Get-PCUConfiguration` | Parses `server.properties`, `security.properties`, `*.conf` (e.g. service.conf) etc. Secrets masked unless `-IncludeSecrets`. |
| `Get-PCUServer` | Application, Secondary, Site, Print Deploy, Mobility Print and Document Processing servers (services, config references, `-AdditionalServer`). Caches hostname/IP/roles. |
| `Test-PCUConnectivity` | TCP checks on default ports (9191/9192, …) plus custom ports from configuration. |
| `Test-PCUDatabase` | Detects DB type from `server.properties` and tests TCP + login via .NET (SqlClient; ODBC for PostgreSQL/Oracle/MySQL when a driver exists). Derby is reported as not remotely testable; `ENC(...)` passwords need `-DatabaseCredential`. |
| `Get-PCUHealth` | Install, services, database, connectivity and the `/api/health` endpoint rolled into Healthy/Degraded/Unhealthy. |
| `Get-PCUCache` / `Clear-PCUCache` | Inspect / clear the in-memory cache (`$script:PCUCache`). Use `-Refresh` on any function to bypass it. |

## Notes and assumptions

- Configuration key names (`health.api.key`, `auth.webservices.auth-token`, `database.url`, ...) and role-specific default ports (e.g. Mobility Print 9163/9164) follow PaperCut conventions but should be verified against your version; adjust `Private/Ports.ps1` and `Private/Network.ps1` as needed.
- Server discovery for Site/Secondary/etc. is heuristic (services + config references); pass `-AdditionalServer @{ host = 'Site' }` for anything it cannot see.
- Secrets are never written to disk; cached API keys are held in memory and hidden by `Get-PCUCache`.

## Development

```powershell
Invoke-Pester ./Tests -Output Detailed
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Tests mock all PaperCut/Windows dependencies, so they run on machines without PaperCut. CI runs PSScriptAnalyzer and Pester on Windows PowerShell 5.1 and PowerShell 7.
