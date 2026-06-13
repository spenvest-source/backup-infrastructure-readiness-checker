// Core domain types for the readiness checker. Shared by the scoring engine,
// parser, exporters and UI. Kept framework-agnostic so the lib is unit-testable
// without React/Next.

export type CheckStatus = "passed" | "warning" | "failed" | "skipped";

export type Severity = "info" | "low" | "medium" | "high" | "critical";

export type ReadinessStatus = "Ready" | "Warning" | "Not Ready";

/** A single check as produced by the PowerShell script. */
export interface CheckResult {
  id: string;
  category: string;
  name: string;
  status: CheckStatus;
  severity: Severity;
  evidence: string;
  recommendation: string;
}

export interface ResultSummary {
  score: number;
  status: ReadinessStatus;
  topIssues: string[];
}

/** The JSON document the script outputs and the user uploads. */
export interface ReadinessResult {
  product: string;
  action: string;
  timestamp: string;
  currentVersion: string;
  targetVersion: string;
  target: {
    computerName: string;
    sqlServer: string;
    sqlInstance: string;
    database: string;
    port: number;
  };
  checks: CheckResult[];
  summary?: ResultSummary;
}

/** Per-category roll-up shown on the report. */
export interface CategoryScore {
  category: string;
  score: number;
  passed: number;
  warning: number;
  failed: number;
  skipped: number;
  total: number;
}

/** Output of the scoring engine. */
export interface ScoreOutcome {
  score: number;
  status: ReadinessStatus;
  topIssues: string[];
  categoryScores: CategoryScore[];
  blockers: CheckResult[];
  counts: Record<CheckStatus, number>;
}

/** A fully normalized report: the result plus an authoritative summary. */
export interface NormalizedReport extends ReadinessResult {
  summary: ResultSummary;
  outcome: ScoreOutcome;
}

/** Shape of lib/readiness/rules/*.json. */
export interface RuleSet {
  product: string;
  displayName: string;
  action: string;
  categories: string[];
  criticalCheckIds: string[];
}
