<#
.SYNOPSIS
    Veeam ONE Health Check & Troubleshooting Assistant.

.DESCRIPTION
    Performs modular read-only health, troubleshooting and upgrade readiness
    checks for Veeam ONE. The script is designed for Windows PowerShell 5.1
    and writes structured local reports only. It does not upload anything.

    Default behavior is a full health check. SQL checks use Windows
    authentication only.

.NOTES
    Unofficial helper tool. Review all output before sharing or acting on it.

    Example (run from the folder where this script was saved):
      cd <PATH_WHERE_SCRIPT_RESIDES>
      Unblock-File .\VeeamOnePreUpgradeReadiness.ps1
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      .\VeeamOnePreUpgradeReadiness.ps1
#>

[CmdletBinding()]
param(
    [ValidateSet('Upgrade', 'Health', 'Full')]
    [string]$Mode = 'Full',

    [string]$CurrentVersion = '{{CURRENT_VERSION}}',
    [string]$TargetVersion = '{{TARGET_VERSION}}',
    [string]$SqlServer = '{{SQL_SERVER}}',
    [string]$SqlInstance = '{{SQL_INSTANCE}}',
    [string]$DatabaseName = '{{DATABASE_NAME}}',
    [string]$SqlPort = '{{SQL_PORT}}',

    [switch]$CheckPorts,
    [string[]]$Target = @(),
    [int[]]$Port = @(),

    [switch]$AnalyzeLogs,
    [string]$LogPath = '',

    [switch]$ValidateSizing,
    [int]$VMCount = 0,
    [int]$HostCount = 0,
    [decimal]$RepositoryTB = 0,

    [string]$ExportJson = '',
    [string]$ExportHtml = '',
    [string]$ExportCsv = '',
    [string]$OutputPath = '.\VeeamOneHealthReport.json'
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

function Normalize-TemplateValue {
    param(
        [string]$Value,
        [string]$Default = ''
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    if ($Value -match '^\{\{.+\}\}$') { return $Default }
    return $Value.Trim()
}

function Normalize-IntValue {
    param(
        [string]$Value,
        [int]$Default
    )
    $parsed = 0
    $normalized = Normalize-TemplateValue -Value $Value
    if ([int]::TryParse($normalized, [ref]$parsed)) { return $parsed }
    return $Default
}

function Resolve-ScriptPath {
    param(
        [string]$Path,
        [string]$DefaultName = ''
    )
    $candidate = Normalize-TemplateValue -Value $Path
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        if ([string]::IsNullOrWhiteSpace($DefaultName)) { return '' }
        return (Join-Path -Path $ScriptRoot -ChildPath $DefaultName)
    }
    if ([System.IO.Path]::IsPathRooted($candidate)) {
        return $candidate
    }
    return (Join-Path -Path $ScriptRoot -ChildPath $candidate)
}

function Ensure-ParentDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

$CurrentVersion = Normalize-TemplateValue -Value $CurrentVersion
$TargetVersion = Normalize-TemplateValue -Value $TargetVersion
$SqlServer = Normalize-TemplateValue -Value $SqlServer
$SqlInstance = Normalize-TemplateValue -Value $SqlInstance
$DatabaseName = Normalize-TemplateValue -Value $DatabaseName -Default 'VeeamONE'
$SqlPort = Normalize-IntValue -Value $SqlPort -Default 1433
$LogPath = Resolve-ScriptPath -Path $LogPath
$OutputPath = Resolve-ScriptPath -Path $OutputPath -DefaultName 'VeeamOneHealthReport.json'
$ExportJson = Resolve-ScriptPath -Path $ExportJson -DefaultName (Split-Path -Leaf $OutputPath)
$ExportHtml = Resolve-ScriptPath -Path $ExportHtml
$ExportCsv = Resolve-ScriptPath -Path $ExportCsv

$script:Checks = New-Object System.Collections.ArrayList
$script:Recommendations = New-Object System.Collections.ArrayList
$script:ModuleData = [ordered]@{
    upgradeReadiness = $null
    services         = @()
    sql              = $null
    collections      = $null
    alarms           = $null
    ports            = @()
    logs             = @()
    sizing           = $null
    discoveredTargets = @()
}

$script:KnownIssueRules = @(
    @{
        name = 'SQL database full'
        regex = 'Could not allocate a new page|database full'
        severity = 'failed'
        cause = 'SQL Express or SQL storage capacity is exhausted.'
        recommendation = 'Move to SQL Standard or Enterprise, or free database capacity immediately.'
    },
    @{
        name = 'Named Pipes Provider error 40'
        regex = 'Named Pipes Provider,\s*error:\s*40'
        severity = 'failed'
        cause = 'SQL Server is unavailable, unreachable or the instance name is incorrect.'
        recommendation = 'Verify SQL service state, TCP/IP, firewall, DNS and the SQL instance name.'
    },
    @{
        name = 'SQL login failed'
        regex = 'Login failed'
        severity = 'warning'
        cause = 'The current account cannot authenticate to SQL Server.'
        recommendation = 'Verify the Veeam ONE service account and SQL permissions.'
    },
    @{
        name = 'SQL timeout expired'
        regex = 'Timeout expired'
        severity = 'warning'
        cause = 'SQL queries are timing out due to load, latency or blocking.'
        recommendation = 'Check SQL load, waits, blocking and network latency.'
    },
    @{
        name = 'Collector task failed'
        regex = 'Collector task failed|collector.+failed'
        severity = 'warning'
        cause = 'A Veeam ONE collection task is failing.'
        recommendation = 'Review collector task health, service status and SQL availability.'
    },
    @{
        name = 'Object properties failure'
        regex = 'Object Properties'
        severity = 'warning'
        cause = 'Object properties collection is failing or incomplete.'
        recommendation = 'Review object properties collectors and dependent infrastructure.'
    },
    @{
        name = 'Potential malware activity detected'
        regex = 'Potential malware activity detected'
        severity = 'failed'
        cause = 'Veeam Backup & Replication surfaced a malware detection event.'
        recommendation = 'Review the VBR malware detection report and investigate the affected VM or restore point.'
    },
    @{
        name = 'Certificate or TLS issue'
        regex = 'TLS|SSL|certificate'
        severity = 'warning'
        cause = 'Certificate validation or TLS negotiation is failing.'
        recommendation = 'Verify certificates, trust chain and TLS protocol configuration.'
    },
    @{
        name = 'Access denied'
        regex = 'Access is denied|access denied'
        severity = 'warning'
        cause = 'The current account lacks required permissions.'
        recommendation = 'Review local, service and SQL permissions for the Veeam ONE account.'
    },
    @{
        name = 'Service crash'
        regex = 'Unhandled exception|service terminated unexpectedly|crash'
        severity = 'failed'
        cause = 'A Veeam ONE service appears unstable or is crashing.'
        recommendation = 'Inspect Windows event logs, service dependencies and recent configuration changes.'
    }
)

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkCyan
}

function Write-StatusLine {
    param(
        [string]$Status,
        [string]$Category,
        [string]$Name,
        [string]$Message
    )
    $label = switch ($Status) {
        'passed' { 'PASS'; break }
        'warning' { 'WARNING'; break }
        'failed' { 'FAIL'; break }
        default { 'INFO' }
    }
    $color = switch ($Status) {
        'passed' { 'Green'; break }
        'warning' { 'Yellow'; break }
        'failed' { 'Red'; break }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1} :: {2} - {3}" -f $label, $Category, $Name, $Message) -ForegroundColor $color
}

function Add-Recommendation {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if (-not ($script:Recommendations -contains $Text)) {
        [void]$script:Recommendations.Add($Text)
    }
}

