"use client";

import { useState } from "react";

export interface FormInputs {
  currentVersion: string;
  targetVersion: string;
  sqlServer: string;
  sqlInstance: string;
  databaseName: string;
  sqlPort: string;
}

const INITIAL: FormInputs = {
  currentVersion: "",
  targetVersion: "",
  sqlServer: "",
  sqlInstance: "",
  databaseName: "VeeamONE",
  sqlPort: "1433",
};

type Errors = Partial<Record<keyof FormInputs, string>>;

function validate(form: FormInputs): Errors {
  const errors: Errors = {};
  const port = Number(form.sqlPort || "1433");
  if (form.sqlPort.trim() && (!Number.isInteger(port) || port < 1 || port > 65535)) {
    errors.sqlPort = "SQL Port must be a number between 1 and 65535.";
  }
  return errors;
}

const labelCls = "flex flex-col gap-1 text-sm";
const inputCls =
  "rounded-md border border-slate-700 bg-slate-800 px-3 py-2 text-sm outline-none focus:border-blue-500";

export function ReadinessForm({
  onGenerate,
}: {
  onGenerate: (inputs: FormInputs) => void;
}) {
  const [form, setForm] = useState<FormInputs>(INITIAL);
  const [errors, setErrors] = useState<Errors>({});

  const set =
    (key: keyof FormInputs) =>
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setForm((f) => ({ ...f, [key]: e.target.value }));
      setErrors((er) => ({ ...er, [key]: undefined }));
    };

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const found = validate(form);
    setErrors(found);
    if (Object.keys(found).length === 0) onGenerate(form);
  };

  const field = (
    key: keyof FormInputs,
    label: string,
    placeholder = "",
    required = false
  ) => (
    <label className={labelCls}>
      <span className="text-slate-300">
        {label} {required && <span className="text-red-400">*</span>}
      </span>
      <input
        className={`${inputCls} ${errors[key] ? "border-red-500" : ""}`}
        value={form[key]}
        onChange={set(key)}
        placeholder={placeholder}
        inputMode={key === "sqlPort" ? "numeric" : undefined}
      />
      {errors[key] && <span className="text-xs text-red-400">{errors[key]}</span>}
    </label>
  );

  return (
    <form onSubmit={submit} noValidate className="space-y-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label className={labelCls}>
          <span className="text-slate-300">Product</span>
          <select className={inputCls} value="Veeam ONE" disabled>
            <option>Veeam ONE</option>
          </select>
        </label>
        <label className={labelCls}>
          <span className="text-slate-300">Action</span>
          <select className={inputCls} value="Full Health Check" disabled>
            <option>Full Health Check</option>
          </select>
        </label>
        {field("currentVersion", "Current version (optional)", "11.0")}
        {field("targetVersion", "Target version (optional)", "12.1")}
        {field("sqlServer", "SQL Server (optional but recommended)", "sql01.corp.local")}
        {field("sqlInstance", "SQL Instance (optional)", "VEEAMSQL2016")}
        {field("databaseName", "Database name", "VeeamONE")}
        {field("sqlPort", "SQL Port", "1433")}
      </div>
      <button
        type="submit"
        className="rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500"
      >
        Generate PowerShell Script
      </button>
    </form>
  );
}
