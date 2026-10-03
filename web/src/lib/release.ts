import { REPO } from "./config";

export interface ReleaseInfo {
  version: string;
  build: string;
  date: string; // ISO
  dmgUrl: string;
  dmgName: string;
  sizeMB: number;
  sha256: string | null;
  shaUrl: string | null;
  live: boolean;
}

// Fallback used when GitHub is unreachable at build time: the 1.6.4 asset.
const FALLBACK: ReleaseInfo = {
  version: "1.6.4",
  build: "14",
  date: "2026-10-03T00:39:36Z",
  dmgUrl: `https://github.com/${REPO}/releases/download/v1.6.4/Herald-1.6.4-build14-macOS.dmg`,
  dmgName: "Herald-1.6.4-build14-macOS.dmg",
  sizeMB: 14,
  sha256: "f679c0985d31f201588bb7f2c69f6e55fd155fd2a043c915fea28c481bd8c7c7",
  shaUrl: `https://github.com/${REPO}/releases/download/v1.6.4/Herald-1.6.4-build14-macOS.dmg.sha256`,
  live: false,
};

interface GhAsset { name: string; size: number; browser_download_url: string; digest?: string }

export async function getRelease(): Promise<ReleaseInfo> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github+json" },
      next: { revalidate: 3600 },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return FALLBACK;
    const rel = (await res.json()) as { tag_name: string; published_at: string; assets: GhAsset[] };
    const dmg = rel.assets.find((a) => a.name.endsWith(".dmg"));
    if (!dmg) return FALLBACK;
    const sha = rel.assets.find((a) => a.name.endsWith(".sha256"));
    const build = dmg.name.match(/build(\d+)/i)?.[1] ?? FALLBACK.build;
    return {
      version: rel.tag_name.replace(/^v/, ""),
      build,
      date: rel.published_at,
      dmgUrl: dmg.browser_download_url,
      dmgName: dmg.name,
      sizeMB: Math.max(1, Math.round(dmg.size / 1024 / 1024)),
      sha256: dmg.digest?.replace(/^sha256:/, "") ?? null,
      shaUrl: sha?.browser_download_url ?? null,
      live: true,
    };
  } catch {
    return FALLBACK;
  }
}

export function monthYear(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}
