"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

// Client-side redirect (static-export friendly) to the main page.
export default function Home() {
  const router = useRouter();
  useEffect(() => {
    router.replace("/readiness-checker");
  }, [router]);
  return <p className="text-slate-400">Redirecting to the readiness checker…</p>;
}
