import { describe, expect, it } from "vitest";
import { computeScore } from "../scoring";
import rulesJson from "../rules/veeam-one-pre-upgrade.json";
import type { CheckResult, RuleSet } from "../types";

const rules = rulesJson as RuleSet;

function check(p: Partial<CheckResult>): CheckResult {
  return {
    id: p.id ?? "x",
    category: p.category ?? "SQL Readiness",
    name: p.name ?? "X",
    status: p.status ?? "passed",
    severity: p.severity ?? "info",
    evidence: p.evidence ?? "",
    recommendation: p.recommendation ?? "",
  };
}

describe("computeScore", () => {
  it("all passed => 100 and Ready", () => {
    const out = computeScore([check({ status: "passed" }), check({ status: "passed" })], rules);
    expect(out.score).toBe(100);
    expect(out.status).toBe("Ready");
  });

  it("applies the severity deduction table", () => {
    const out = computeScore(
      [
        check({ id: "sql-metadata-permission", status: "failed", severity: "high" }), // -15
        check({ id: "sql-express-size", status: "warning", severity: "medium" }), // -5
      ],
      rules
    );
    expect(out.score).toBe(80);
    expect(out.status).toBe("Warning");
  });

  it("a critical-check failure forces Not Ready regardless of score", () => {
    const out = computeScore(
      [check({ id: "sql-port-connectivity", status: "failed", severity: "critical" })],
      rules
    );
    expect(out.score).toBe(75); // 100 - 25
    expect(out.status).toBe("Not Ready");
    expect(out.blockers.map((b) => b.id)).toContain("sql-port-connectivity");
  });

  it("clamps the score at 0", () => {
    const many = Array.from({ length: 10 }, () =>
      check({ id: "sql-connection", status: "failed", severity: "critical" })
    );
    expect(computeScore(many, rules).score).toBe(0);
  });

  it("warnings present push a high score down to Warning", () => {
    const out = computeScore([check({ status: "warning", severity: "low" })], rules);
    expect(out.score).toBe(95);
    expect(out.status).toBe("Warning");
  });

  it("produces per-category scores for each rule category", () => {
    const out = computeScore(
      [
        check({ category: "System Health", status: "passed" }),
        check({ category: "SQL Readiness", id: "sql-connection", status: "failed", severity: "critical" }),
      ],
      rules
    );
    const sql = out.categoryScores.find((c) => c.category === "SQL Readiness");
    const sys = out.categoryScores.find((c) => c.category === "System Health");
    expect(sys?.score).toBe(100);
    expect(sql?.score).toBe(75);
    expect(out.categoryScores.map((c) => c.category)).toEqual(
      expect.arrayContaining(rules.categories)
    );
  });
});
