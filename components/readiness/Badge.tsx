import type { CheckStatus, ReadinessStatus, Severity } from "@/lib/readiness/types";

const STATUS_CLASS: Record<CheckStatus, string> = {
  passed: "bg-green-600",
  warning: "bg-amber-500",
  failed: "bg-red-600",
  skipped: "bg-gray-500",
};

const SEVERITY_CLASS: Record<Severity, string> = {
  critical: "bg-red-600",
  high: "bg-orange-600",
  medium: "bg-amber-500",
  low: "bg-blue-600",
  info: "bg-gray-500",
};

const READINESS_CLASS: Record<ReadinessStatus, string> = {
  Ready: "bg-green-600",
  Warning: "bg-amber-500",
  "Not Ready": "bg-red-600",
};

function Pill({ className, children }: { className: string; children: React.ReactNode }) {
  return (
    <span
      className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-semibold capitalize text-white ${className}`}
    >
      {children}
    </span>
  );
}

export function StatusBadge({ status }: { status: CheckStatus }) {
  return <Pill className={STATUS_CLASS[status]}>{status}</Pill>;
}

export function SeverityBadge({ severity }: { severity: Severity }) {
  return <Pill className={SEVERITY_CLASS[severity]}>{severity}</Pill>;
}

export function ReadinessBadge({ status }: { status: ReadinessStatus }) {
  return (
    <span
      className={`inline-block rounded-full px-4 py-1 text-sm font-bold text-white ${READINESS_CLASS[status]}`}
    >
      {status}
    </span>
  );
}
