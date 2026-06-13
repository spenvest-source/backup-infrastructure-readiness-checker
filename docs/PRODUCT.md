# Backup Infrastructure Readiness Checker — Product Documentation

> ⚠️ **Unofficial readiness tool.** It does not replace vendor documentation or
> official support guidance. Review all output before sharing.

## 1. Overview

The **Backup Infrastructure Readiness Checker** is a browser-based tool that
helps administrators validate infrastructure **before** a Veeam-related
installation or upgrade. It turns a set of manual pre-flight checks into a
repeatable, scored readiness report.

It is **frontend-only**: a Next.js app that runs entirely in the browser. There
is no backend, no database, no account, and nothing is transmitted to any
server. The only component that touches the target infrastructure is a
PowerShell script the user runs themselves.

**MVP scope:** *Veeam ONE — Pre-Upgrade Readiness*. The design is modular so
additional products/actions can be added (see [Roadmap](#9-roadmap)).

## 2. Who it is for

- Backup/infrastructure administrators planning a Veeam ONE upgrade.
- Pre-sales / professional-services engineers running a readiness pass.
- Support engineers who want a structured summary of a customer environment.

## 3. Key concepts

| Concept | Meaning |
| --- | --- |
| **Product** | The software being validated (MVP: Veeam ONE). |
| **Action** | The lifecycle event being prepared for (MVP: Pre-Upgrade). |
| **Check** | A single read-only validation with a status and severity. |
| **Category** | A grouping of checks: System Health, Network Readiness, SQL Readiness, Veeam Services. |
| **Rule set** | A JSON file defining a product/action's categories and which checks are upgrade-critical. |
| **Readiness report** | The scored result rendered after a JSON result is uploaded. |

## 4. How it works

1. The user opens `/readiness-checker` and selects **Veeam ONE / Pre-Upgrade**,
   then enters the target details (current/target version, SQL Server, optional
   instance, database name, SQL port).
2. The app generates a **PowerShell script** by loading a template and replacing
   placeholders (`{{CURRENT_VERSION}}`, `{{TARGET_VERSION}}`, `{{SQL_SERVER}}`,
   `{{SQL_INSTANCE}}`, `{{DATABASE_NAME}}`, `{{SQL_PORT}}`).
3. The user **copies or downloads** the script and runs it **on the Veeam ONE
   server** (or a host with the same network path to SQL). The script writes a
   sanitized JSON result to a local file — it uploads nothing.
4. The user **uploads** that JSON back into the browser. The app validates the
   schema, **recomputes the score authoritatively**, and renders the report.
5. The user can **copy a support summary**, or **export** the normalized report
   as JSON or Markdown.

```
Browser (Next.js)                      Veeam ONE server
┌──────────────────────┐               ┌───────────────────────────┐
│ form → generate .ps1 │── download ──▶│ run VeeamOnePreUpgrade...  │
│                      │               │   → writes result.json     │
│ upload result.json  ◀│── user file ──│   (local only, no upload)  │
│ validate + score     │               └───────────────────────────┘
│ → readiness report   │
└──────────────────────┘
```

## 5. The checks

The PowerShell script runs 20 read-only checks across four categories. Each
emits `{ id, category, name, status, severity, evidence, recommendation }`.

### System Health
| id | Check | Severity | Validates |
| --- | --- | --- | --- |
| `os-version` | OS Version | info | OS caption and build number |
| `cpu-count` | CPU Cores | medium | Logical processor count (≥4 recommended) |
| `ram-amount` | Memory (RAM) | medium | Physical memory (≥8 GB recommended) |
| `disk-free-system` | System Drive Free Space | high | Free space on the system drive |
| `pending-reboot` | Pending Reboot | high | CBS / Windows Update / pending file-rename flags |
| `powershell-version` | PowerShell Version | low | Windows PowerShell ≥ 5.1 |
| `dotnet-runtime` | .NET Framework | low | .NET Framework ≥ 4.7.2 |

### Network Readiness
| id | Check | Severity | Validates |
| --- | --- | --- | --- |
| `sql-dns-resolution` | DNS Resolution | critical | SQL Server hostname resolves |
| `sql-port-connectivity` | SQL Port Connectivity | critical | TCP reachability to the SQL port |
| `sql-latency` | SQL Latency | low/medium | TCP round-trip latency to SQL |

### SQL Readiness
| id | Check | Severity | Validates |
| --- | --- | --- | --- |
| `sql-named-instance` | Named Instance | low | Warns when a named instance relies on SQL Browser |
| `sql-connection` | SQL Connection | critical | Connect using Windows authentication |
| `database-existence` | Database Existence | critical | The Veeam ONE database exists |
| `sql-version` | SQL Version | info | SQL Server product version/level |
| `sql-edition` | SQL Edition | info | SQL Server edition |
| `sql-express-size` | SQL Express Size | medium | Warns if an Express DB is over 8 GB (10 GB cap) |
| `sql-metadata-permission` | Metadata Read Permission | high | Account can read database metadata |

### Veeam Services
| id | Check | Severity | Validates |
| --- | --- | --- | --- |
| `veeam-one-monitoring` | Veeam ONE Monitoring Service | medium | Service installed and running |
| `veeam-one-reporting` | Veeam ONE Reporting Service | medium | Service installed and running |
| `veeam-one-agent` | Veeam ONE Agent | medium | Service installed and running |
| `veeam-one-error-reporting` | Veeam ONE Error Reporting Service | medium | Service installed and running |

**Critical checks** (a failure makes the environment **Not Ready**), defined in
`lib/readiness/rules/veeam-one-pre-upgrade.json`:
`sql-dns-resolution`, `sql-port-connectivity`, `sql-connection`,
`database-existence`.

## 6. Scoring model

The score is recomputed in the browser from the raw checks; any `summary` in the
uploaded file is ignored (so it cannot be tampered with to inflate the result).

- **Start** at 100.
- **Deduct** per check:
  - Failed: critical −25, high −15, medium −10, low −5, info 0
  - Warning: −5
  - Skipped / Passed: 0
- **Clamp** to a minimum of 0.

**Overall status:**
- **Ready** — score ≥ 85, no critical-check failures, no warnings
- **Warning** — score 60–84, or any warnings present
- **Not Ready** — score < 60, or any critical-check failure

**Category scores** apply the same start-at-100-and-deduct method to the checks
within each category, giving a per-area readout.

## 7. Report & outputs

The readiness report shows: overall score, status badge (Ready / Warning / Not
Ready), the four category scores, upgrade blockers, recommendations, and the
full check-results table (Category, Check Name, Status, Severity, Evidence,
Recommendation). Badge colours: passed = green, warning = amber, failed/critical
= red, skipped = gray.

Outputs:
- **Copy Support Summary** — plain-text summary for a ticket or email.
- **Export Report as JSON** — the normalized report.
- **Export Report as Markdown** — a shareable Markdown document.

## 8. Security & privacy

- The PowerShell script collects and outputs **no passwords, secrets, or
  tokens**, and uses **Windows authentication only** for SQL checks.
- The script writes JSON to a **local file** and **uploads nothing**.
- JSON parsing, validation and scoring happen **entirely in the browser**; no
  data leaves the user's machine via this tool.
- Result files describe customer infrastructure — **review before sharing**.

## 9. Roadmap

**Current:** Veeam ONE Pre-Upgrade.

**Planned:** VBR Pre-Upgrade · VB365 Pre-Install · VB365 Object Storage
Validation · VBR Repository Validation · Microsoft 365 Permission Validation ·
VMware/vCenter Connectivity Validation.

A new product/action is added by supplying a rule set
(`lib/readiness/rules/*.json`), a PowerShell template
(`public/scripts/*.ps1`), and selector options — the scoring engine, parser,
exporters and report UI are generic over the rule set.

## 10. Disclaimer

This is an **unofficial** diagnostic/readiness tool. It is not affiliated with,
endorsed by, or supported by Veeam, and does not replace official documentation
or support.
