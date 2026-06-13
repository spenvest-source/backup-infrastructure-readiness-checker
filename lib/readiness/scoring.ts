import type {
  CategoryScore,
  CheckResult,
  CheckStatus,
  RuleSet,
  ScoreOutcome,
  Severity,
} from "./types";

// Deduction applied to a FAILED check, by severity.
const FAILED_DEDUCTION: Record<Severity, number> = {
  critical: 25,
  high: 15,
  medium: 10,
  low: 5,
  info: 0,
};

const WARNING_DEDUCTION = 5;
const SEVERITY_ORDER: Severity[] = ["critical", "high", "medium", "low", "info"];

/** Deduction a single check contributes (warning -5, failed by severity). */
function deductionFor(check: CheckResult): number {
  if (check.status === "failed") return FAILED_DEDUCTION[check.severity] ?? 0;
  if (check.status === "warning") return WARNING_DEDUCTION;
  return 0;
}

/** Score a subset of checks: start at 100, deduct, clamp to [0, 100]. */
function scoreChecks(checks: CheckResult[]): number {
  const deduction = checks.reduce((sum, c) => sum + deductionFor(c), 0);
  return Math.max(0, 100 - deduction);
}

function emptyCounts(): Record<CheckStatus, number> {
  return { passed: 0, warning: 0, failed: 0, skipped: 0 };
}

/**
 * Authoritative scoring for a full result.
 *
 * Overall score: start at 100, deduct per the rules (failed critical -25 /
 * high -15 / medium -10 / low -5, warning -5, skipped 0), min 0.
 *
 * Status:
 *   - Ready:     score >= 85, no critical-check failures, no warnings
 *   - Warning:   score 60-84, or any warnings present
 *   - Not Ready: score < 60, or any critical-check failure
 *
 * Critical-check failures are determined by `rules.criticalCheckIds`
 * (a check with one of those ids whose status is "failed"), plus any check
 * with severity "critical" that failed.
 */
export function computeScore(
  checks: CheckResult[],
  rules: RuleSet
): ScoreOutcome {
  const criticalIds = new Set(rules.criticalCheckIds);
  const score = scoreChecks(checks);

  const counts = emptyCounts();
  for (const c of checks) counts[c.status] += 1;

  const blockers = checks.filter(
    (c) =>
      c.status === "failed" &&
      (criticalIds.has(c.id) || c.severity === "critical")
  );
  const hasWarning = counts.warning > 0;

  let status: ScoreOutcome["status"];
  if (blockers.length > 0 || score < 60) status = "Not Ready";
  else if (score < 85 || hasWarning) status = "Warning";
  else status = "Ready";

  // Per-category roll-ups. Categories come from the rules, plus any extra
  // categories present in the data (defensive).
  const categoryNames = Array.from(
    new Set([...rules.categories, ...checks.map((c) => c.category)])
  );
  const categoryScores: CategoryScore[] = categoryNames.map((category) => {
    const inCat = checks.filter((c) => c.category === category);
    const catCounts = emptyCounts();
    for (const c of inCat) catCounts[c.status] += 1;
    return {
      category,
      score: scoreChecks(inCat),
      passed: catCounts.passed,
      warning: catCounts.warning,
      failed: catCounts.failed,
      skipped: catCounts.skipped,
      total: inCat.length,
    };
  });

  const rank = (s: Severity) => {
    const i = SEVERITY_ORDER.indexOf(s);
    return i === -1 ? SEVERITY_ORDER.length : i;
  };
  const topIssues = checks
    .filter((c) => c.status === "failed" || c.status === "warning")
    .sort((a, b) => rank(a.severity) - rank(b.severity))
    .slice(0, 5)
    .map((c) => (c.recommendation ? `${c.name} - ${c.recommendation}` : c.name));

  return { score, status, topIssues, categoryScores, blockers, counts };
}
