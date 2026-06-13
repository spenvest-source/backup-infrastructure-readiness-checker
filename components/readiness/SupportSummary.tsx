"use client";

import { useMemo, useState } from "react";
import {
  buildSupportSummary,
  exportJson,
  exportMarkdown,
} from "@/lib/readiness/reportExport";
import type { NormalizedReport } from "@/lib/readiness/types";

function downloadText(filename: string, text: string, mime: string) {
  const blob = new Blob([text], { type: `${mime};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function SupportSummary({ report }: { report: NormalizedReport }) {
  const summaryText = useMemo(() => buildSupportSummary(report), [report]);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    await navigator.clipboard.writeText(summaryText);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <button
          onClick={copy}
          className="rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          {copied ? "Copied!" : "Copy Support Summary"}
        </button>
        <button
          onClick={() => downloadText("readiness-report.json", exportJson(report), "application/json")}
          className="rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          Export Report as JSON
        </button>
        <button
          onClick={() => downloadText("readiness-report.md", exportMarkdown(report), "text/markdown")}
          className="rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          Export Report as Markdown
        </button>
      </div>
      <pre className="max-h-72 overflow-auto whitespace-pre-wrap rounded-md border border-slate-800 bg-slate-950 p-4 text-xs">
        {summaryText}
      </pre>
    </div>
  );
}
