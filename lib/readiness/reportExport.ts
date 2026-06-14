import type { NormalizedReport } from "./types";

/** Export the normalized report (incl. authoritative summary) as pretty JSON. */
export function exportJson(report: NormalizedReport): string {
  const { outcome, ...rest } = report;
  // Persist the user-facing report shape; `outcome` is derived/internal.
  void outcome;
  return JSON.stringify(rest, null, 2);
}

/** A plain-text support summary suitable for pasting into a ticket/email. */
export function buildSupportSummary(report: NormalizedReport): string {
  const { summary, outcome, target, checks } = report;
  const lines: string[] = [];
  lines.push("Veeam ONE Health Check & Troubleshooting Assistant - Support Summary");
  lines.push("(Unofficial open-source helper tool. Review before sharing.)");
  lines.push("");
  lines.push(`Product: ${report.product}  Action: ${report.action}  Mode: ${report.mode || "Full"}`);
  lines.push(`Health: ${summary.status}   Score: ${summary.score}/100`);
  lines.push(
    `Versions: ${report.currentVersion || "?"} -> ${report.targetVersion || "?"}`
  );
  lines.push(
    `Target: ${target.sqlServer || "?"}${
      target.sqlInstance ? "\\" + target.sqlInstance : ""
    }:${target.port}  DB=${target.database || "?"}  Host=${
      target.computerName || "?"
    }`
  );
  lines.push("");
  lines.push("Category scores:");
  for (const c of outcome.categoryScores) {
    lines.push(`  - ${c.category}: ${c.score}/100`);
  }
  if (outcome.blockers.length) {
    lines.push("");
    lines.push("Upgrade blockers:");
    outcome.blockers.forEach((b) =>
      lines.push(`  - [${b.severity}] ${b.name}: ${b.evidence}`)
    );
  }
  const failed = checks.filter((c) => c.status === "failed");
  const warned = checks.filter((c) => c.status === "warning");
  if (failed.length) {
    lines.push("");
    lines.push("Failed:");
    failed.forEach((c) => lines.push(`  - [${c.severity}] ${c.name}: ${c.evidence}`));
  }
  if (warned.length) {
    lines.push("");
    lines.push("Warnings:");
    warned.forEach((c) => lines.push(`  - [${c.severity}] ${c.name}: ${c.evidence}`));
  }
  const recs = Array.from(
    new Set(checks.filter((c) => c.recommendation).map((c) => c.recommendation))
  );
  if (recs.length) {
    lines.push("");
    lines.push("Recommendations:");
    recs.forEach((r) => lines.push(`  - ${r}`));
  }
  return lines.join("\n");
}

/** Export the report as a Markdown document. */
export function exportMarkdown(report: NormalizedReport): string {
  const { summary, outcome, target, checks } = report;
  const md: string[] = [];
  md.push(`# Health Report - ${report.product} ${report.action}`);
  md.push("");
  md.push("> Unofficial open-source helper tool. Review before sharing.");
  md.push("");
  md.push(`**Status:** ${summary.status}  ·  **Score:** ${summary.score}/100`);
  md.push("");
  md.push(`- **Mode:** ${report.mode || "Full"}`);
  md.push(`- **Versions:** ${report.currentVersion || "?"} → ${report.targetVersion || "?"}`);
  md.push(
    `- **Target:** \`${target.sqlServer || "?"}${
      target.sqlInstance ? "\\" + target.sqlInstance : ""
    }:${target.port}\`  DB \`${target.database || "?"}\``
  );
  md.push(`- **Computer:** ${target.computerName || "?"}`);
  md.push(`- **Timestamp:** ${report.timestamp}`);
  md.push("");

  md.push("## Category Scores");
  md.push("");
  md.push("| Category | Score | Passed | Warning | Failed | Skipped |");
  md.push("| --- | ---: | ---: | ---: | ---: | ---: |");
  for (const c of outcome.categoryScores) {
    md.push(
      `| ${c.category} | ${c.score} | ${c.passed} | ${c.warning} | ${c.failed} | ${c.skipped} |`
    );
  }
  md.push("");

  if (outcome.blockers.length) {
    md.push("## Critical Issues");
    md.push("");
    outcome.blockers.forEach((b) =>
      md.push(`- **${b.name}** (${b.severity}) — ${b.evidence}`)
    );
    md.push("");
  }

  md.push("## Check Results");
  md.push("");
  md.push("| Category | Check | Status | Severity | Evidence | Recommendation |");
  md.push("| --- | --- | --- | --- | --- | --- |");
  for (const c of checks) {
    md.push(
      `| ${c.category} | ${c.name} | ${c.status} | ${c.severity} | ${mdCell(
        c.evidence
      )} | ${mdCell(c.recommendation)} |`
    );
  }
  md.push("");

  const recs = Array.from(
    new Set(checks.filter((c) => c.recommendation).map((c) => c.recommendation))
  );
  if (recs.length) {
    md.push("## Recommendations");
    md.push("");
    recs.forEach((r) => md.push(`- ${r}`));
    md.push("");
  }
  return md.join("\n");
}

