import { describe, expect, it } from "vitest";
import { validateAndNormalize } from "../parser";
import { buildSupportSummary, exportCsv, exportHtml, exportJson, exportMarkdown } from "../reportExport";
import rulesJson from "../rules/veeam-one-pre-upgrade.json";
import type { NormalizedReport, RuleSet } from "../types";

const rules = rulesJson as RuleSet;

function sampleReport(): NormalizedReport {
  const r = validateAndNormalize(
      {
        product: "Veeam ONE",
        action: "Full Health Check",
        mode: "Full",
        currentVersion: "11.0",
        targetVersion: "12.1",
        target: { sqlServer: "sql01", database: "VeeamONE", port: 1433 },
      checks: [
        { id: "sql-port-connectivity", category: "Network Readiness", name: "SQL Port Connectivity", status: "failed", severity: "critical", evidence: "not reachable", recommendation: "Open TCP port 1433." },
        { id: "disk-free-system", category: "System Health", name: "System Drive Free Space", status: "warning", severity: "high", evidence: "6 GB free", recommendation: "Free disk space." },
        { id: "os-version", category: "System Health", name: "OS Version", status: "passed", severity: "info", evidence: "Windows Server 2022" },
      ],
    },
    rules
  );
  if (!r.ok) throw new Error("fixture failed to normalize");
  return r.report;
}

describe("reportExport", () => {
  it("exportMarkdown includes status, score, a blockers section and a results table", () => {
    const md = exportMarkdown(sampleReport());
    expect(md).toContain("# Health Report");
    expect(md).toContain("**Status:** Not Ready");
    expect(md).toContain("Score:** 70");
    expect(md).toContain("## Critical Issues");
    expect(md).toContain("| Category | Check | Status | Severity | Evidence | Recommendation |");
    expect(md).toContain("SQL Port Connectivity");
  });

  it("exportJson round-trips to valid JSON without the internal outcome field", () => {
    const parsed = JSON.parse(exportJson(sampleReport()));
    expect(parsed.summary.status).toBe("Not Ready");
    expect(parsed.summary.score).toBe(70);
    expect(parsed.outcome).toBeUndefined();
    expect(Array.isArray(parsed.checks)).toBe(true);
  });

  it("buildSupportSummary lists category scores and recommendations", () => {
    const text = buildSupportSummary(sampleReport());
    expect(text).toContain("Health: Not Ready");
    expect(text).toContain("Category scores:");
    expect(text).toContain("Open TCP port 1433.");
  });

  it("exports HTML and CSV report formats", () => {
    const report = sampleReport();
    const html = exportHtml(report);
    const csv = exportCsv(report);
    expect(html).toContain("Veeam ONE Health Check & Troubleshooting Assistant");
    expect(html).toContain("<table>");
    expect(csv).toContain('"Category","Check","Status","Severity","Evidence","Recommendation"');
    expect(csv).toContain("SQL Port Connectivity");
  });
});
