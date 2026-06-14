"use client";

import { useState } from "react";
import { CategoryScores } from "@/components/readiness/CategoryScores";
import { CheckResultsTable } from "@/components/readiness/CheckResultsTable";
import { JsonUploader } from "@/components/readiness/JsonUploader";
import { ReadinessForm, type FormInputs } from "@/components/readiness/ReadinessForm";
import { Recommendations } from "@/components/readiness/Recommendations";
import { ScoreCard } from "@/components/readiness/ScoreCard";
import { ScriptGenerator } from "@/components/readiness/ScriptGenerator";
import { SupportSummary } from "@/components/readiness/SupportSummary";
import { UpgradeBlockers } from "@/components/readiness/UpgradeBlockers";
import type { NormalizedReport } from "@/lib/readiness/types";

function Section({
  step,
  title,
  children,
}: {
  step: number;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-xl border border-slate-800 bg-slate-900/40 p-5">
      <h2 className="mb-4 text-lg font-semibold">
        <span className="mr-2 text-slate-500">{step}.</span>
        {title}
      </h2>
      {children}
    </section>
  );
}

export default function ReadinessCheckerPage() {
  const [inputs, setInputs] = useState<FormInputs | null>(null);
  const [report, setReport] = useState<NormalizedReport | null>(null);

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <h1 className="text-2xl font-bold sm:text-3xl">
          Veeam ONE Health Check &amp; Troubleshooting Assistant
        </h1>
        <p className="text-slate-400">
          Upgrade readiness, health scoring, troubleshooting checks and report exports for Veeam ONE.
        </p>
        <div className="rounded-lg border border-amber-700/50 bg-amber-900/20 px-4 py-2 text-sm text-amber-200">
          This is an unofficial open-source helper tool. It does not replace vendor
          documentation or official support guidance. Review output before
          sharing.
        </div>
      </header>

      <Section step={1} title="Configure check">
        <ReadinessForm
          onGenerate={(values) => {
            setInputs(values);
            setReport(null);
          }}
        />
      </Section>

      {inputs && (
        <Section step={2} title="Generate & run PowerShell script">
          <ScriptGenerator inputs={inputs} />
        </Section>
      )}

      {inputs && (
        <Section step={3} title="Upload JSON result">
          <JsonUploader onReport={setReport} />
        </Section>
      )}

      {report ? (
        <Section step={4} title="Health report">
          <div className="space-y-6">
            <ScoreCard report={report} />

            <div>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-400">
                Category Scores
              </h3>
              <CategoryScores scores={report.outcome.categoryScores} />
            </div>

            <UpgradeBlockers blockers={report.outcome.blockers} />

            <div>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-400">
                Recommendations
              </h3>
              <Recommendations checks={report.checks} />
            </div>

            <div>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-400">
                Full Check Results
              </h3>
              <CheckResultsTable checks={report.checks} />
            </div>

            <div>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-400">
                Support Summary &amp; Export
              </h3>
              <SupportSummary report={report} />
            </div>
          </div>
        </Section>
      ) : (
        inputs && (
          <div className="rounded-xl border border-dashed border-slate-800 px-5 py-8 text-center text-sm text-slate-500">
            No result yet. Run the script on the Veeam ONE server and upload its
            JSON (or load a sample above) to see the health report.
          </div>
        )
      )}
    </div>
  );
}
