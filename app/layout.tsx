import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Backup Infrastructure Readiness Checker",
  description:
    "Pre-installation and pre-upgrade validation for backup infrastructure. Unofficial readiness tool.",
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
              Readiness Checker
            </Link>
            <div className="flex gap-4 text-sm text-slate-300">
              <Link href="/readiness-checker" className="hover:text-white">
                Checker
              </Link>
              <Link href="/roadmap" className="hover:text-white">
                Roadmap
              </Link>
            </div>
          </nav>
        </header>
        <main className="mx-auto max-w-5xl px-5 py-8">{children}</main>
        <footer className="mx-auto max-w-5xl px-5 pb-10 pt-4 text-xs text-slate-500">
          Unofficial diagnostic/readiness tool. Not affiliated with or supported
          by Veeam.
        </footer>
      </body>
    </html>
  );
}
