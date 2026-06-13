# Backup Infrastructure Readiness Checker

A **frontend-only** (Next.js 15) browser tool that helps validate infrastructure
before a Veeam-related installation or upgrade. It generates a PowerShell
diagnostic script, you run it on the target server, then upload the resulting
JSON to see a scored readiness report — all in the browser. **No backend, no
database, no authentication, nothing is uploaded anywhere.**

**MVP scope:** *Veeam ONE — Pre-Upgrade Readiness*. Built modular for future
products (see `/roadmap`).

> ⚠️ **Unofficial readiness tool.** It does not replace vendor documentation or
> official support guidance. Review output before sharing.

## Documentation

Product documentation (features, full check catalog, scoring model, security):
[docs/PRODUCT.md](docs/PRODUCT.md).

## Stack

- Next.js 15 (App Router) · TypeScript · Tailwind CSS
- Vitest for unit tests
- All logic in `lib/readiness/` (no scoring/requirements hardcoded in components)

## Project structure

```
app/
  readiness-checker/page.tsx   main page (the full flow)
  roadmap/page.tsx             current + planned products
  layout.tsx, page.tsx         shell + redirect / -> /readiness-checker
components/readiness/          ReadinessForm, ScriptGenerator, JsonUploader,
                               ScoreCard, CategoryScores, UpgradeBlockers,
                               CheckResultsTable, Recommendations, SupportSummary
lib/readiness/
  types.ts  scoring.ts  parser.ts  reportExport.ts
  rules/veeam-one-pre-upgrade.json     categories + criticalCheckIds
  __tests__/                           vitest unit tests
public/
  scripts/VeeamOnePreUpgradeReadiness.ps1   template with {{PLACEHOLDERS}}
  samples/sample-{ready,warning,not-ready}.json
```

## Run the app

```bash
npm install
npm run dev      # http://localhost:3000  (redirects to /readiness-checker)
# production:
npm run build && npm start
```

Open **http://localhost:3000/readiness-checker**.

## How it works

1. On `/readiness-checker`, choose Veeam ONE / Pre-Upgrade and enter the target
   details (current/target version, SQL Server, optional instance, database,
   port).
2. Click **Generate PowerShell Script**. The app loads
   `public/scripts/VeeamOnePreUpgradeReadiness.ps1` and replaces the
   `{{CURRENT_VERSION}}`, `{{TARGET_VERSION}}`, `{{SQL_SERVER}}`,
   `{{SQL_INSTANCE}}`, `{{DATABASE_NAME}}`, `{{SQL_PORT}}` placeholders.
3. **Copy Script** or **Download Script**.
4. Run it **on the Veeam ONE server** (or a host with the same network path to
   SQL):
   ```powershell
   .\VeeamOnePreUpgradeReadiness.ps1 -SqlServer sql01 -CurrentVersion 11.0 -TargetVersion 12.1
   # writes .\veeamone-readiness-result.json
   ```
5. Back in the browser, **Upload JSON Result**. The app validates the schema,
   recomputes the score, and renders the report: overall score, status badge
   (Ready / Warning / Not Ready), category scores, upgrade blockers,
   recommendations, and the full check-results table.
6. **Copy Support Summary**, **Export Report as JSON**, or **Export Report as
   Markdown**.

## Test with the sample files

No server needed — use the bundled samples:

- On `/readiness-checker`, in step 3 click a sample link
  (`sample-ready.json`, `sample-warning.json`, `sample-not-ready.json`), or
  upload one from `public/samples/`.
- Expected: **Ready / 100**, **Warning / 85**, **Not Ready / 65**.

## Scoring

Start at 100, deduct: failed critical −25 / high −15 / medium −10 / low −5,
warning −5, skipped 0 (min 0). Status: **Ready** ≥ 85 (no critical failures, no
warnings) · **Warning** 60–84 or any warning · **Not Ready** < 60 or any
critical-check failure. Critical checks (from
`lib/readiness/rules/veeam-one-pre-upgrade.json`): `sql-dns-resolution`,
`sql-port-connectivity`, `sql-connection`, `database-existence`.

## Deployment (GitLab Pages)

`.gitlab-ci.yml` builds the static export and publishes it to GitLab Pages on
every push to `main`. The build sets `NEXT_PUBLIC_BASE_PATH=/$CI_PROJECT_NAME`
so assets resolve from the project subpath.

Public URL (after the `pages` pipeline succeeds):
**https://backup-health-checker.gitlab.io/backup-infrastructure-readiness-checker/**

> For that exact URL, **Settings → Pages → "Use unique domain" must be OFF**.
> If it is ON, GitLab serves Pages at a random `*.gitlab.io` root instead — in
> that case set `NEXT_PUBLIC_BASE_PATH: ""` in `.gitlab-ci.yml` and use the URL
> shown under **Deploy → Pages**. GitLab.com also requires CI shared runners to
> be enabled for the namespace.

## Run the tests

```bash
npm test     # vitest: scoring, parser/validation, markdown export, status calc
```

## Security

- No passwords, secrets or tokens are collected, output, or stored.
- The PowerShell script uses Windows authentication only and writes JSON to a
  **local file** — it never uploads anything.
- JSON parsing happens entirely in your browser. Result files describe your
  infrastructure — review before sharing.

## Disclaimer

This is an **unofficial** diagnostic/readiness tool. It is not affiliated with,
endorsed by, or supported by Veeam, and does not replace official documentation
or support.
