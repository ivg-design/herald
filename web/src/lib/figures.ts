import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

// Docs screenshots live in public/shots/docs with a manifest (file, width, height, appearance, title, shows, section).
// The Markdown names them by a path that also resolves on GitHub (../web/public/shots/docs/<file>); the site maps
// that to /shots/docs/<file> and takes the intrinsic size, and the dark twin when there is one, from the manifest.

export interface Shot {
  file: string;
  file2x?: string;
  framed?: boolean;
  width?: number;
  height?: number;
  appearance?: string;
  title?: string;
  shows?: string;
  section?: string;
}

let cache: Map<string, Shot> | null = null;

export function shots(): Map<string, Shot> {
  if (cache) return cache;
  const out = new Map<string, Shot>();
  const file = join(process.cwd(), "public", "shots", "docs", "manifest.json");
  if (existsSync(file)) {
    try {
      const raw = JSON.parse(readFileSync(file, "utf8"));
      const list: Shot[] = Array.isArray(raw) ? raw : Array.isArray(raw.images) ? raw.images : Array.isArray(raw.shots) ? raw.shots : Object.values(raw);
      for (const s of list) if (s && typeof s.file === "string") out.set(s.file.replace(/^.*\//, ""), s);
    } catch {
      // A broken manifest only costs the intrinsic sizes.
    }
  }
  cache = out;
  return out;
}

const DOC_SHOT = /(?:^|\/)shots\/docs\/([^/?#]+)$/;

/** The file name of a docs screenshot path, or null for any other image. */
export function shotName(src: string): string | null {
  const m = src.match(DOC_SHOT);
  return m ? m[1] : null;
}

/** Numbered callouts over a capture, as percentages of its width and height. The legend is the ordered list that
 *  follows the image in the Markdown, so the page reads the same on GitHub; item n belongs to hotspot n. */
export const HOTSPOTS: Record<string, { x: number; y: number }[]> = {};
