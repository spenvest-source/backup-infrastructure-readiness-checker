"use client";

import { useEffect, useState } from "react";
import { asset } from "@/lib/basePath";
import type { FormInputs } from "./ReadinessForm";

const SCRIPT_PATH = asset("/scripts/VeeamOnePreUpgradeReadiness.ps1");
const SCRIPT_NAME = "VeeamOnePreUpgradeReadiness.ps1";

function applyPlaceholders(template: string, inputs: FormInputs): string {
  return template
    .replace(/\{\{CURRENT_VERSION\}\}/g, inputs.currentVersion)
    .replace(/\{\{TARGET_VERSION\}\}/g, inputs.targetVersion)
    .replace(/\{\{SQL_SERVER\}\}/g, inputs.sqlServer)
    .replace(/\{\{SQL_INSTANCE\}\}/g, inputs.sqlInstance)
    .replace(/\{\{DATABASE_NAME\}\}/g, inputs.databaseName)
    .replace(/\{\{SQL_PORT\}\}/g, inputs.sqlPort);
}

export function ScriptGenerator({ inputs }: { inputs: FormInputs }) {
  const [script, setScript] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let active = true;
    setScript(null);
    setError(null);
    fetch(SCRIPT_PATH)
      .then((r) => {
        if (!r.ok) throw new Error(String(r.status));
        return r.text();
      })
      .then((tpl) => {
        if (active) setScript(applyPlaceholders(tpl, inputs));
      })
      .catch(() => {
        if (active) setError("Could not load the PowerShell template.");
      });
    return () => {
      active = false;
    };
  }, [inputs]);

  const copy = async () => {
    if (!script) return;
    await navigator.clipboard.writeText(script);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const download = () => {
    if (!script) return;
    const blob = new Blob([script], { type: "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = SCRIPT_NAME;
    a.click();
    URL.revokeObjectURL(url);
  };

  if (error) {
    return <div className="rounded-md bg-red-900/30 px-4 py-3 text-sm text-red-200">{error}</div>;
  }
  if (!script) {
    return <div className="text-sm text-slate-400">Generating script…</div>;
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-slate-400">
        Run <code className="rounded bg-slate-800 px-1.5 py-0.5">{SCRIPT_NAME}</code>{" "}
        <strong>on the Veeam ONE server</strong> (or a host with the same network
        path to SQL). It now supports `-Mode Upgrade`, `-Mode Health`, `-Mode Full`,
        log analysis, port checks, sizing guidance, and JSON/HTML/CSV exports.
        It writes sanitized local report files only; nothing is uploaded
        automatically and no passwords or secrets are collected. Review the
        report before sharing.
      </p>
      <div className="flex gap-2">
        <button
          onClick={copy}
          className="rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          {copied ? "Copied!" : "Copy Script"}
        </button>
        <button
          onClick={download}
          className="rounded-md border border-slate-700 bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          Download Script
        </button>
      </div>
      <pre className="max-h-96 overflow-auto rounded-md border border-slate-800 bg-slate-950 p-4 text-xs leading-relaxed">
        <code>{script}</code>
      </pre>
    </div>
  );
}
