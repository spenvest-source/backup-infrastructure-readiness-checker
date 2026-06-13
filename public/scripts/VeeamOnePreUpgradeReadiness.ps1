<#
.SYNOPSIS
    Veeam ONE Pre-Upgrade Readiness checker.

.DESCRIPTION
    Runs read-only System, Network, SQL and Veeam ONE service checks and writes
    a single sanitized JSON document to a local file. It does NOT collect or
    output passwords, secrets or tokens, and it does NOT upload anything.
    SQL checks use Windows authentication only.

    Run this FROM the Veeam ONE server, or from a host that shares the same
    network path to the SQL Server.

    UNOFFICIAL readiness tool - not affiliated with or supported by Veeam.
    REVIEW the JSON output before sharing it with anyone.

.NOTES
    Use Windows PowerShell 5.1. Example:
      .\VeeamOnePreUpgradeReadiness.ps1 -SqlServer sql01 -CurrentVersion 11.0 -TargetVersion 12.1
#>

param(
    [string]$CurrentVersion = '{{CURRENT_VERSION}}',
    [string]$TargetVersion = '{{TARGET_VERSION}}',
    [string]$SqlServer = '{{SQL_SERVER}}',
    [string]$SqlInstance = '{{SQL_INSTANCE}}',
    [string]$DatabaseName = '{{DATABASE_NAME}}',
    [int]$SqlPort = {{SQL_PORT}},
    [string]$OutputPath = '.\veeamone-readiness-result.json'
)

$ErrorActionPreference = 'Stop'

# --- Result collection -----------------------------------------------------
$script:Checks = New-Object System.Collections.ArrayList
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
    [void]$script:Checks.Add([ordered]@{
        id             = $Id
        category       = $Category
        name           = $Name
        status         = $Status
        severity       = $Severity
        evidence       = $Evidence
        recommendation = $Recommendation
    })
}

# ==========================================================================
# SYSTEM HEALTH
# ==========================================================================
$computerSystem = $null
try { $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}

# 1. OS version and build
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Add-Check 'os-version' 'System Health' 'OS Version' 'passed' 'info' "$($os.Caption) (Build $($os.BuildNumber))" ''
} catch {
    Add-Check 'os-version' 'System Health' 'OS Version' 'skipped' 'info' "Could not read OS information: $($_.Exception.Message)" ''
}

# 2. CPU count
try {
    $cores = [int]$computerSystem.NumberOfLogicalProcessors
    if ($cores -ge 4) {
        Add-Check 'cpu-count' 'System Health' 'CPU Cores' 'passed' 'medium' "$cores logical processors." ''
    } elseif ($cores -ge 2) {
        Add-Check 'cpu-count' 'System Health' 'CPU Cores' 'warning' 'medium' "$cores logical processors (4+ recommended)." 'Allocate at least 4 logical processors before upgrade.'
    } else {
        Add-Check 'cpu-count' 'System Health' 'CPU Cores' 'failed' 'high' "$cores logical processor(s)." 'Allocate at least 4 logical processors before upgrade.'
    }
} catch {
    Add-Check 'cpu-count' 'System Health' 'CPU Cores' 'skipped' 'medium' "Could not read CPU information: $($_.Exception.Message)" ''
}

# 3. RAM amount
try {
    $ramGB = [math]::Round([double]$computerSystem.TotalPhysicalMemory / 1GB, 1)
    if ($ramGB -ge 8) {
        Add-Check 'ram-amount' 'System Health' 'Memory (RAM)' 'passed' 'medium' "$($ramGB) GB physical memory." ''
    } elseif ($ramGB -ge 4) {
        Add-Check 'ram-amount' 'System Health' 'Memory (RAM)' 'warning' 'medium' "$($ramGB) GB physical memory (8+ GB recommended)." 'Increase memory to at least 8 GB before upgrade.'
    } else {
        Add-Check 'ram-amount' 'System Health' 'Memory (RAM)' 'failed' 'high' "$($ramGB) GB physical memory." 'Increase memory to at least 8 GB before upgrade.'
    }
} catch {
    Add-Check 'ram-amount' 'System Health' 'Memory (RAM)' 'skipped' 'medium' "Could not read memory information: $($_.Exception.Message)" ''
}

