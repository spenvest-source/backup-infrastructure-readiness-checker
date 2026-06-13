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
  lines.push("Backup Infrastructure Readiness Checker - Support Summary");
  lines.push("(Unofficial readiness tool. Review before sharing.)");
  lines.push("");
  lines.push(`Product: ${report.product}  Action: ${report.action}`);
  lines.push(`Readiness: ${summary.status}   Score: ${summary.score}/100`);
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
  md.push(`# Readiness Report - ${report.product} ${report.action}`);
  md.push("");
  md.push("> Unofficial readiness tool. Review before sharing.");
  md.push("");
  md.push(`**Status:** ${summary.status}  ·  **Score:** ${summary.score}/100`);
  md.push("");
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
    md.push("## Upgrade Blockers");
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

/** Escape pipes/newlines so a value is safe inside a Markdown table cell. */
function mdCell(value: string): string {
  return (value || "—").replace(/\|/g, "\\|").replace(/\n+/g, " ");
}