function Add-Check {
    param(
        [string]$Id,
        [string]$Category,
        [string]$Name,
        [string]$Status,
        [string]$Severity,
        [string]$Evidence,
        [string]$Recommendation = ''
    )
    $entry = [ordered]@{
        id             = $Id
        category       = $Category
        name           = $Name
        status         = $Status
        severity       = $Severity
        evidence       = $Evidence
        recommendation = $Recommendation
    }
    [void]$script:Checks.Add($entry)
    Add-Recommendation -Text $Recommendation
    Write-StatusLine -Status $Status -Category $Category -Name $Name -Message $Evidence
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-VeeamOneVersion {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $paths) {
        try {
            $app = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like 'Veeam ONE*' } |
                Select-Object -First 1
            if ($app) {
                return [ordered]@{
                    displayName = [string]$app.DisplayName
                    version     = [string]$app.DisplayVersion
                }
            }
        } catch {}
    }
    return $null
}

function Get-DotNetVersion {
    try {
        $release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release
        if ($release -ge 533320) {
            $name = '4.8.1 or later'
        } elseif ($release -ge 528040) {
            $name = '4.8'
        } elseif ($release -ge 461808) {
            $name = '4.7.2'
        } elseif ($release -ge 460798) {
            $name = '4.7'
        } else {
            $name = 'Earlier than 4.7'
        }
        return [ordered]@{
            release = $release
            version = $name
        }
    } catch {
        return $null
    }
}

function Resolve-SqlDataSource {
    if ([string]::IsNullOrWhiteSpace($SqlServer)) { return '' }
    if (-not [string]::IsNullOrWhiteSpace($SqlInstance)) {
        return "$SqlServer\$SqlInstance"
    }
    return "$SqlServer,$SqlPort"
}

function New-SqlConnectionString {
    param([string]$Database = 'master')
    $dataSource = Resolve-SqlDataSource
    return "Server=$dataSource;Database=$Database;Integrated Security=SSPI;Encrypt=False;TrustServerCertificate=True;Connect Timeout=8;Application Name=VeeamOneHealthAssistant;"
}

