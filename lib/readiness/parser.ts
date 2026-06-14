import { computeScore } from "./scoring";
import type {
  CheckResult,
  CheckStatus,
  NormalizedReport,
  ReadinessResult,
  RuleSet,
  Severity,
} from "./types";

const STATUSES: CheckStatus[] = ["passed", "warning", "failed", "skipped"];
const SEVERITIES: Severity[] = ["info", "low", "medium", "high", "critical"];

export type ParseResult =
  | { ok: true; report: NormalizedReport }
  | { ok: false; error: string };

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function str(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

/**
 * Validate a parsed JSON object against the expected readiness-result schema
 * and normalize it (filling defaults and recomputing the authoritative
 * summary). Returns a friendly error message on failure.
 */
export function validateAndNormalize(
  data: unknown,
  rules: RuleSet
): ParseResult {
  if (!isObject(data)) {
    return { ok: false, error: "The file must contain a JSON object." };
  }
  if (!Array.isArray(data.checks)) {
    return {
      ok: false,
      error: "Missing a 'checks' array. This does not look like a readiness result.",
    };
  }
  if (data.checks.length === 0) {
    return { ok: false, error: "The 'checks' array is empty." };
  }

  const checks: CheckResult[] = [];
  for (let i = 0; i < data.checks.length; i++) {
    const raw = data.checks[i];
    const where = `checks[${i}]`;
    if (!isObject(raw)) {
      return { ok: false, error: `${where} is not an object.` };
    }
    if (typeof raw.name !== "string" || raw.name.trim() === "") {
      return { ok: false, error: `${where} is missing a 'name'.` };
    }
    if (!STATUSES.includes(raw.status as CheckStatus)) {
      return {
        ok: false,
        error: `${where} has an invalid 'status' (${String(
          raw.status
        )}). Expected one of: ${STATUSES.join(", ")}.`,
      };
    }
    const severity = SEVERITIES.includes(raw.severity as Severity)
      ? (raw.severity as Severity)
      : "medium";
    checks.push({
      id: str(raw.id) || slug(str(raw.name)),
      category: str(raw.category, "General"),
      name: raw.name,
      status: raw.status as CheckStatus,
      severity,
      evidence: str(raw.evidence),
      recommendation: str(raw.recommendation),
    });
  }

  const target = isObject(data.target) ? data.target : {};
  const details = isObject(data.details) ? data.details : undefined;
  const result: ReadinessResult = {
    product: str(data.product, rules.displayName),
    toolName: str(data.toolName, `${rules.displayName} Health Check & Troubleshooting Assistant`),
    action: str(data.action, "Pre-Upgrade"),
    mode: str(data.mode, "Full"),
    timestamp: str(data.timestamp, new Date().toISOString()),
    currentVersion: str(data.currentVersion),
    targetVersion: str(data.targetVersion),
    target: {
      computerName: str(target.computerName),
      sqlServer: str(target.sqlServer),
      sqlInstance: str(target.sqlInstance),
      database: str(target.database),
      port: typeof target.port === "number" ? target.port : 1433,
    },
    checks,
    details,
  };

  const outcome = computeScore(checks, rules);
  const report: NormalizedReport = {
    ...result,
    summary: {
      score: outcome.score,
      status: outcome.status,
      topIssues: outcome.topIssues,
    },
    outcome,
  };
  return { ok: true, report };
}

/** Parse raw text then validate. Friendly error on malformed JSON. */
export function parseReport(text: string, rules: RuleSet): ParseResult {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return {
      ok: false,
      error: "That file is not valid JSON. Upload the result produced by the script.",
    };
  }
  return validateAndNormalize(data, rules);
}

function slug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}
