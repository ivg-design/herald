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

// Fallback used when GitHub is unreachable at build time: the real 1.9.2 (build 24) asset.
const FALLBACK: ReleaseInfo = {
  version: "1.9.2",
  build: "24",
  date: "2026-10-05T01:30:00Z",
  dmgUrl: `https://github.com/${REPO}/releases/download/v1.9.2/Herald-1.9.2-build24-macOS.dmg`,
  dmgName: "Herald-1.9.2-build24-macOS.dmg",
  sizeMB: Math.round(15266007 / 1024 / 1024),
  sha256: "70c042d959ce8e375280b9fcb330955c92e783762db0de48ec621f70e28cd721",
  shaUrl: `https://github.com/${REPO}/releases/download/v1.9.2/Herald-1.9.2-build24-macOS.dmg.sha256`,
  live: false,
};

function parts(v: string): number[] {
  const m = v.replace(/^v/, "").split(/[.\-+]/).slice(0, 3).map((n) => parseInt(n, 10));
  return [0, 1, 2].map((i) => (Number.isFinite(m[i]) ? m[i] : 0));
}

/** True when version a is newer than b (major.minor.patch, numerically). */
function newer(a: string, b: string): boolean {
  const x = parts(a), y = parts(b);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i];
  return false;
}

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
    const live: ReleaseInfo = {
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
    // Never let an older live answer downgrade the page below the known fallback.
    return newer(FALLBACK.version, live.version) ? FALLBACK : live;
  } catch {
    return FALLBACK;
  }
}

export function monthYear(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
}
