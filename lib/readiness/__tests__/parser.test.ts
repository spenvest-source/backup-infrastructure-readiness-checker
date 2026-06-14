import { describe, expect, it } from "vitest";
import { parseReport, validateAndNormalize } from "../parser";
import rulesJson from "../rules/veeam-one-pre-upgrade.json";
import type { RuleSet } from "../types";

const rules = rulesJson as RuleSet;

describe("parseReport", () => {
  it("rejects malformed JSON with a friendly message", () => {
    const r = parseReport("{ not json", rules);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/not valid JSON/i);
  });

  it("rejects an object without a checks array", () => {
    const r = parseReport(JSON.stringify({ product: "Veeam ONE" }), rules);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/checks/i);
  });

  it("rejects a check with an invalid status", () => {
    const r = validateAndNormalize(
      { checks: [{ name: "X", status: "exploded" }] },
      rules
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error).toMatch(/invalid 'status'/i);
  });

  it("normalizes a valid result and recomputes the summary", () => {
    const r = validateAndNormalize(
      {
        product: "Veeam ONE",
        action: "Full Health Check",
        mode: "Full",
        details: { services: [{ displayName: "Veeam ONE Monitoring Service" }] },
        checks: [
          { id: "sql-port-connectivity", category: "Network Readiness", name: "SQL Port Connectivity", status: "failed", severity: "critical", evidence: "", recommendation: "open port" },
          { id: "os-version", category: "System Health", name: "OS Version", status: "passed", severity: "info" },
        ],
      },
      rules
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.report.summary.score).toBe(75);
      expect(r.report.summary.status).toBe("Not Ready");
      expect(r.report.mode).toBe("Full");
      expect(r.report.details?.services).toBeTruthy();
      // invalid/missing severity defaults to medium; missing evidence defaults to ""
      expect(r.report.checks[1]!.evidence).toBe("");
    }
  });

  it("defaults an unknown severity to medium", () => {
    const r = validateAndNormalize(
      { checks: [{ id: "c", name: "C", status: "warning", severity: "bogus" }] },
      rules
    );
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.report.checks[0]!.severity).toBe("medium");
  });
});
