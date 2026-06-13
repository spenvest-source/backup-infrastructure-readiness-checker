import type { CheckResult } from "@/lib/readiness/types";
import { SeverityBadge } from "./Badge";

export function UpgradeBlockers({ blockers }: { blockers: CheckResult[] }) {
  if (blockers.length === 0) {
    return (
      <div className="rounded-xl border border-green-800/60 bg-green-900/20 px-4 py-3 text-sm text-green-200">
        No upgrade blockers detected.
      </div>
    );
  }
  return (
    <div className="rounded-xl border border-red-800 bg-red-900/20 p-4">
      <h3 className="mb-2 font-semibold text-red-200">Upgrade Blockers</h3>
      <ul className="space-y-2">
        {blockers.map((b) => (
          <li key={b.id} className="flex items-start gap-3 text-sm">
            <SeverityBadge severity={b.severity} />
            <div>
              <div className="font-medium">{b.name}</div>
              <div className="text-slate-300">{b.evidence}</div>
              {b.recommendation && (
                <div className="text-slate-400">→ {b.recommendation}</div>
              )}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
