import type { CheckResult } from "@/lib/readiness/types";
import { SeverityBadge, StatusBadge } from "./Badge";

export function CheckResultsTable({ checks }: { checks: CheckResult[] }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="w-full text-left text-sm">
        <thead className="bg-slate-900 text-slate-400">
          <tr>
            <th className="px-3 py-2 font-medium">Category</th>
            <th className="px-3 py-2 font-medium">Check Name</th>
            <th className="px-3 py-2 font-medium">Status</th>
            <th className="px-3 py-2 font-medium">Severity</th>
            <th className="px-3 py-2 font-medium">Evidence</th>
            <th className="px-3 py-2 font-medium">Recommendation</th>
          </tr>
        </thead>
        <tbody>
          {checks.map((c) => (
            <tr key={c.id} className="border-t border-slate-800 align-top">
              <td className="px-3 py-2 text-slate-300">{c.category}</td>
              <td className="px-3 py-2">{c.name}</td>
              <td className="px-3 py-2">
                <StatusBadge status={c.status} />
              </td>
              <td className="px-3 py-2">
                <SeverityBadge severity={c.severity} />
              </td>
              <td className="max-w-xs px-3 py-2 text-slate-400">{c.evidence}</td>
              <td className="max-w-xs px-3 py-2 text-slate-400">
                {c.recommendation || "—"}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
