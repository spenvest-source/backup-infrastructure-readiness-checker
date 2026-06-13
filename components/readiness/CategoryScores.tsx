import type { CategoryScore } from "@/lib/readiness/types";

function barColor(score: number): string {
  if (score >= 85) return "bg-green-500";
  if (score >= 60) return "bg-amber-500";
  return "bg-red-500";
}

export function CategoryScores({ scores }: { scores: CategoryScore[] }) {
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      {scores.map((c) => (
        <div key={c.category} className="rounded-xl border border-slate-800 bg-slate-900 p-4">
          <div className="text-sm font-medium text-slate-300">{c.category}</div>
          <div className="mt-1 text-2xl font-bold">{c.score}</div>
          <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-slate-800">
            <div
              className={`h-full ${barColor(c.score)}`}
              style={{ width: `${c.score}%` }}
            />
          </div>
          <div className="mt-2 text-xs text-slate-500">
            {c.passed}P · {c.warning}W · {c.failed}F · {c.skipped}S
          </div>
        </div>
      ))}
    </div>
  );
}