# 4. Free disk space on the system drive
try {
    $sysDrive = $env:SystemDrive
    $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction Stop
    $freeGB = [math]::Round([double]$ld.FreeSpace / 1GB, 1)
    if ($freeGB -ge 10) {
        Add-Check 'disk-free-system' 'System Health' 'System Drive Free Space' 'passed' 'high' "$($freeGB) GB free on $sysDrive." ''
    } elseif ($freeGB -ge 5) {
        Add-Check 'disk-free-system' 'System Health' 'System Drive Free Space' 'warning' 'high' "$($freeGB) GB free on $sysDrive." 'Free additional disk space on the system drive before upgrade.'
    } else {
        Add-Check 'disk-free-system' 'System Health' 'System Drive Free Space' 'failed' 'high' "$($freeGB) GB free on $sysDrive." 'Free additional disk space on the system drive before upgrade.'
    }
} catch {
    Add-Check 'disk-free-system' 'System Health' 'System Drive Free Space' 'skipped' 'high' "Could not read disk information: $($_.Exception.Message)" ''
}

# 5. Pending reboot detection
try {
    $pendingReasons = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pendingReasons += 'Component Based Servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pendingReasons += 'Windows Update' }
    $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pfro) { $pendingReasons += 'Pending file rename' }
    if ($pendingReasons.Count -gt 0) {
        Add-Check 'pending-reboot' 'System Health' 'Pending Reboot' 'failed' 'high' "Reboot pending: $($pendingReasons -join ', ')." 'Resolve pending reboot before upgrade.'
    } else {
        Add-Check 'pending-reboot' 'System Health' 'Pending Reboot' 'passed' 'low' 'No pending reboot detected.' ''
    }
} catch {
    Add-Check 'pending-reboot' 'System Health' 'Pending Reboot' 'skipped' 'low' "Could not evaluate pending reboot: $($_.Exception.Message)" ''
}

# 6. PowerShell version
try {
    $psv = $PSVersionTable.PSVersion
    if ($psv.Major -ge 5) {
        Add-Check 'powershell-version' 'System Health' 'PowerShell Version' 'passed' 'low' "PowerShell $($psv.ToString())." ''
    } else {
        Add-Check 'powershell-version' 'System Health' 'PowerShell Version' 'warning' 'low' "PowerShell $($psv.ToString())." 'Upgrade to Windows PowerShell 5.1.'
    }
} catch {
    Add-Check 'powershell-version' 'System Health' 'PowerShell Version' 'skipped' 'low' 'Could not read PowerShell version.' ''
}

# 7. .NET Framework detection
try {
    $rel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release
    $netVer = if ($rel -ge 528040) { '4.8 or later' } elseif ($rel -ge 461808) { '4.7.2' } elseif ($rel -ge 460798) { '4.7' } else { 'earlier than 4.7' }
    if ($rel -ge 461808) {
        Add-Check 'dotnet-runtime' 'System Health' '.NET Framework' 'passed' 'low' ".NET Framework $netVer (release $rel)." ''
    } else {
        Add-Check 'dotnet-runtime' 'System Health' '.NET Framework' 'warning' 'low' ".NET Framework $netVer (release $rel)." 'Install .NET Framework 4.7.2 or later before upgrade.'
    }
} catch {
    Add-Check 'dotnet-runtime' 'System Health' '.NET Framework' 'skipped' 'low' "Could not detect .NET Framework: $($_.Exception.Message)" ''
}

# ==========================================================================
# NETWORK READINESS
# ==========================================================================
$sqlConfigured = -not [string]::IsNullOrWhiteSpace($SqlServer)
$instanceGiven = -not [string]::IsNullOrWhiteSpace($SqlInstance)
if ($instanceGiven) { $dataSource = "$SqlServer\$SqlInstance" } else { $dataSource = "$SqlServer,$SqlPort" }

# 8. DNS resolution (critical)
if ($sqlConfigured) {
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($SqlServer) | ForEach-Object { $_.IPAddressToString }
        Add-Check 'sql-dns-resolution' 'Network Readiness' 'DNS Resolution' 'passed' 'critical' "$SqlServer resolves to $($ips -join ', ')." ''
    } catch {
        Add-Check 'sql-dns-resolution' 'Network Readiness' 'DNS Resolution' 'failed' 'critical' "Could not resolve $SqlServer: $($_.Exception.Message)" 'Verify the SQL Server hostname and DNS configuration on the Veeam ONE server.'
    }
} else {
    Add-Check 'sql-dns-resolution' 'Network Readiness' 'DNS Resolution' 'skipped' 'critical' 'No SQL Server specified.' ''
}