function Invoke-SqlScalarSafe {
    param(
        [string]$Query,
        [string]$Database = 'master'
    )
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection (New-SqlConnectionString -Database $Database)
        $cn.Open()
        try {
            $cmd = $cn.CreateCommand()
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = 15
            $value = $cmd.ExecuteScalar()
            return @{ ok = $true; value = $value }
        } finally {
            $cn.Close()
        }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Invoke-SqlRowsSafe {
    param(
        [string]$Query,
        [string]$Database = $DatabaseName
    )
    try {
        $cn = New-Object System.Data.SqlClient.SqlConnection (New-SqlConnectionString -Database $Database)
        $cn.Open()
        try {
            $cmd = $cn.CreateCommand()
            $cmd.CommandText = $Query
            $cmd.CommandTimeout = 20
            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
            $table = New-Object System.Data.DataTable
            [void]$adapter.Fill($table)
            return @{ ok = $true; rows = @($table.Rows) }
        } finally {
            $cn.Close()
        }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}

function Test-SqlUnsupportedMessage {
    param([string]$Message)
    return ($Message -match 'Invalid object name' -or
        $Message -match 'Invalid column name' -or
        $Message -match 'could not be bound' -or
        $Message -match 'There is already an object named' -or
        $Message -match 'Could not find stored procedure')
}

function Invoke-SqlVariantQuery {
    param(
        [array]$Variants,
        [string]$Database = $DatabaseName
    )
    foreach ($variant in $Variants) {
        $result = Invoke-SqlRowsSafe -Query $variant.query -Database $Database
        if ($result.ok) {
            return @{ ok = $true; source = $variant.name; rows = $result.rows }
        }
        if (-not (Test-SqlUnsupportedMessage -Message $result.error)) {
            return @{ ok = $false; source = $variant.name; error = $result.error }
        }
    }
    return @{ ok = $false; unsupported = $true; error = 'Check not supported on this version.' }
}

function Get-DataRowValue {
    param(
        [object]$Row,
        [string]$Column
    )
    try {
        if ($Row.Table.Columns.Contains($Column)) {
            return $Row[$Column]
        }
    } catch {}
    return $null
}

function Test-PortConnectivity {
    param(
        [string]$ComputerName,
        [int]$PortNumber
    )
    if ([string]::IsNullOrWhiteSpace($ComputerName) -or $PortNumber -le 0) {
        return [ordered]@{
            target = $ComputerName
            port = $PortNumber
            reachable = $false
            latencyMs = $null
            source = 'invalid-input'
            detail = 'Target or port is missing.'
        }
    }

    $tnc = Get-Command Test-NetConnection -ErrorAction SilentlyContinue
    if ($tnc) {
        try {
            $res = Test-NetConnection -ComputerName $ComputerName -Port $PortNumber -WarningAction SilentlyContinue
            return [ordered]@{
                target = $ComputerName
                port = $PortNumber
                reachable = [bool]$res.TcpTestSucceeded
                latencyMs = $null
                source = 'Test-NetConnection'
                detail = $(
                    if ($res.TcpTestSucceeded) { 'Reachable.' } else { 'TCP test failed.' }
                )
            }
        } catch {}
    }

    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $iar = $client.BeginConnect($ComputerName, $PortNumber, $null, $null)
        $connected = $iar.AsyncWaitHandle.WaitOne(5000, $false)
        if ($connected -and $client.Connected) {
            $client.EndConnect($iar)
            $sw.Stop()
            return [ordered]@{
                target = $ComputerName
                port = $PortNumber
                reachable = $true
                latencyMs = $sw.ElapsedMilliseconds
                source = 'TcpClient'
                detail = 'Reachable.'
            }
        }
        return [ordered]@{
            target = $ComputerName
            port = $PortNumber
            reachable = $false
            latencyMs = $null
            source = 'TcpClient'
            detail = 'Connection timed out.'
        }
    } catch {
        return [ordered]@{
            target = $ComputerName
            port = $PortNumber
            reachable = $false
            latencyMs = $null
            source = 'TcpClient'
            detail = $_.Exception.Message
        }
    } finally {
        if ($client) { $client.Close() }
    }
}

function Get-VeeamServiceHealth {
    $definitions = @(
        @{ id = 'veeam-one-monitoring'; name = 'Veeam ONE Monitoring Service' },
        @{ id = 'veeam-one-reporting'; name = 'Veeam ONE Reporting Service' },
        @{ id = 'veeam-one-agent'; name = 'Veeam ONE Agent' },
        @{ id = 'veeam-one-error-reporting'; name = 'Veeam ONE Error Reporting Service' }
    )

    $results = @()
    foreach ($definition in $definitions) {
        $svc = $null
        try {
            $svc = Get-CimInstance Win32_Service -ErrorAction Stop |
                Where-Object { $_.DisplayName -eq $definition.name } |
                Select-Object -First 1
        } catch {}

        if (-not $svc) {
            $entry = [ordered]@{
                id = $definition.id
                displayName = $definition.name
                exists = $false
                status = 'Missing'
                startupType = ''
                processId = $null
                lastStartTime = $null
                account = ''
                recommendation = 'If this is the Veeam ONE server, verify the product installation and services.'
            }
            Add-Check -Id $definition.id -Category 'Veeam Services Health' -Name $definition.name -Status 'warning' -Severity 'high' -Evidence 'Service is missing on this host.' -Recommendation $entry.recommendation
            $results += $entry
            continue
        }

        $startTime = $null
        if ($svc.ProcessId -and $svc.ProcessId -gt 0) {
            try {
                $proc = Get-Process -Id $svc.ProcessId -ErrorAction Stop
                $startTime = $proc.StartTime.ToString('s')
            } catch {
                $startTime = $null
            }
        }

        $recommendation = ''
        $status = 'passed'
        $severity = 'medium'
        if ($svc.State -ne 'Running') {
            $status = 'warning'
            $recommendation = 'Start the service and review dependent components before relying on Veeam ONE data.'
        }
        if ($svc.StartMode -eq 'Disabled') {
            $status = 'failed'
            $severity = 'high'
            $recommendation = 'Enable the service startup type unless this role is intentionally disabled.'
        }

        $entry = [ordered]@{
            id = $definition.id
            displayName = $definition.name
            exists = $true
            status = [string]$svc.State
            startupType = [string]$svc.StartMode
            processId = $null
            lastStartTime = $startTime
            account = [string]$svc.StartName
            recommendation = $recommendation
        }
        if ($svc.ProcessId -gt 0) {
            $entry.processId = [int]$svc.ProcessId
        }
        $evidence = "Status=$($entry.status); StartupType=$($entry.startupType)"
        if ($entry.processId) { $evidence += "; PID=$($entry.processId)" }
        if ($entry.lastStartTime) { $evidence += "; LastStart=$($entry.lastStartTime)" }
        if ($entry.account) { $evidence += "; Account=$($entry.account)" }
        Add-Check -Id $definition.id -Category 'Veeam Services Health' -Name $definition.name -Status $status -Severity $severity -Evidence $evidence -Recommendation $recommendation
        $results += $entry
    }
    return $results
}

function Get-SqlDatabaseHealth {
    $dataSource = Resolve-SqlDataSource
    $summary = [ordered]@{
        configured = -not [string]::IsNullOrWhiteSpace($SqlServer)
        dataSource = $dataSource
        databaseName = $DatabaseName
        dnsResolved = $false
        tcpConnected = $false
        connectionOk = $false
        currentLogin = ''
        version = ''
        edition = ''
        compatibilityLevel = $null
        recoveryModel = ''
        databaseSizeGb = $null
        logSizeGb = $null
        freeSpaceGb = $null
        expressRisk = $false
        growthWarning = $false
        warnings = @()
        errors = @()
    }

    if (-not $summary.configured) {
        Add-Check -Id 'sql-target-configured' -Category 'SQL / Database Health' -Name 'SQL Target Supplied' -Status 'warning' -Severity 'high' -Evidence 'No SQL Server was provided.' -Recommendation 'Provide -SqlServer and -DatabaseName to enable SQL diagnostics.'
        $summary.warnings += 'SQL target not provided.'
        return $summary
    }

    try {
        [void][System.Net.Dns]::GetHostAddresses($SqlServer)
        $summary.dnsResolved = $true
        Add-Check -Id 'sql-dns-resolution' -Category 'Upgrade Readiness' -Name 'SQL DNS Resolution' -Status 'passed' -Severity 'critical' -Evidence "$SqlServer resolves successfully." -Recommendation ''
    } catch {
        $summary.errors += $_.Exception.Message
        Add-Check -Id 'sql-dns-resolution' -Category 'Upgrade Readiness' -Name 'SQL DNS Resolution' -Status 'failed' -Severity 'critical' -Evidence "Could not resolve ${SqlServer}: $($_.Exception.Message)" -Recommendation 'Verify SQL hostname, DNS and the configured SQL instance.'
    }

    $portResult = Test-PortConnectivity -ComputerName $SqlServer -PortNumber $SqlPort
    $summary.tcpConnected = [bool]$portResult.reachable
    if ($summary.tcpConnected) {
        Add-Check -Id 'sql-port-connectivity' -Category 'Upgrade Readiness' -Name 'SQL Port Connectivity' -Status 'passed' -Severity 'critical' -Evidence "TCP $($SqlServer):$SqlPort is reachable." -Recommendation ''
    } else {
        Add-Check -Id 'sql-port-connectivity' -Category 'Upgrade Readiness' -Name 'SQL Port Connectivity' -Status 'failed' -Severity 'critical' -Evidence "TCP $($SqlServer):$SqlPort failed: $($portResult.detail)" -Recommendation 'Open the SQL port and verify firewalls, routing and SQL listener configuration.'
    }

    $connect = Invoke-SqlScalarSafe -Query 'SELECT 1' -Database 'master'
    if (-not $connect.ok) {
        $summary.errors += $connect.error
        Add-Check -Id 'sql-connection' -Category 'Upgrade Readiness' -Name 'SQL Connection' -Status 'failed' -Severity 'critical' -Evidence "SQL connection failed: $($connect.error)" -Recommendation 'Verify the SQL service, instance name, Windows authentication and SQL permissions.'
        Add-Check -Id 'database-existence' -Category 'Upgrade Readiness' -Name 'Database Availability' -Status 'skipped' -Severity 'critical' -Evidence 'Skipped because SQL connection failed.' -Recommendation ''
        return $summary
    }

    $summary.connectionOk = $true
    Add-Check -Id 'sql-connection' -Category 'Upgrade Readiness' -Name 'SQL Connection' -Status 'passed' -Severity 'critical' -Evidence "Connected to $dataSource with Windows authentication." -Recommendation ''

    $login = Invoke-SqlScalarSafe -Query 'SELECT SYSTEM_USER' -Database 'master'
    if ($login.ok) { $summary.currentLogin = [string]$login.value }

    $dbEsc = $DatabaseName -replace "'", "''"
    $dbExists = Invoke-SqlScalarSafe -Query "SELECT DB_ID(N'$dbEsc')" -Database 'master'
    if ($dbExists.ok -and $null -ne $dbExists.value -and $dbExists.value -isnot [System.DBNull]) {
        Add-Check -Id 'database-existence' -Category 'Upgrade Readiness' -Name 'Database Availability' -Status 'passed' -Severity 'critical' -Evidence "Database '$DatabaseName' exists." -Recommendation ''
    } else {
        if ($dbExists.ok) {
            $msg = "Database '$DatabaseName' was not found."
        } else {
            $msg = $dbExists.error
        }
        $summary.errors += $msg
        Add-Check -Id 'database-existence' -Category 'Upgrade Readiness' -Name 'Database Availability' -Status 'failed' -Severity 'critical' -Evidence $msg -Recommendation 'Verify the Veeam ONE database name and the SQL instance configuration.'
        return $summary
    }

    $version = Invoke-SqlScalarSafe -Query "SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(128)) + ' / ' + CAST(SERVERPROPERTY('ProductLevel') AS varchar(128))" -Database 'master'
    if ($version.ok) {
        $summary.version = [string]$version.value
        Add-Check -Id 'sql-version' -Category 'Upgrade Readiness' -Name 'SQL Version' -Status 'passed' -Severity 'medium' -Evidence "SQL Server $($summary.version)." -Recommendation ''
    } else {
        Add-Check -Id 'sql-version' -Category 'Upgrade Readiness' -Name 'SQL Version' -Status 'warning' -Severity 'medium' -Evidence "Could not read SQL version: $($version.error)" -Recommendation 'Confirm the SQL Server version manually.'
    }

    $edition = Invoke-SqlScalarSafe -Query "SELECT CAST(SERVERPROPERTY('Edition') AS varchar(128))" -Database 'master'
    if ($edition.ok) {
        $summary.edition = [string]$edition.value
        if ($summary.edition -match 'Express|Standard|Enterprise') {
            $editionStatus = 'passed'
            $editionRec = ''
        } else {
            $editionStatus = 'warning'
            $editionRec = 'Confirm that this SQL edition is supported for the intended Veeam ONE deployment.'
        }
        Add-Check -Id 'sql-edition' -Category 'Upgrade Readiness' -Name 'SQL Edition' -Status $editionStatus -Severity 'medium' -Evidence $summary.edition -Recommendation $editionRec
    } else {
        Add-Check -Id 'sql-edition' -Category 'Upgrade Readiness' -Name 'SQL Edition' -Status 'warning' -Severity 'medium' -Evidence "Could not read SQL edition: $($edition.error)" -Recommendation 'Confirm the SQL edition manually.'
    }

    $dbStats = Invoke-SqlRowsSafe -Database 'master' -Query @"
SELECT
    CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8.0 / 1024 / 1024 AS decimal(18,2)) AS DatabaseSizeGb,
    CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8.0 / 1024 / 1024 AS decimal(18,2)) AS LogSizeGb,
    CAST(SUM(CASE WHEN mf.type = 0 THEN FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 / 1024 AS decimal(18,2)) AS UsedDataGb,
    CAST(SUM(CASE WHEN mf.type = 1 THEN FILEPROPERTY(mf.name, 'SpaceUsed') END) * 8.0 / 1024 / 1024 AS decimal(18,2)) AS UsedLogGb
FROM sys.master_files mf
WHERE mf.database_id = DB_ID(N'$dbEsc');
"@
    if ($dbStats.ok -and $dbStats.rows.Count -gt 0) {
        $row = $dbStats.rows[0]
        $summary.databaseSizeGb = [double](Get-DataRowValue -Row $row -Column 'DatabaseSizeGb')
        $summary.logSizeGb = [double](Get-DataRowValue -Row $row -Column 'LogSizeGb')
        $usedData = [double](Get-DataRowValue -Row $row -Column 'UsedDataGb')
        if ($summary.databaseSizeGb -gt 0) {
            $summary.freeSpaceGb = [math]::Round(($summary.databaseSizeGb - $usedData), 2)
        }
        Add-Check -Id 'sql-database-size' -Category 'SQL / Database Health' -Name 'Database Size' -Status 'passed' -Severity 'medium' -Evidence ("Data={0} GB; Log={1} GB; FreeInsideFiles={2} GB" -f $summary.databaseSizeGb, $summary.logSizeGb, $summary.freeSpaceGb) -Recommendation ''
    } else {
        Add-Check -Id 'sql-database-size' -Category 'SQL / Database Health' -Name 'Database Size' -Status 'warning' -Severity 'medium' -Evidence "Could not read database file sizes: $($dbStats.error)" -Recommendation 'Verify database file growth, log size and free space manually.'
    }

    $dbOptions = Invoke-SqlRowsSafe -Database 'master' -Query "SELECT recovery_model_desc AS RecoveryModel, compatibility_level AS CompatibilityLevel FROM sys.databases WHERE name = N'$dbEsc';"
    if ($dbOptions.ok -and $dbOptions.rows.Count -gt 0) {
        $row = $dbOptions.rows[0]
        $summary.recoveryModel = [string](Get-DataRowValue -Row $row -Column 'RecoveryModel')
        $summary.compatibilityLevel = Get-DataRowValue -Row $row -Column 'CompatibilityLevel'
        Add-Check -Id 'sql-database-options' -Category 'SQL / Database Health' -Name 'Database Options' -Status 'passed' -Severity 'low' -Evidence "RecoveryModel=$($summary.recoveryModel); CompatibilityLevel=$($summary.compatibilityLevel)" -Recommendation ''
    } else {
        Add-Check -Id 'sql-database-options' -Category 'SQL / Database Health' -Name 'Database Options' -Status 'warning' -Severity 'low' -Evidence "Could not read database options: $($dbOptions.error)" -Recommendation 'Confirm the database recovery model and compatibility level manually.'
    }

    if ($summary.edition -match 'Express' -and $summary.databaseSizeGb -ge 8) {
        $summary.expressRisk = $true
        $summary.warnings += 'SQL Express database is approaching the 10 GB cap.'
        Add-Check -Id 'sql-express-risk' -Category 'SQL / Database Health' -Name 'SQL Express Capacity Risk' -Status 'warning' -Severity 'high' -Evidence "Database size is $($summary.databaseSizeGb) GB on SQL Express." -Recommendation 'Move to SQL Standard or Enterprise before reaching the SQL Express limit.'
    } else {
        Add-Check -Id 'sql-express-risk' -Category 'SQL / Database Health' -Name 'SQL Express Capacity Risk' -Status 'passed' -Severity 'medium' -Evidence 'No immediate SQL Express 10 GB risk detected.' -Recommendation ''
    }

    if ($summary.logSizeGb -ge 5) {
        $summary.warnings += 'Transaction log is unusually large.'
        Add-Check -Id 'sql-log-size' -Category 'SQL / Database Health' -Name 'Transaction Log Size' -Status 'warning' -Severity 'medium' -Evidence "Transaction log is $($summary.logSizeGb) GB." -Recommendation 'Investigate log backups, long-running transactions and recovery model settings.'
    } else {
        Add-Check -Id 'sql-log-size' -Category 'SQL / Database Health' -Name 'Transaction Log Size' -Status 'passed' -Severity 'low' -Evidence "Transaction log is $($summary.logSizeGb) GB." -Recommendation ''
    }

    if ($summary.freeSpaceGb -le 1 -and $summary.databaseSizeGb) {
        $summary.growthWarning = $true
        Add-Check -Id 'sql-growth-warning' -Category 'SQL / Database Health' -Name 'Database Growth Headroom' -Status 'warning' -Severity 'high' -Evidence "Only $($summary.freeSpaceGb) GB free remains inside the data files." -Recommendation 'Pre-grow files or free capacity to avoid autogrowth pressure.'
    } else {
        Add-Check -Id 'sql-growth-warning' -Category 'SQL / Database Health' -Name 'Database Growth Headroom' -Status 'passed' -Severity 'medium' -Evidence 'No immediate database growth pressure detected.' -Recommendation ''
    }

    if ($summary.currentLogin) {
        Add-Check -Id 'service-account-permissions' -Category 'Upgrade Readiness' -Name 'SQL Access Identity' -Status 'passed' -Severity 'medium' -Evidence "Current SQL login: $($summary.currentLogin)" -Recommendation ''
    } else {
        Add-Check -Id 'service-account-permissions' -Category 'Upgrade Readiness' -Name 'SQL Access Identity' -Status 'warning' -Severity 'medium' -Evidence 'Could not confirm the current SQL login. This does not prove the Veeam ONE service account permissions.' -Recommendation 'Validate Veeam ONE service account rights in SQL manually if needed.'
    }

    return $summary
}

