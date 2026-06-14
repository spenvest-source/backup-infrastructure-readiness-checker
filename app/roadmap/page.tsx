import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Roadmap — Veeam ONE Health Check & Troubleshooting Assistant",
};

const CURRENT = ["Veeam ONE Health Check & Troubleshooting Assistant"];

const PLANNED = [
  "VBR Pre-Upgrade",
  "VB365 Pre-Install",
  "VB365 Object Storage Validation",
  "VBR Repository Validation",
  "Microsoft 365 Permission Validation",
  "VMware/vCenter Connectivity Validation",
];

export default function RoadmapPage() {
  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-2xl font-bold">Roadmap</h1>
        <p className="mt-1 text-slate-400">
          The assistant is modular. Veeam ONE health and upgrade diagnostics are
          live, and more product-specific assistants are planned.
        </p>
      </header>

      <section>
        <h2 className="mb-3 text-lg font-semibold">Current</h2>
        <ul className="space-y-2">
          {CURRENT.map((item) => (
            <li
              key={item}
              className="flex items-center gap-3 rounded-lg border border-green-800/60 bg-green-900/20 px-4 py-3"
            >
              <span className="rounded-full bg-green-600 px-2 py-0.5 text-xs font-semibold">
                Available
              </span>
              {item}
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-3 text-lg font-semibold">Planned</h2>
        <ul className="space-y-2">
          {PLANNED.map((item) => (
            <li
              key={item}
              className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-900/40 px-4 py-3 text-slate-300"
            >
              <span className="rounded-full bg-slate-600 px-2 py-0.5 text-xs font-semibold">
                Planned
              </span>
              {item}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