# 9. TCP connectivity to SQL port (critical)
$tcpOk = $false
if ($sqlConfigured) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($SqlServer, $SqlPort, $null, $null)
        $reached = $iar.AsyncWaitHandle.WaitOne(5000, $false)
        if ($reached -and $client.Connected) {
            $client.EndConnect($iar)
            $tcpOk = $true
            Add-Check 'sql-port-connectivity' 'Network Readiness' 'SQL Port Connectivity' 'passed' 'critical' "TCP $($SqlServer):$SqlPort is reachable." ''
        } else {
            Add-Check 'sql-port-connectivity' 'Network Readiness' 'SQL Port Connectivity' 'failed' 'critical' "TCP $($SqlServer):$SqlPort not reachable within 5s." "Open TCP port $SqlPort from the Veeam ONE server to the SQL Server."
        }
        $client.Close()
    } catch {
        Add-Check 'sql-port-connectivity' 'Network Readiness' 'SQL Port Connectivity' 'failed' 'critical' "TCP connect error: $($_.Exception.Message)" "Open TCP port $SqlPort from the Veeam ONE server to the SQL Server."
    }
} else {
    Add-Check 'sql-port-connectivity' 'Network Readiness' 'SQL Port Connectivity' 'skipped' 'critical' 'No SQL Server specified.' ''
}

# 10. Basic latency test
if ($tcpOk) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $c2 = New-Object System.Net.Sockets.TcpClient
        $c2.Connect($SqlServer, $SqlPort)
        $sw.Stop()
        $c2.Close()
        $ms = $sw.ElapsedMilliseconds
        if ($ms -le 50) {
            Add-Check 'sql-latency' 'Network Readiness' 'SQL Latency' 'passed' 'low' "TCP connect latency: $($ms) ms." ''
        } elseif ($ms -le 200) {
            Add-Check 'sql-latency' 'Network Readiness' 'SQL Latency' 'warning' 'medium' "TCP connect latency: $($ms) ms (elevated)." 'Investigate the network path between the Veeam ONE server and SQL Server.'
        } else {
            Add-Check 'sql-latency' 'Network Readiness' 'SQL Latency' 'failed' 'medium' "TCP connect latency: $($ms) ms (high)." 'High latency can degrade Veeam ONE; investigate the network path.'
        }
    } catch {
        Add-Check 'sql-latency' 'Network Readiness' 'SQL Latency' 'skipped' 'low' "Latency not measured: $($_.Exception.Message)" ''
    }
} else {
    Add-Check 'sql-latency' 'Network Readiness' 'SQL Latency' 'skipped' 'low' 'Skipped - no TCP connectivity.' ''
}

# ==========================================================================
# SQL READINESS (Windows authentication only)
# ==========================================================================
function New-ConnString([string]$Db = $DatabaseName) {
    return "Server=$dataSource;Database=$Db;Integrated Security=SSPI;Encrypt=False;TrustServerCertificate=True;Connect Timeout=10;Application Name=VeeamOnePreUpgradeReadiness;"
}
function Invoke-Scalar([string]$ConnString, [string]$Query) {
    $cn = New-Object System.Data.SqlClient.SqlConnection $ConnString
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 15
        return $cmd.ExecuteScalar()
    } finally { $cn.Close() }
}

# 11. Named instance warning
if ($instanceGiven) {
    Add-Check 'sql-named-instance' 'SQL Readiness' 'Named Instance' 'warning' 'low' "Named instance '$SqlInstance' specified; resolution relies on SQL Browser (UDP 1434) unless a static port is configured." 'Verify the instance name and listening port; ensure SQL Browser is running or use a static port.'
} else {
    Add-Check 'sql-named-instance' 'SQL Readiness' 'Named Instance' 'skipped' 'info' 'Default instance / explicit port in use.' ''
}

# 12. SQL connection (Windows auth, critical)
$connectOk = $false
if ($sqlConfigured) {
    try {
        Invoke-Scalar (New-ConnString 'master') 'SELECT 1' | Out-Null
        $connectOk = $true
        Add-Check 'sql-connection' 'SQL Readiness' 'SQL Connection' 'passed' 'critical' "Connected to $dataSource using Windows authentication." ''
    } catch {
        Add-Check 'sql-connection' 'SQL Readiness' 'SQL Connection' 'failed' 'critical' "Connection failed: $($_.Exception.Message)" 'Verify the Veeam ONE service account has access and the SQL Server service is running.'
    }
} else {
    Add-Check 'sql-connection' 'SQL Readiness' 'SQL Connection' 'skipped' 'critical' 'No SQL Server specified.' ''
}