export function exportHtml(report: NormalizedReport): string {
  const { target } = report;
  const rows = report.checks
    .map(
      (c) => `<tr>
  <td>${escapeHtml(c.category)}</td>
  <td>${escapeHtml(c.name)}</td>
  <td>${escapeHtml(c.status)}</td>
  <td>${escapeHtml(c.severity)}</td>
  <td>${escapeHtml(c.evidence || "—")}</td>
  <td>${escapeHtml(c.recommendation || "—")}</td>
</tr>`
    )
    .join("\n");
  const recs = Array.from(
    new Set(report.checks.filter((c) => c.recommendation).map((c) => c.recommendation))
  )
    .map((r) => `<li>${escapeHtml(r)}</li>`)
    .join("");
  return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<title>Veeam ONE Health Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#f8fafc;color:#0f172a}
h1,h2{margin:0 0 12px}
.meta{margin:0 0 20px}
.pill{display:inline-block;padding:4px 10px;border-radius:999px;background:#e2e8f0;margin-right:8px}
table{border-collapse:collapse;width:100%;background:white}
th,td{border:1px solid #cbd5e1;padding:8px;vertical-align:top;text-align:left}
th{background:#e2e8f0}
</style>
</head>
<body>
<h1>Veeam ONE Health Check & Troubleshooting Assistant</h1>
<p class="meta"><span class="pill">Status: ${escapeHtml(report.summary.status)}</span><span class="pill">Score: ${report.summary.score}/100</span><span class="pill">Mode: ${escapeHtml(report.mode || "Full")}</span></p>
<p class="meta"><strong>Action:</strong> ${escapeHtml(report.action)}<br><strong>Target:</strong> ${escapeHtml(target.computerName || "?")} / ${escapeHtml(target.sqlServer || "?")} / ${escapeHtml(target.database || "?")}<br><strong>Timestamp:</strong> ${escapeHtml(report.timestamp)}</p>
<h2>Recommendations</h2>
<ul>${recs || "<li>No recommendations.</li>"}</ul>
<h2>Check Results</h2>
<table>
<thead><tr><th>Category</th><th>Check</th><th>Status</th><th>Severity</th><th>Evidence</th><th>Recommendation</th></tr></thead>
<tbody>
${rows}
</tbody>
</table>
</body>
</html>`;
}

export function exportCsv(report: NormalizedReport): string {
  const header = ["Category", "Check", "Status", "Severity", "Evidence", "Recommendation"];
  const rows = report.checks.map((c) => [
    c.category,
    c.name,
    c.status,
    c.severity,
    c.evidence,
    c.recommendation,
  ]);
  return [header, ...rows].map((row) => row.map(csvCell).join(",")).join("\n");
}

/** Escape pipes/newlines so a value is safe inside a Markdown table cell. */
function mdCell(value: string): string {
  return (value || "—").replace(/\|/g, "\\|").replace(/\n+/g, " ");
}

function escapeHtml(value: string): string {
  return (value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function csvCell(value: string): string {
  const text = (value || "").replace(/\r?\n/g, " ");
  return `"${text.replace(/"/g, '""')}"`;
}
