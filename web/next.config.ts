import type { NextConfig } from "next";

const isProd = process.env.NODE_ENV === "production";
const isForgeContext = process.env.NEXT_PUBLIC_SITE_URL?.includes("forge.mograph.life");
const prefix = isProd && isForgeContext ? "/apps/herald" : "";

const nextConfig: NextConfig = {
  // Verification builds use NEXT_DIST_DIR=.next-verify so they never touch the live dev server's .next.
  distDir: process.env.NEXT_DIST_DIR || ".next",
  images: { unoptimized: true },
  turbopack: { root: process.cwd() },
  assetPrefix: prefix,
  env: {
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3102",
    NEXT_PUBLIC_ASSET_PREFIX: prefix,
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Robots-Tag", value: "index, follow, max-snippet:-1, max-image-preview:large" },
        ],
      },
    ];
  },
};

export default nextConfig;
