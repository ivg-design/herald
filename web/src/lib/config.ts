export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3102";
export const PREFIX = process.env.NEXT_PUBLIC_ASSET_PREFIX || "";
export const REPO = "ivg-design/herald";
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases`;
/** Who makes Herald: shown in the footer and on the legal pages. */
export const DEVELOPER = {
  name: "Ilya Gusinski",
  studio: "IVG Design",
  linkedin: "https://www.linkedin.com/in/ivgd",
  portfolio: "https://www.mograph.life",
  contact: "https://services.mograph.life/",
};

/** Static files in /public (images, fonts). */
export function asset(path: string): string {
  return `${PREFIX}${path}`;
}

/** Internal route, honouring the forge sub-path deployment. */
export function route(path: string): string {
  if (!path.startsWith("/") || path.startsWith("//")) return path;
  return `${PREFIX}${path}`;
}

export function absolute(path: string): string {
  return `${SITE_URL.replace(/\/$/, "")}${path}`;
}

/** Easings used across the site (names from the motion plan). */
export const EASE = {
  quart: [0.25, 1, 0.5, 1] as [number, number, number, number],
  quint: [0.22, 1, 0.36, 1] as [number, number, number, number],
  expo: [0.16, 1, 0.3, 1] as [number, number, number, number],
};
