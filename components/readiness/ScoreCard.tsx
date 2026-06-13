import type { NormalizedReport } from "@/lib/readiness/types";
import { ReadinessBadge } from "./Badge";

export function ScoreCard({ report }: { report: NormalizedReport }) {
  const { summary, outcome } = report;
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <div className="rounded-xl border border-slate-800 bg-gradient-to-br from-slate-900 to-slate-800 p-5">
        <div className="text-xs uppercase tracking-wide text-slate-400">
          Overall Readiness Score
        </div>
        <div className="mt-1 text-5xl font-bold">{summary.score}</div>
        <div className="text-xs text-slate-400">out of 100</div>
      </div>
      <div className="rounded-xl border border-slate-800 bg-slate-900 p-5">
        <div className="text-xs uppercase tracking-wide text-slate-400">Status</div>
        <div className="mt-3">
          <ReadinessBadge status={summary.status} />
        </div>
      </div>
      <div className="rounded-xl border border-slate-800 bg-slate-900 p-5">
        <div className="text-xs uppercase tracking-wide text-slate-400">Checks</div>
        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
          <span className="text-green-400">{outcome.counts.passed} passed</span>
          <span className="text-amber-400">{outcome.counts.warning} warning</span>
          <span className="text-red-400">{outcome.counts.failed} failed</span>
          <span className="text-slate-400">{outcome.counts.skipped} skipped</span>
        </div>
      </div>
    </div>
  );
}
