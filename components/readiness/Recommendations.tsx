import type { CheckResult } from "@/lib/readiness/types";

export function Recommendations({ checks }: { checks: CheckResult[] }) {
  const recommendations = Array.from(
    new Set(
      checks
        .filter((c) => c.recommendation && (c.status === "failed" || c.status === "warning"))
        .map((c) => c.recommendation)
    )
  );

  if (recommendations.length === 0) {
    return (
      <div className="text-sm text-slate-400">No recommendations — everything looks good.</div>
    );
  }

  return (
    <ul className="list-disc space-y-1.5 pl-5 text-sm text-slate-200">
      {recommendations.map((r, i) => (
        <li key={i}>{r}</li>
      ))}
    </ul>
  );
}