# 13. Database existence (critical)
$dbOk = $false
if ($connectOk) {
    try {
        $dbEsc = $DatabaseName -replace "'", "''"
        $dbid = Invoke-Scalar (New-ConnString 'master') "SELECT DB_ID(N'$dbEsc')"
        if ($null -ne $dbid -and $dbid -isnot [System.DBNull]) {
            $dbOk = $true
            Add-Check 'database-existence' 'SQL Readiness' 'Database Existence' 'passed' 'critical' "Database '$DatabaseName' is present (db_id=$dbid)." ''
        } else {
            Add-Check 'database-existence' 'SQL Readiness' 'Database Existence' 'failed' 'critical' "Database '$DatabaseName' was not found." 'Confirm the Veeam ONE database name; the default is VeeamONE.'
        }
    } catch {
        Add-Check 'database-existence' 'SQL Readiness' 'Database Existence' 'failed' 'critical' "Lookup error: $($_.Exception.Message)" 'Confirm the database name and the account permissions.'
    }
} else {
    Add-Check 'database-existence' 'SQL Readiness' 'Database Existence' 'skipped' 'critical' 'Skipped - no SQL connection.' ''
}

# 14/15. SQL version and edition
$edition = ''
if ($connectOk) {
    try {
        $version = [string](Invoke-Scalar (New-ConnString 'master') "SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(128)) + ' (' + CAST(SERVERPROPERTY('ProductLevel') AS varchar(128)) + ')'")
        Add-Check 'sql-version' 'SQL Readiness' 'SQL Version' 'passed' 'info' "SQL Server version $version." ''
    } catch {
        Add-Check 'sql-version' 'SQL Readiness' 'SQL Version' 'skipped' 'info' "Could not read version: $($_.Exception.Message)" ''
    }
    try {
        $edition = [string](Invoke-Scalar (New-ConnString 'master') "SELECT CAST(SERVERPROPERTY('Edition') AS varchar(128))")
        Add-Check 'sql-edition' 'SQL Readiness' 'SQL Edition' 'passed' 'info' "$edition." ''
    } catch {
        Add-Check 'sql-edition' 'SQL Readiness' 'SQL Edition' 'skipped' 'info' "Could not read edition: $($_.Exception.Message)" ''
    }
} else {
    Add-Check 'sql-version' 'SQL Readiness' 'SQL Version' 'skipped' 'info' 'Skipped - no SQL connection.' ''
    Add-Check 'sql-edition' 'SQL Readiness' 'SQL Edition' 'skipped' 'info' 'Skipped - no SQL connection.' ''
}

# 16. SQL Express size warning (over 8 GB)
if ($connectOk -and $dbOk) {
    try {
        if ($edition -match 'Express') {
            $dbEsc = $DatabaseName -replace "'", "''"
            $sizeMB = Invoke-Scalar (New-ConnString 'master') "SELECT CAST(SUM(size) * 8.0 / 1024 AS decimal(18,1)) FROM sys.master_files WHERE database_id = DB_ID(N'$dbEsc') AND type = 0"
            if ($null -eq $sizeMB -or $sizeMB -is [System.DBNull]) { $sizeMB = 0 }
            $sizeGB = [math]::Round([double]$sizeMB / 1024, 2)
            if ($sizeGB -ge 8) {
                Add-Check 'sql-express-size' 'SQL Readiness' 'SQL Express Size' 'warning' 'medium' "Express data size is $($sizeGB) GB (10 GB limit)." 'SQL Express database is close to the 10 GB limit. Consider moving to SQL Standard or Enterprise before upgrade.'
            } else {
                Add-Check 'sql-express-size' 'SQL Readiness' 'SQL Express Size' 'passed' 'medium' "Express data size is $($sizeGB) GB, within limits." ''
            }
        } else {
            Add-Check 'sql-express-size' 'SQL Readiness' 'SQL Express Size' 'skipped' 'info' "Edition '$edition' has no 10 GB cap." ''
        }
    } catch {
        Add-Check 'sql-express-size' 'SQL Readiness' 'SQL Express Size' 'skipped' 'medium' "Could not read database size: $($_.Exception.Message)" ''
    }
} else {
    Add-Check 'sql-express-size' 'SQL Readiness' 'SQL Express Size' 'skipped' 'medium' 'Skipped - database not reachable.' ''
}

