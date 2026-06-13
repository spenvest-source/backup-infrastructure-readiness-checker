// Base path the app is served from. Set by CI for GitLab Pages (a subpath);
// empty in local dev. Next.js rewrites <Link>/router/_next assets for basePath
// automatically, but NOT manual fetch() of files in public/, so prefix those
// with `asset()`.
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

export function asset(path: string): string {
  const p = path.startsWith("/") ? path : `/${path}`;
  return `${BASE_PATH}${p}`;
}
