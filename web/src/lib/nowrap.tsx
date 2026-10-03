import type { ReactNode } from "react";

/** Proper nouns and tokens that must never break across lines. */
export const NOWRAP_PHRASES = [
  "IVG Design",
  "Claude Code",
  "Claude Desktop",
  "Codex CLI",
  "Apple Silicon",
  "SF Symbols",
  "Notification Center",
  "Apple Shortcut",
  "Apple Shortcuts",
  "macOS 13.1+",
  "macOS 13.1",
  "Developer ID",
  "Kokoro voice",
  "WebWatcher",
];

const PATTERNS = [
  String.raw`\d+\.\d+\.\d+(?: \(Build \d+\))?`,
  String.raw`Build \d+`,
  String.raw`⌘[⇧⌥⌃]*[A-Z]`,
  String.raw`macOS \d+(?:\.\d+)?\+?`,
];

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const MATCHER = new RegExp(
  [...[...NOWRAP_PHRASES].sort((a, b) => b.length - a.length).map(esc), ...PATTERNS].join("|"),
  "g",
);

/** Split text and wrap each protected phrase in <span class="nowrap">. Server-safe, no hooks. */
export function nowrapText(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(MATCHER)) {
    const i = m.index ?? 0;
    if (i > last) out.push(text.slice(last, i));
    out.push(<span key={`nw-${i}`} className="nowrap">{m[0]}</span>);
    last = i + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}