# 17. SQL metadata read permission
if ($dbOk) {
    try {
        $objCount = Invoke-Scalar (New-ConnString) 'SELECT COUNT(*) FROM sys.objects'
        Add-Check 'sql-metadata-permission' 'SQL Readiness' 'Metadata Read Permission' 'passed' 'high' "Account can read metadata in '$DatabaseName' ($objCount objects visible)." ''
    } catch {
        Add-Check 'sql-metadata-permission' 'SQL Readiness' 'Metadata Read Permission' 'failed' 'high' "Metadata read failed: $($_.Exception.Message)" 'Verify the Veeam ONE service account has required SQL database access (db_datareader / VIEW DEFINITION).'
    }
} else {
    Add-Check 'sql-metadata-permission' 'SQL Readiness' 'Metadata Read Permission' 'skipped' 'high' 'Skipped - database not reachable.' ''
}

# ==========================================================================
# VEEAM SERVICES
# ==========================================================================
$veeamServices = @(
    @{ id = 'veeam-one-monitoring';       name = 'Veeam ONE Monitoring Service' },
    @{ id = 'veeam-one-reporting';        name = 'Veeam ONE Reporting Service' },
    @{ id = 'veeam-one-agent';            name = 'Veeam ONE Agent' },
    @{ id = 'veeam-one-error-reporting';  name = 'Veeam ONE Error Reporting Service' }
)
foreach ($svcDef in $veeamServices) {
    try {
        $svc = Get-Service -DisplayName $svcDef.name -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            Add-Check $svcDef.id 'Veeam Services' $svcDef.name 'passed' 'medium' 'Service is installed and running.' ''
        } else {
            Add-Check $svcDef.id 'Veeam Services' $svcDef.name 'warning' 'medium' "Service is installed but $($svc.Status)." 'Start the service or confirm its expected state before upgrade.'
        }
    } catch {
        Add-Check $svcDef.id 'Veeam Services' $svcDef.name 'skipped' 'info' 'Service not found on this host.' 'If this host is the Veeam ONE server, verify the installation.'
    }
}

# ==========================================================================
# SUMMARY (the browser recomputes this authoritatively on upload)
# ==========================================================================
$criticalIds = @('sql-dns-resolution', 'sql-port-connectivity', 'sql-connection', 'database-existence')
$deduction = 0
$hasWarning = $false
foreach ($c in $script:Checks) {
    if ($c.status -eq 'failed') {
        switch ($c.severity) {
            'critical' { $deduction += 25 }
            'high'     { $deduction += 15 }
            'medium'   { $deduction += 10 }
            'low'      { $deduction += 5 }
            default    { $deduction += 0 }
        }
    } elseif ($c.status -eq 'warning') {
        $deduction += 5
        $hasWarning = $true
    }
}
$score = [math]::Max(0, 100 - $deduction)
$criticalFail = @($script:Checks | Where-Object { ($criticalIds -contains $_.id) -and $_.status -eq 'failed' })
if ($criticalFail.Count -gt 0 -or $score -lt 60) { $overall = 'Not Ready' }
elseif ($score -lt 85 -or $hasWarning) { $overall = 'Warning' }
else { $overall = 'Ready' }

$topIssues = @($script:Checks |
    Where-Object { $_.status -eq 'failed' -or $_.status -eq 'warning' } |
    Select-Object -First 5 |
    ForEach-Object { if ($_.recommendation) { "$($_.name) - $($_.recommendation)" } else { $_.name } })

$result = [ordered]@{
    product        = 'Veeam ONE'
    action         = 'Pre-Upgrade'
    timestamp      = (Get-Date).ToUniversalTime().ToString('o')
    currentVersion = $CurrentVersion
    targetVersion  = $TargetVersion
    target         = [ordered]@{
        computerName = $env:COMPUTERNAME
        sqlServer    = $SqlServer
        sqlInstance  = $SqlInstance
        database     = $DatabaseName
        port         = $SqlPort
    }
    checks         = @($script:Checks)
    summary        = [ordered]@{
        score     = $score
        status    = $overall
        topIssues = $topIssues
    }
}

# REVIEW this JSON before sharing - it describes your infrastructure.
# Nothing is uploaded automatically; only this local file is written.
$json = $result | ConvertTo-Json -Depth 6
$json | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "Saved readiness result to $OutputPath. Review it before sharing."