function Invoke-CollectionHealth {
    param([hashtable]$SqlHealth)

    $result = [ordered]@{
        supported = $false
        source = ''
        failedCollectorTasks = $null
        objectPropertiesFailures = $null
        performanceCollectionFailures = $null
        lastSuccessfulCollectionTime = $null
        lastFailureTime = $null
        failureCount = $null
        note = ''
    }

    if (-not $SqlHealth.connectionOk) {
        Add-Check -Id 'collection-health' -Category 'Collection Health' -Name 'Collection Health Availability' -Status 'skipped' -Severity 'medium' -Evidence 'Skipped because SQL is unavailable.' -Recommendation ''
        return $result
    }

    $variants = @(
        @{
            name = 'collection-task-events'
            query = @"
SELECT TOP 1
    SUM(CASE WHEN status IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS FailedCollectorTasks,
    SUM(CASE WHEN task_name LIKE '%Object Properties%' AND status IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS ObjectPropertiesFailures,
    SUM(CASE WHEN task_name LIKE '%Performance%' AND status IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS PerformanceCollectionFailures,
    MAX(CASE WHEN status IN ('Success', 'Completed') THEN finish_time END) AS LastSuccessfulCollectionTime,
    MAX(CASE WHEN status IN ('Failed', 'Error') THEN finish_time END) AS LastFailureTime,
    SUM(CASE WHEN status IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS FailureCount
FROM dbo.CollectionTaskHistory;
"@
        },
        @{
            name = 'collector-sessions'
            query = @"
SELECT TOP 1
    SUM(CASE WHEN state IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS FailedCollectorTasks,
    SUM(CASE WHEN name LIKE '%Object Properties%' AND state IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS ObjectPropertiesFailures,
    SUM(CASE WHEN name LIKE '%Performance%' AND state IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS PerformanceCollectionFailures,
    MAX(CASE WHEN state IN ('Success', 'Completed') THEN end_time END) AS LastSuccessfulCollectionTime,
    MAX(CASE WHEN state IN ('Failed', 'Error') THEN end_time END) AS LastFailureTime,
    SUM(CASE WHEN state IN ('Failed', 'Error') THEN 1 ELSE 0 END) AS FailureCount
FROM dbo.CollectorTaskSessions;
"@
        }
    )
    $query = Invoke-SqlVariantQuery -Variants $variants
    if (-not $query.ok) {
        if ($query.unsupported) {
            $result.note = 'Check not supported on this version.'
            $availabilityStatus = 'skipped'
        } else {
            $result.note = $query.error
            $availabilityStatus = 'warning'
        }
        Add-Check -Id 'collection-health' -Category 'Collection Health' -Name 'Collection Health Availability' -Status $availabilityStatus -Severity 'medium' -Evidence $result.note -Recommendation ''
        return $result
    }

    $result.supported = $true
    $result.source = $query.source
    $row = $query.rows[0]
    $result.failedCollectorTasks = Get-DataRowValue -Row $row -Column 'FailedCollectorTasks'
    $result.objectPropertiesFailures = Get-DataRowValue -Row $row -Column 'ObjectPropertiesFailures'
    $result.performanceCollectionFailures = Get-DataRowValue -Row $row -Column 'PerformanceCollectionFailures'
    $result.lastSuccessfulCollectionTime = Get-DataRowValue -Row $row -Column 'LastSuccessfulCollectionTime'
    $result.lastFailureTime = Get-DataRowValue -Row $row -Column 'LastFailureTime'
    $result.failureCount = Get-DataRowValue -Row $row -Column 'FailureCount'

    if ([int]$result.failureCount -gt 0) {
        $status = 'warning'
        $rec = 'Review collector tasks, object properties jobs, performance collection and related services.'
    } else {
        $status = 'passed'
        $rec = ''
    }
    $evidence = "FailedTasks=$($result.failedCollectorTasks); ObjectPropertiesFailures=$($result.objectPropertiesFailures); PerformanceFailures=$($result.performanceCollectionFailures); LastSuccess=$($result.lastSuccessfulCollectionTime); LastFailure=$($result.lastFailureTime)"
    Add-Check -Id 'collection-health' -Category 'Collection Health' -Name 'Collection Task Health' -Status $status -Severity 'high' -Evidence $evidence -Recommendation $rec
    return $result
}

function Invoke-AlarmHealth {
    param([hashtable]$SqlHealth)

    $result = [ordered]@{
        supported = $false
        source = ''
        totalAlarms = $null
        activeAlarms = $null
        disabledAlarms = $null
        warningOrErrorAlarms = $null
        recentAlarmNames = @()
        highlighted = @()
        note = ''
    }

    if (-not $SqlHealth.connectionOk) {
        Add-Check -Id 'alarm-health' -Category 'Alarm Health' -Name 'Alarm Health Availability' -Status 'skipped' -Severity 'medium' -Evidence 'Skipped because SQL is unavailable.' -Recommendation ''
        return $result
    }

    $variants = @(
        @{
            name = 'alarm-summary'
            query = @"
SELECT TOP 25
    name AS AlarmName,
    status AS AlarmStatus,
    enabled AS Enabled,
    last_triggered AS LastTriggered
FROM dbo.Alarms
ORDER BY last_triggered DESC;
"@
        },
        @{
            name = 'alarm-state'
            query = @"
SELECT TOP 25
    alarm_name AS AlarmName,
    state AS AlarmStatus,
    is_enabled AS Enabled,
    last_triggered_at AS LastTriggered
FROM dbo.AlarmState
ORDER BY last_triggered_at DESC;
"@
        }
    )
    $query = Invoke-SqlVariantQuery -Variants $variants
    if (-not $query.ok) {
        if ($query.unsupported) {
            $result.note = 'Check not supported on this version.'
            $availabilityStatus = 'skipped'
        } else {
            $result.note = $query.error
            $availabilityStatus = 'warning'
        }
        Add-Check -Id 'alarm-health' -Category 'Alarm Health' -Name 'Alarm Health Availability' -Status $availabilityStatus -Severity 'medium' -Evidence $result.note -Recommendation ''
        return $result
    }

    $rows = @($query.rows)
    $result.supported = $true
    $result.source = $query.source
    $result.totalAlarms = $rows.Count
    $result.activeAlarms = @($rows | Where-Object { ([string](Get-DataRowValue -Row $_ -Column 'AlarmStatus')) -match 'Active|Triggered|Error|Warning' }).Count
    $result.disabledAlarms = @($rows | Where-Object {
        $enabled = Get-DataRowValue -Row $_ -Column 'Enabled'
        $enabled -eq $false -or [string]$enabled -eq '0'
    }).Count
    $result.warningOrErrorAlarms = @($rows | Where-Object { ([string](Get-DataRowValue -Row $_ -Column 'AlarmStatus')) -match 'Warning|Error' }).Count
    $result.recentAlarmNames = @($rows | Select-Object -First 5 | ForEach-Object { [string](Get-DataRowValue -Row $_ -Column 'AlarmName') })

    $keywords = 'Potential malware', 'Backup failure', 'Repository', 'Infrastructure', 'SQL', 'Collector'
    foreach ($alarmName in $result.recentAlarmNames) {
        foreach ($keyword in $keywords) {
            if ($alarmName -like "*$keyword*") {
                $result.highlighted += $alarmName
                break
            }
        }
    }

    if ($result.warningOrErrorAlarms -gt 0 -or $result.highlighted.Count -gt 0) {
        $status = 'warning'
        $rec = 'Review active alarms, especially SQL, repository, collector and malware-related alerts.'
    } else {
        $status = 'passed'
        $rec = ''
    }
    $evidence = "Total=$($result.totalAlarms); Active=$($result.activeAlarms); Disabled=$($result.disabledAlarms); WarningOrError=$($result.warningOrErrorAlarms); Recent=$($result.recentAlarmNames -join ', ')"
    Add-Check -Id 'alarm-health' -Category 'Alarm Health' -Name 'Alarm Summary' -Status $status -Severity 'medium' -Evidence $evidence -Recommendation $rec
    return $result
}

function Get-DiscoveredTargets {
    param([hashtable]$SqlHealth)

    $targets = @()
    if ($SqlHealth.connectionOk) {
        $variants = @(
            @{
                name = 'managed-servers'
                query = "SELECT TOP 50 name AS TargetName, 'Discovered server' AS TargetType FROM dbo.ManagedServers;"
            },
            @{
                name = 'monitored-infrastructure'
                query = "SELECT TOP 50 display_name AS TargetName, object_type AS TargetType FROM dbo.MonitoredInfrastructure;"
            }
        )
        $query = Invoke-SqlVariantQuery -Variants $variants
        if ($query.ok) {
            foreach ($row in $query.rows) {
                $name = [string](Get-DataRowValue -Row $row -Column 'TargetName')
                $kind = [string](Get-DataRowValue -Row $row -Column 'TargetType')
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $targetKind = 'Discovered target'
                    if ($kind) { $targetKind = $kind }
                    $targets += [ordered]@{
                        target = $name
                        kind = $targetKind
                    }
                }
            }
        }
    }
    return $targets
}

function Invoke-PortCheckModule {
    param(
        [hashtable]$SqlHealth,
        [array]$DiscoveredTargets
    )

    $results = @()
    $items = New-Object System.Collections.ArrayList

    if ($SqlHealth.configured) {
        [void]$items.Add([ordered]@{ target = $SqlServer; port = $SqlPort; label = 'SQL Server' })
    }

    foreach ($t in $Target) {
        if ($Port.Count -gt 0) {
            foreach ($p in $Port) {
                [void]$items.Add([ordered]@{ target = $t; port = $p; label = 'Manual target' })
            }
        } else {
            [void]$items.Add([ordered]@{ target = $t; port = 1433; label = 'Manual target' })
        }
    }

    foreach ($item in $DiscoveredTargets | Select-Object -First 10) {
        $candidatePort = 0
        $kind = [string]$item.kind
        if ($kind -match 'VBR|Backup') { $candidatePort = 9392 }
        elseif ($kind -match 'vCenter') { $candidatePort = 443 }
        elseif ($kind -match 'Hyper-V') { $candidatePort = 5985 }
        if ($candidatePort -gt 0) {
            [void]$items.Add([ordered]@{ target = $item.target; port = $candidatePort; label = $kind })
        }
    }

    if ($items.Count -eq 0) {
        Add-Check -Id 'port-checks' -Category 'Port Checks' -Name 'Port Validation' -Status 'skipped' -Severity 'low' -Evidence 'No targets were available for port checks.' -Recommendation ''
        return $results
    }

    $seen = @{}
    foreach ($item in $items) {
        $key = "$($item.target):$($item.port)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $probe = Test-PortConnectivity -ComputerName $item.target -PortNumber $item.port
        $probe.label = $item.label
        $results += $probe
        if ($probe.reachable) {
            $status = 'passed'
            $rec = ''
        } else {
            $status = 'warning'
            $rec = "Verify connectivity from this host to $($probe.target):$($probe.port)."
        }
        $evidence = "{0} via {1}; Detail={2}" -f $key, $probe.source, $probe.detail
        Add-Check -Id ("port-check-" + ($key -replace '[^a-zA-Z0-9]+', '-').ToLower()) -Category 'Port Checks' -Name "$($item.label) connectivity" -Status $status -Severity 'medium' -Evidence $evidence -Recommendation $rec
    }
    return $results
}

function Invoke-LogAnalysis {
    $findings = @()
    if (-not $AnalyzeLogs -and [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Check -Id 'log-analysis' -Category 'Log Analysis' -Name 'Log Analysis' -Status 'skipped' -Severity 'low' -Evidence 'Log analysis was not requested.' -Recommendation ''
        return $findings
    }

    if ([string]::IsNullOrWhiteSpace($LogPath) -or -not (Test-Path $LogPath)) {
        Add-Check -Id 'log-analysis' -Category 'Log Analysis' -Name 'Log Analysis Path' -Status 'warning' -Severity 'medium' -Evidence "Log path '$LogPath' was not found." -Recommendation 'Provide -LogPath pointing to the Veeam ONE log folder.'
        return $findings
    }

    $files = @()
    try {
        if ((Get-Item $LogPath).PSIsContainer) {
            $files = @(Get-ChildItem -Path $LogPath -Recurse -Include *.log, *.txt -File -ErrorAction SilentlyContinue)
        } else {
            $files = @(Get-Item -Path $LogPath -ErrorAction Stop)
        }
    } catch {
        Add-Check -Id 'log-analysis' -Category 'Log Analysis' -Name 'Log Analysis Path' -Status 'warning' -Severity 'medium' -Evidence $_.Exception.Message -Recommendation 'Verify the supplied log path and file permissions.'
        return $findings
    }

    foreach ($file in $files | Select-Object -First 25) {
        $lineNumber = 0
        try {
            Get-Content -Path $file.FullName -ErrorAction Stop | ForEach-Object {
                $lineNumber++
                foreach ($rule in $script:KnownIssueRules) {
                    if ($_ -match $rule.regex) {
                        $findings += [ordered]@{
                            pattern = $rule.name
                            file = $file.FullName
                            lineNumber = $lineNumber
                            severity = $rule.severity
                            cause = $rule.cause
                            recommendation = $rule.recommendation
                            line = $_
                        }
                    }
                }
            }
        } catch {
            $findings += [ordered]@{
                pattern = 'Log read failure'
                file = $file.FullName
                lineNumber = $null
                severity = 'warning'
                cause = 'The log file could not be read.'
                recommendation = 'Check file permissions and whether the log is locked.'
                line = $_.Exception.Message
            }
        }
    }

    if ($findings.Count -eq 0) {
        Add-Check -Id 'log-analysis' -Category 'Log Analysis' -Name 'Known Issue Patterns' -Status 'passed' -Severity 'medium' -Evidence "No known issue patterns were detected in $($files.Count) file(s)." -Recommendation ''
    } else {
        $critical = @($findings | Where-Object { $_.severity -eq 'failed' }).Count
        $warning = @($findings | Where-Object { $_.severity -eq 'warning' }).Count
        Add-Check -Id 'log-analysis' -Category 'Log Analysis' -Name 'Known Issue Patterns' -Status 'warning' -Severity 'high' -Evidence "Detected $critical critical and $warning warning log pattern(s)." -Recommendation 'Review the log findings section and address the highlighted causes.'
    }
    return $findings
}

function Invoke-SizingValidation {
    $assessment = [ordered]@{
        supported = $true
        status = 'Supported'
        sqlEditionRecommendation = 'SQL Standard'
        resourceRecommendation = 'Keep dedicated CPU, memory and SQL capacity for Veeam ONE.'
        notes = @()
    }

    if (-not $ValidateSizing) {
        Add-Check -Id 'sizing-guidance' -Category 'Architecture / Sizing' -Name 'Sizing Guidance' -Status 'skipped' -Severity 'low' -Evidence 'Sizing validation was not requested.' -Recommendation ''
        return $assessment
    }

    if ($VMCount -le 0 -and $HostCount -le 0 -and $RepositoryTB -le 0) {
        Add-Check -Id 'sizing-guidance' -Category 'Architecture / Sizing' -Name 'Sizing Guidance' -Status 'warning' -Severity 'low' -Evidence 'Sizing validation was requested but no sizing inputs were supplied.' -Recommendation 'Provide VMCount, HostCount and RepositoryTB for sizing guidance.'
        $assessment.status = 'Warning'
        $assessment.notes += 'Sizing guidance is incomplete without workload numbers.'
        return $assessment
    }

    if ($VMCount -gt 2000 -or $RepositoryTB -gt 500 -or $HostCount -gt 50) {
        $assessment.supported = $false
        $assessment.status = 'Not recommended'
        $assessment.sqlEditionRecommendation = 'SQL Enterprise or carefully sized SQL Standard'
        $assessment.resourceRecommendation = 'Consider scale-out architecture, larger SQL capacity and dedicated monitoring infrastructure.'
        $assessment.notes += 'Workload size is beyond conservative single-server guidance.'
        Add-Check -Id 'sizing-guidance' -Category 'Architecture / Sizing' -Name 'Sizing Guidance' -Status 'failed' -Severity 'high' -Evidence "VMs=$VMCount; Hosts=$HostCount; RepositoryTB=$RepositoryTB. Guidance only, not official support validation." -Recommendation $assessment.resourceRecommendation
    } elseif ($VMCount -gt 1000 -or $RepositoryTB -gt 250 -or $HostCount -gt 20) {
        $assessment.status = 'Warning'
        $assessment.sqlEditionRecommendation = 'SQL Standard or Enterprise'
        $assessment.resourceRecommendation = 'Plan additional RAM, faster SQL storage and careful retention sizing.'
        $assessment.notes += 'Environment is in a higher-demand range and should be reviewed carefully.'
        Add-Check -Id 'sizing-guidance' -Category 'Architecture / Sizing' -Name 'Sizing Guidance' -Status 'warning' -Severity 'medium' -Evidence "VMs=$VMCount; Hosts=$HostCount; RepositoryTB=$RepositoryTB. Guidance only, not official support validation." -Recommendation $assessment.resourceRecommendation
    } else {
        $assessment.notes += 'Environment fits conservative generic sizing guidance.'
        Add-Check -Id 'sizing-guidance' -Category 'Architecture / Sizing' -Name 'Sizing Guidance' -Status 'passed' -Severity 'low' -Evidence "VMs=$VMCount; Hosts=$HostCount; RepositoryTB=$RepositoryTB. Guidance only, not official support validation." -Recommendation ''
    }
    return $assessment
}

function Invoke-UpgradeReadinessChecks {
    param(
        [hashtable]$SqlHealth,
        [array]$Services
    )

    Write-Section 'Upgrade Readiness'

    $computerSystem = $null
    try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $supported = ($os.Caption -match '2016|2019|2022')
        if ($supported) {
            $status = 'passed'
            $recommendation = ''
        } else {
            $status = 'warning'
            $recommendation = 'Confirm that this Windows Server version is supported for the target Veeam ONE release.'
        }
        Add-Check -Id 'os-version' -Category 'Upgrade Readiness' -Name 'OS Version' -Status $status -Severity 'medium' -Evidence "$($os.Caption) (Build $($os.BuildNumber))" -Recommendation $recommendation
    } catch {
        Add-Check -Id 'os-version' -Category 'Upgrade Readiness' -Name 'OS Version' -Status 'skipped' -Severity 'medium' -Evidence $_.Exception.Message -Recommendation ''
    }

    try {
        $cores = [int]$computerSystem.NumberOfLogicalProcessors
        if ($cores -ge 4) {
            $status = 'passed'
            $recommendation = ''
        } elseif ($cores -ge 2) {
            $status = 'warning'
            $recommendation = 'Allocate at least 4 logical processors before upgrade.'
        } else {
            $status = 'failed'
            $recommendation = 'Allocate at least 4 logical processors before upgrade.'
        }
        Add-Check -Id 'cpu-count' -Category 'Upgrade Readiness' -Name 'CPU Cores' -Status $status -Severity 'medium' -Evidence "$cores logical processor(s)." -Recommendation $recommendation
    } catch {
        Add-Check -Id 'cpu-count' -Category 'Upgrade Readiness' -Name 'CPU Cores' -Status 'skipped' -Severity 'medium' -Evidence $_.Exception.Message -Recommendation ''
    }

    try {
        $ramGb = [math]::Round([double]$computerSystem.TotalPhysicalMemory / 1GB, 1)
        if ($ramGb -ge 8) {
            $status = 'passed'
            $recommendation = ''
        } elseif ($ramGb -ge 4) {
            $status = 'warning'
            $recommendation = 'Increase memory before upgrade.'
        } else {
            $status = 'failed'
            $recommendation = 'Increase memory before upgrade.'
        }
        Add-Check -Id 'ram-amount' -Category 'Upgrade Readiness' -Name 'Memory (RAM)' -Status $status -Severity 'high' -Evidence "$ramGb GB physical memory." -Recommendation $recommendation
    } catch {
        Add-Check -Id 'ram-amount' -Category 'Upgrade Readiness' -Name 'Memory (RAM)' -Status 'skipped' -Severity 'high' -Evidence $_.Exception.Message -Recommendation ''
    }

    try {
        $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $freeGb = [math]::Round([double]$drive.FreeSpace / 1GB, 1)
        if ($freeGb -ge 10) {
            $status = 'passed'
            $recommendation = ''
        } elseif ($freeGb -ge 5) {
            $status = 'warning'
            $recommendation = 'Free additional system drive space before upgrade.'
        } else {
            $status = 'failed'
            $recommendation = 'Free additional system drive space before upgrade.'
        }
        Add-Check -Id 'disk-free-system' -Category 'Upgrade Readiness' -Name 'System Drive Free Space' -Status $status -Severity 'high' -Evidence "$freeGb GB free on $($env:SystemDrive)." -Recommendation $recommendation
    } catch {
        Add-Check -Id 'disk-free-system' -Category 'Upgrade Readiness' -Name 'System Drive Free Space' -Status 'skipped' -Severity 'high' -Evidence $_.Exception.Message -Recommendation ''
    }

    $versionInfo = Get-VeeamOneVersion
    if ($versionInfo) {
        $status = 'passed'
        $rec = ''
        if ($CurrentVersion -and $versionInfo.version -and $CurrentVersion -ne $versionInfo.version) {
            $status = 'warning'
            $rec = 'The discovered Veeam ONE version does not match the supplied CurrentVersion value.'
        }
        Add-Check -Id 'veeam-one-version' -Category 'Upgrade Readiness' -Name 'Installed Veeam ONE Version' -Status $status -Severity 'medium' -Evidence "$($versionInfo.displayName) $($versionInfo.version)" -Recommendation $rec
    } else {
        Add-Check -Id 'veeam-one-version' -Category 'Upgrade Readiness' -Name 'Installed Veeam ONE Version' -Status 'warning' -Severity 'medium' -Evidence 'Could not detect an installed Veeam ONE version.' -Recommendation 'Verify that you are running the script on the Veeam ONE server.'
    }

    $dotNet = Get-DotNetVersion
    if ($dotNet) {
        if ($dotNet.release -ge 461808) {
            $status = 'passed'
            $recommendation = ''
        } else {
            $status = 'warning'
            $recommendation = 'Install .NET Framework 4.7.2 or later before upgrading.'
        }
        Add-Check -Id 'dotnet-runtime' -Category 'Upgrade Readiness' -Name '.NET Framework' -Status $status -Severity 'medium' -Evidence ".NET Framework $($dotNet.version) (release $($dotNet.release))." -Recommendation $recommendation
    } else {
        Add-Check -Id 'dotnet-runtime' -Category 'Upgrade Readiness' -Name '.NET Framework' -Status 'warning' -Severity 'medium' -Evidence 'Could not detect the installed .NET Framework version.' -Recommendation 'Validate the required .NET Framework version manually.'
    }

    try {
        $pendingReasons = @()
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pendingReasons += 'Component Based Servicing' }
        if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pendingReasons += 'Windows Update' }
        $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pfro) { $pendingReasons += 'Pending file rename' }
        if ($pendingReasons.Count -gt 0) {
            Add-Check -Id 'pending-reboot' -Category 'Upgrade Readiness' -Name 'Pending Reboot' -Status 'failed' -Severity 'high' -Evidence ($pendingReasons -join ', ') -Recommendation 'Clear pending reboot conditions before upgrade.'
        } else {
            Add-Check -Id 'pending-reboot' -Category 'Upgrade Readiness' -Name 'Pending Reboot' -Status 'passed' -Severity 'low' -Evidence 'No pending reboot detected.' -Recommendation ''
        }
    } catch {
        Add-Check -Id 'pending-reboot' -Category 'Upgrade Readiness' -Name 'Pending Reboot' -Status 'skipped' -Severity 'low' -Evidence $_.Exception.Message -Recommendation ''
    }

    $accounts = @($Services | Where-Object { $_.exists -and $_.account } | ForEach-Object { $_.account } | Select-Object -Unique)
    if ($accounts.Count -gt 0) {
        Add-Check -Id 'service-account-summary' -Category 'Upgrade Readiness' -Name 'Service Account Configuration' -Status 'passed' -Severity 'medium' -Evidence ("Service accounts: " + ($accounts -join ', ')) -Recommendation ''
    } else {
        Add-Check -Id 'service-account-summary' -Category 'Upgrade Readiness' -Name 'Service Account Configuration' -Status 'warning' -Severity 'medium' -Evidence 'Could not determine the Veeam ONE service accounts.' -Recommendation 'Verify service logon accounts and their local and SQL permissions manually.'
    }

    return [ordered]@{
        mode = $Mode
        currentVersion = $CurrentVersion
        targetVersion = $TargetVersion
        blockers = @($script:Checks | Where-Object { $_.category -eq 'Upgrade Readiness' -and $_.status -eq 'failed' } | ForEach-Object { $_.name })
        warnings = @($script:Checks | Where-Object { $_.category -eq 'Upgrade Readiness' -and $_.status -eq 'warning' } | ForEach-Object { $_.name })
    }
}

function Compute-OverallSummary {
    $criticalIds = @(
        'sql-dns-resolution',
        'sql-port-connectivity',
        'sql-connection',
        'database-existence',
        'pending-reboot'
    )

    $deduction = 0
    $warningCount = 0
    foreach ($check in $script:Checks) {
        if ($check.status -eq 'failed') {
            switch ($check.severity) {
                'critical' { $deduction += 25 }
                'high' { $deduction += 15 }
                'medium' { $deduction += 10 }
                'low' { $deduction += 5 }
            }
        } elseif ($check.status -eq 'warning') {
            $warningCount++
            $deduction += 5
        }
    }
    $score = [math]::Max(0, 100 - $deduction)
    $blockers = @($script:Checks | Where-Object { $_.status -eq 'failed' -and ($criticalIds -contains $_.id -or $_.severity -eq 'critical') })
    if ($blockers.Count -gt 0 -or $score -lt 60) {
        $status = 'Not Ready'
    } elseif ($score -lt 85 -or $warningCount -gt 0) {
        $status = 'Warning'
    } else {
        $status = 'Ready'
    }

    $topIssues = @(
        $script:Checks |
        Where-Object { $_.status -in @('failed', 'warning') } |
        Select-Object -First 8 |
        ForEach-Object {
            if ($_.recommendation) { "$($_.name) - $($_.recommendation)" } else { $_.name }
        }
    )

    return [ordered]@{
        score = $score
        status = $status
        topIssues = $topIssues
        passed = @($script:Checks | Where-Object { $_.status -eq 'passed' }).Count
        warnings = @($script:Checks | Where-Object { $_.status -eq 'warning' }).Count
        failed = @($script:Checks | Where-Object { $_.status -eq 'failed' }).Count
        skipped = @($script:Checks | Where-Object { $_.status -eq 'skipped' }).Count
        criticalIssues = @($script:Checks | Where-Object { $_.status -eq 'failed' -and $_.severity -in @('critical', 'high') } | ForEach-Object { $_.name })
        recommendations = @($script:Recommendations)
    }
}

function Export-HtmlReport {
    param(
        [hashtable]$Report,
        [string]$Path
    )
    $rows = foreach ($check in $Report.checks) {
        [pscustomobject]@{
            Category = $check.category
            Check = $check.name
            Status = $check.status
            Severity = $check.severity
            Evidence = $check.evidence
            Recommendation = $check.recommendation
        }
    }
    $summary = @"
<h1>Veeam ONE Health Check & Troubleshooting Assistant</h1>
<p><strong>Mode:</strong> $($Report.mode) <strong>Status:</strong> $($Report.summary.status) <strong>Score:</strong> $($Report.summary.score)/100</p>
<p><strong>Host:</strong> $($Report.target.computerName) <strong>SQL:</strong> $($Report.target.sqlServer) <strong>Database:</strong> $($Report.target.database)</p>
<h2>Recommendations</h2>
<ul>$((@($Report.summary.recommendations) | ForEach-Object { "<li>$_</li>" }) -join '')</ul>
<h2>Top Issues</h2>
<ul>$((@($Report.summary.topIssues) | ForEach-Object { "<li>$_</li>" }) -join '')</ul>
"@
    $css = @"
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #0f172a; }
h1, h2 { color: #0f172a; }
table { border-collapse: collapse; width: 100%; margin-top: 16px; }
th, td { border: 1px solid #cbd5e1; padding: 8px; text-align: left; vertical-align: top; }
th { background: #e2e8f0; }
"@
    $html = $rows | ConvertTo-Html -Title 'Veeam ONE Health Report' -PreContent $summary -Head "<style>$css</style>"
    Set-Content -Path $Path -Value $html -Encoding UTF8
}

function Export-CsvReport {
    param(
        [hashtable]$Report,
        [string]$Path
    )
    $Report.checks | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

Ensure-ParentDirectory -Path $ExportJson
if ($ExportHtml) { Ensure-ParentDirectory -Path $ExportHtml }
if ($ExportCsv) { Ensure-ParentDirectory -Path $ExportCsv }

Write-Section 'Veeam ONE Health Check & Troubleshooting Assistant'
Write-Host "Mode: $Mode" -ForegroundColor Cyan
Write-Host "Script root: $ScriptRoot" -ForegroundColor DarkGray
Write-Host "Basic checks do not require admin rights. Some details may be reduced without elevation." -ForegroundColor DarkGray
if (-not (Test-IsAdministrator)) {
    Write-Host 'Running without elevation. Some service/process details may be limited.' -ForegroundColor Yellow
}

$sqlHealth = [ordered]@{}
$services = @()
$discoveredTargets = @()

Write-Section 'Veeam ONE Services Health'
$services = Get-VeeamServiceHealth
$script:ModuleData.services = $services

Write-Section 'SQL / Database Health'
$sqlHealth = Get-SqlDatabaseHealth
$script:ModuleData.sql = $sqlHealth

if ($Mode -in @('Upgrade', 'Full')) {
    $script:ModuleData.upgradeReadiness = Invoke-UpgradeReadinessChecks -SqlHealth $sqlHealth -Services $services
}

if ($Mode -in @('Health', 'Full')) {
    Write-Section 'Collection Health'
    $script:ModuleData.collections = Invoke-CollectionHealth -SqlHealth $sqlHealth

    Write-Section 'Alarm Health'
    $script:ModuleData.alarms = Invoke-AlarmHealth -SqlHealth $sqlHealth
}

$discoveredTargets = Get-DiscoveredTargets -SqlHealth $sqlHealth
$script:ModuleData.discoveredTargets = $discoveredTargets

if ($Mode -in @('Health', 'Full') -or $CheckPorts) {
    Write-Section 'Port Checks'
    $script:ModuleData.ports = Invoke-PortCheckModule -SqlHealth $sqlHealth -DiscoveredTargets $discoveredTargets
}

if ($Mode -eq 'Full' -or $AnalyzeLogs -or $LogPath) {
    Write-Section 'Log Analysis'
    $script:ModuleData.logs = Invoke-LogAnalysis
}

if ($Mode -eq 'Full' -or $ValidateSizing) {
    Write-Section 'Architecture / Sizing'
    $script:ModuleData.sizing = Invoke-SizingValidation
}

$summary = Compute-OverallSummary
$action = 'Full Health Check'
if ($Mode -eq 'Upgrade') {
    $action = 'Upgrade Readiness'
} elseif ($Mode -eq 'Health') {
    $action = 'Health Check'
}
$report = [ordered]@{
    product = 'Veeam ONE'
    toolName = 'Veeam ONE Health Check & Troubleshooting Assistant'
    action = $action
    mode = $Mode
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    currentVersion = $CurrentVersion
    targetVersion = $TargetVersion
    target = [ordered]@{
        computerName = $env:COMPUTERNAME
        sqlServer = $SqlServer
        sqlInstance = $SqlInstance
        database = $DatabaseName
        port = $SqlPort
    }
    checks = @($script:Checks)
    summary = $summary
    details = $script:ModuleData
}

$json = $report | ConvertTo-Json -Depth 10
Set-Content -Path $ExportJson -Value $json -Encoding UTF8
if ($ExportHtml) { Export-HtmlReport -Report $report -Path $ExportHtml }
if ($ExportCsv) { Export-CsvReport -Report $report -Path $ExportCsv }

Write-Section 'Summary'
Write-Host ("Overall score: {0}/100" -f $summary.score) -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $summary.status) -ForegroundColor Cyan
if ($summary.topIssues.Count -gt 0) {
    Write-Host 'Top issues:' -ForegroundColor Yellow
    foreach ($issue in $summary.topIssues) {
        Write-Host (" - {0}" -f $issue) -ForegroundColor Yellow
    }
}
Write-Host "JSON report: $ExportJson" -ForegroundColor Green
if ($ExportHtml) { Write-Host "HTML report: $ExportHtml" -ForegroundColor Green }
if ($ExportCsv) { Write-Host "CSV report: $ExportCsv" -ForegroundColor Green }
