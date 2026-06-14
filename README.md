# Veeam ONE Health Check & Troubleshooting Assistant

A frontend-first Next.js tool plus a reusable PowerShell collector for **Veeam
ONE health checks, troubleshooting, and upgrade readiness**. The browser
generates the script, you run it locally on the target server, and then you can
review the JSON report in the UI or keep the locally exported JSON/HTML/CSV
files.

This project is intentionally **read-only**. It does not upload anything, does
not execute remediation, and does not collect passwords or secrets.

> Unofficial open-source helper tool. It is not an official Veeam support tool
> unless explicitly owned or approved by Veeam. Review output before sharing or
> acting on it.

## What It Checks

The current major version expands the old upgrade-only workflow into a modular
assistant:

- Upgrade readiness
  - OS version
  - CPU / RAM
  - Disk space
  - Installed Veeam ONE version
  - SQL Server version / edition
  - SQL connectivity
  - .NET version
  - Service account visibility
  - Upgrade blockers and warnings
- Veeam ONE services health
  - Monitoring, Reporting, Agent, Error Reporting
  - Status, startup type, PID, last start time when available
- SQL / database health
  - Instance, edition, version, compatibility level, recovery model
  - Database size, log size, free space, growth warnings
  - SQL Express 10 GB risk
- Collection health
  - Failed collectors
  - Object Properties issues
  - Performance collection issues
  - Last success / failure timestamps when available
- Alarm health
  - Total, active, disabled, warning / error alarms
  - Recently triggered alarms
  - Highlighting for malware, backup, repository, infrastructure, SQL and collector alarms
- Port checks
  - SQL target
  - Discovered targets when available
  - Manually supplied targets and ports
- Log analyzer
  - SQL connection failures
  - Named Pipes Provider error 40
  - Login failed
  - Timeout expired
  - Could not allocate a new page
  - Database full
  - Collector and Object Properties failures
  - Malware, TLS / certificate, access denied and service crash patterns
- Architecture / sizing guidance
  - Conservative non-official guidance using VM, host and repository inputs
- Best-practice health score
  - 0-100 score with PASS / WARNING / FAIL / INFO output

## PowerShell Modes

The script keeps the existing upgrade readiness checks and adds broader health
modules.

Default:

```powershell
.\VeeamOnePreUpgradeReadiness.ps1
```

This now performs a **full health check**.

Examples:

```powershell
.\VeeamOnePreUpgradeReadiness.ps1 -Mode Upgrade -SqlServer "sql01" -DatabaseName "VeeamONE"
.\VeeamOnePreUpgradeReadiness.ps1 -Mode Health -SqlServer "sql01\VEEAMSQL"
.\VeeamOnePreUpgradeReadiness.ps1 -Mode Full -ExportHtml ".\report.html" -ExportCsv ".\report.csv"
.\VeeamOnePreUpgradeReadiness.ps1 -AnalyzeLogs -LogPath "C:\ProgramData\Veeam\Veeam ONE Monitor\Logs"
.\VeeamOnePreUpgradeReadiness.ps1 -CheckPorts -Target "server.domain.local" -Port 1433
.\VeeamOnePreUpgradeReadiness.ps1 -ValidateSizing -VMCount 1000 -HostCount 20 -RepositoryTB 500
```

Available export parameters:

```powershell
-ExportJson ".\VeeamOneHealthReport.json"
-ExportHtml ".\VeeamOneHealthReport.html"
-ExportCsv ".\VeeamOneHealthReport.csv"
```

## Repository Structure

```text
app/
  readiness-checker/page.tsx   Main browser workflow
components/readiness/
  ReadinessForm.tsx            Script generator form
  ScriptGenerator.tsx          PowerShell template rendering
  JsonUploader.tsx             Upload and normalize report JSON
  ScoreCard.tsx                Health score and status
  SupportSummary.tsx           Copy/export UI helpers
lib/readiness/
  parser.ts                    Report validation and normalization
  scoring.ts                   Health score computation
  reportExport.ts              JSON / Markdown / HTML / CSV browser exports
  rules/veeam-one-pre-upgrade.json
public/scripts/
  VeeamOnePreUpgradeReadiness.ps1
public/samples/
  sample-ready.json
  sample-warning.json
  sample-not-ready.json
public/samples/logs/
  veeamone-known-issues.log
```

## Browser Flow

1. Open `/readiness-checker`.
2. Generate the PowerShell script.
3. Run it on the Veeam ONE server or a host with the same SQL network path.
4. Upload the JSON result into the browser.
5. Review the score, category results, blockers, recommendations and exports.

The browser app now supports export of the uploaded normalized report as:

- JSON
- Markdown
- HTML
- CSV

## Reports

The PowerShell script can export:

- JSON
- HTML
- CSV

The HTML report includes:

- Summary
- Health score
- Upgrade readiness
- Services health
- SQL / database health
- Collection health
- Alarm health
- Port checks
- Log findings
- Recommendations

## Sample Output / Demo Data

The repository includes sample JSON uploads and sample log content:

- `public/samples/sample-ready.json`
- `public/samples/sample-warning.json`
- `public/samples/sample-not-ready.json`
- `public/samples/logs/veeamone-known-issues.log`

The sample log file is useful for validating the log-analyzer pattern rules and
for demonstrating known issue detection without a live Veeam ONE environment.

## Running Locally

```bash
npm install
npm run dev
```

Open:

```text
http://localhost:3000/readiness-checker
```

## Testing

Frontend / TypeScript tests:

```bash
npm test
```

Suggested PowerShell validation on a Windows host with PowerShell available:

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content .\public\scripts\VeeamOnePreUpgradeReadiness.ps1 -Raw), [ref]$null)
```

If PSScriptAnalyzer is installed:

```powershell
Invoke-ScriptAnalyzer -Path .\public\scripts\VeeamOnePreUpgradeReadiness.ps1
```

## Compatibility

- Targeted for **Windows PowerShell 5.1**
- Basic checks do not require admin rights
- If elevation is needed for a detail, the script should warn instead of crashing
- SQL and Veeam ONE absence should degrade gracefully instead of terminating

## SEO Keywords

- Veeam ONE health check
- Veeam ONE troubleshooting
- Veeam ONE SQL Express database full
- Veeam ONE collector task failed
- Veeam ONE upgrade readiness
- Veeam ONE log analyzer

## Disclaimer

This repository is an **unofficial open-source helper tool** for diagnostics and
readiness review. It does not replace official Veeam documentation, support
guidance or supportability statements.
