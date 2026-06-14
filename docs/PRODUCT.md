# Veeam ONE Health Check & Troubleshooting Assistant — Product Documentation

> Unofficial open-source helper tool. It does not replace vendor documentation
> or official support guidance.

## Overview

This repository has moved beyond a single pre-upgrade script. It now provides a
modular **Veeam ONE Health Check & Troubleshooting Assistant** with two main
parts:

- A browser UI that generates the PowerShell script and renders uploaded JSON
  reports.
- A Windows PowerShell 5.1 compatible script that performs health,
  troubleshooting and upgrade-readiness checks locally.

## Core Design Goals

- Keep the original upgrade readiness coverage intact
- Add broader health and troubleshooting modules
- Stay read-only
- Avoid crashing when Veeam ONE or SQL are missing
- Produce structured machine-readable and human-readable reports

## Modules

### Upgrade Readiness

- OS version
- CPU / RAM
- Disk free space
- Installed Veeam ONE version
- SQL connectivity
- SQL version / edition
- .NET Framework
- Pending reboot
- Service account visibility

### Services Health

- Monitoring Service
- Reporting Service
- Agent
- Error Reporting Service

Each service attempts to report:

- Exists / missing
- Status
- Startup type
- PID
- Last start time when available
- Recommendation if stopped or disabled

### SQL / Database Health

- SQL target availability
- Database existence
- SQL edition and version
- Compatibility level
- Recovery model
- Database size
- Log file size
- Free space
- SQL Express 10 GB risk
- Growth warnings

### Collection Health

Where version-specific tables are available, the script attempts to report:

- Failed collector tasks
- Object Properties collection failures
- Performance collection failures
- Last success time
- Last failure time
- Failure count

If the target version exposes different schemas, the check is marked as
unsupported instead of crashing.

### Alarm Health

- Total alarms
- Active alarms
- Disabled alarms
- Warning / error alarms
- Recently triggered alarms
- Highlighting of malware, backup, repository, infrastructure, SQL and collector-related alarms

### Port Checks

- SQL connectivity
- Discovered infrastructure targets when available
- Manually supplied target / port combinations

### Log Analyzer

Known issue patterns include:

- Named Pipes Provider error 40
- Login failed
- Timeout expired
- Could not allocate a new page
- Database full
- Collector task failed
- Object Properties failure
- Malware detection
- TLS / certificate errors
- Access denied
- Service crash

### Architecture / Sizing Guidance

Optional workload guidance for:

- VM count
- Host count
- Repository size

This section is intentionally conservative and clearly marked as non-official
guidance.

## Reports

The script can export:

- JSON
- HTML
- CSV

The browser app can export the uploaded normalized report as:

- JSON
- Markdown
- HTML
- CSV

## Scoring

The overall score remains 0-100 and is still check-driven so the original
workflow remains compatible. Failures and warnings are weighted by severity and
the browser recomputes the authoritative score after upload.

## Compatibility

- Windows PowerShell 5.1 target
- Basic checks should work without admin rights
- Reduced visibility should become a warning, not a terminating error

## Sample Assets

- `public/samples/sample-ready.json`
- `public/samples/sample-warning.json`
- `public/samples/sample-not-ready.json`
- `public/samples/logs/veeamone-known-issues.log`

## Disclaimer

This project is an **unofficial open-source helper tool**. It is not a support
statement, not an official compatibility matrix, and not a replacement for
vendor documentation or escalation guidance.
