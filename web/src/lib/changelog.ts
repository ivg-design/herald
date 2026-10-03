import { readFileSync } from "node:fs";
import { join } from "node:path";

export interface ChangelogEntry {
  version: string;
  build: string | null;
  date: string;
  body: string; // markdown below the heading
  summary: string; // one line for the landing page
}

function plain(s: string): string {
  return s.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/[`*_]/g, "").replace(/\s+/g, " ").trim();
}

function sentence(parts: string[]): string {
  if (!parts.length) return "";
  return `${parts.join("; ")}.`;
}

export function parseChangelog(): ChangelogEntry[] {
  let text = "";
  try {
    text = readFileSync(join(process.cwd(), "content", "CHANGELOG.md"), "utf8");
  } catch {
    return [];
  }
  const entries: ChangelogEntry[] = [];
  const parts = text.split(/^## /m).slice(1);
  for (const part of parts) {
    const nl = part.indexOf("\n");
    const head = part.slice(0, nl);
    const m = head.match(/^(\S+)(?: \([Bb]uild (\d+)\))?(?: - (.+))?$/);
    if (!m) continue;
    const body = part.slice(nl + 1).trim();
    // Landing summary: the bold lead of each bullet, joined; falls back to first bullet text.
    const leads = [...body.matchAll(/^- \*\*(.+?)\*\*/gm)].map((x) => plain(x[1]).replace(/[.:]$/, ""));
    let summary = sentence(leads.slice(0, 4));
    if (!summary) {
      const first = body.split("\n").find((l) => l.startsWith("- "));
      summary = first ? plain(first.slice(2)).replace(/[.:]?$/, ".") : "";
    }
    if (summary.length > 190) summary = summary.slice(0, 187).replace(/\s+\S*$/, "") + "…";
    entries.push({ version: m[1], build: m[2] ?? null, date: m[3] ?? "", body, summary });
  }
  return entries;
}
