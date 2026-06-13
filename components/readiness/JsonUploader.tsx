"use client";

import { useRef, useState } from "react";
import { asset } from "@/lib/basePath";
import { parseReport } from "@/lib/readiness/parser";
import rulesJson from "@/lib/readiness/rules/veeam-one-pre-upgrade.json";
import type { NormalizedReport, RuleSet } from "@/lib/readiness/types";

const rules = rulesJson as RuleSet;

const SAMPLES = [
  { label: "sample-ready.json", path: asset("/samples/sample-ready.json") },
  { label: "sample-warning.json", path: asset("/samples/sample-warning.json") },
  { label: "sample-not-ready.json", path: asset("/samples/sample-not-ready.json") },
];

export function JsonUploader({
  onReport,
}: {
  onReport: (report: NormalizedReport) => void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const ingest = (text: string) => {
    const result = parseReport(text, rules);
    if (result.ok) {
      setError(null);
      onReport(result.report);
    } else {
      setError(result.error);
    }
  };

  const onFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setBusy(true);
    try {
      ingest(await file.text());
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const loadSample = async (path: string) => {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(path);
      ingest(await res.text());
    } catch {
      setError("Could not load the sample file.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-3">
      <label className="inline-block cursor-pointer rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500">
        {busy ? "Reading…" : "Upload JSON Result"}
        <input
          ref={fileRef}
          type="file"
          accept="application/json,.json"
          onChange={onFile}
          disabled={busy}
          hidden
        />
      </label>

      <div className="text-xs text-slate-400">
        Or load a sample:{" "}
        {SAMPLES.map((s, i) => (
          <span key={s.path}>
            {i > 0 && " · "}
            <button
              onClick={() => loadSample(s.path)}
              className="underline hover:text-slate-200"
            >
              {s.label}
            </button>
          </span>
        ))}
      </div>

      {error && (
        <div className="rounded-md border border-red-800 bg-red-900/30 px-4 py-3 text-sm text-red-200">
          {error}
        </div>
      )}
    </div>
  );
}
