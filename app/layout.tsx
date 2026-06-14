import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Veeam ONE Health Check & Troubleshooting Assistant",
  description:
    "Veeam ONE health checks, troubleshooting, SQL diagnostics, log analysis and upgrade readiness guidance.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        <header className="border-b border-slate-800 bg-slate-900/60">
          <nav className="mx-auto flex max-w-5xl items-center justify-between px-5 py-3">
            <Link href="/readiness-checker" className="font-semibold tracking-tight">
              Veeam ONE Assistant
            </Link>
            <div className="flex gap-4 text-sm text-slate-300">
              <Link href="/readiness-checker" className="hover:text-white">
                Assistant
              </Link>
              <Link href="/roadmap" className="hover:text-white">
                Roadmap
              </Link>
            </div>
          </nav>
        </header>
        <main className="mx-auto max-w-5xl px-5 py-8">{children}</main>
        <footer className="mx-auto max-w-5xl px-5 pb-10 pt-4 text-xs text-slate-500">
          Unofficial open-source diagnostic and troubleshooting helper. Not
          affiliated with or supported by Veeam.
        </footer>
      </body>
    </html>
  );
}
