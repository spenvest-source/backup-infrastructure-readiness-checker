// Static export for GitLab Pages. `NEXT_PUBLIC_BASE_PATH` is set by CI to the
// project path (e.g. /backup-infrastructure-readiness-checker) so the site
// works when served from a subpath. Empty in local dev (served at root).
const basePath = process.env.NEXT_PUBLIC_BASE_PATH || "";

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  ...(basePath ? { basePath } : {}),
};

export default nextConfig;
