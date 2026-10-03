"use client";
import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "framer-motion";
import Image from "next/image";
import { Check } from "lucide-react";
import { asset } from "@/lib/config";
import { useHerald } from "@/components/herald/useHerald";
import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { copyText, useInViewOnce } from "./b-hooks";

const SNIPPET = '{"mcpServers":{"herald":{"command":"herald-mcp"}}}';
const ROWS: { name: string; href?: string }[] = [
  { name: "Claude Code", href: "/docs/more/mcp-guide#claude-code" },
  { name: "Codex CLI", href: "/docs/more/mcp-guide#codex" },
  { name: "Claude Desktop", href: "/docs/more/mcp-guide#one-click-settings--mcp" },
  { name: "Generic (JSON)" },
];

export function McpMock() {
  const [copied, setCopied] = useState(false);
  const [failed, setFailed] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const onCopy = async () => {
    const ok = await copyText(SNIPPET);
    setFailed(!ok);
    setCopied(ok);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setCopied(false), 2200);
  };
  return (
    <div>
      <ul className="m-0 flex list-none flex-col border-t border-line p-0">
        {ROWS.map((r) => (
          <li key={r.name} className="flex min-h-14 items-center justify-between gap-3 border-b border-line py-2">
            <span className="text-[17px] font-semibold">{nowrapText(r.name)}</span>
            {r.href ? (
              <SiteLink href={r.href} className="btn btn-ghost btn-sm">How to install</SiteLink>
            ) : (
              <button type="button" onClick={onCopy} className="btn btn-ghost btn-sm" style={copied ? { color: "var(--accent-text)", borderColor: "var(--blue)" } : undefined}>
                {copied ? "Copied" : "Copy config"}
              </button>
            )}
          </li>
        ))}
      </ul>
      <p className="readout m-0 mt-3" role="status" aria-live="polite">
        {failed ? "Copy is not available in this browser." : copied ? "Copied the herald-mcp config." : "The app installs these for you with one click; here each links to the steps."}
      </p>
    </div>
  );
}

const TOOLS: [string, string][] = [
  ["put_manifest", "declare fields, samples, actions"],
  ["put_template / validate_template", "the grid, checked"],
  ["render_preview", "a PNG from the real renderer, no window"],
  ["add_action_rule", "attach a script, Shortcut or callback"],
  ["send_test / speak", "show it for real, hear it"],
  ["list_history / list_stacks", "read what was shown"],
];

type Demo = "send" | "preview" | "state";
const DEMOS: Record<string, Demo> = { "send_test / speak": "send", render_preview: "preview", "list_history / list_stacks": "state" };

/** Typing plays once per page load, whatever re-renders or remounts the list. */
let typedOnce = false;

export function ToolList() {
  const reduced = useReducedMotion();
  const herald = useHerald();
  const ref = useRef<HTMLUListElement>(null);
  const seen = useInViewOnce(ref, 0.5);
  const lines = TOOLS.map(([n, d]) => `${n}: ${d}`);
  const GAP = 7; // ≈120 ms pause between rows at 18 ms/char
  const total = lines.reduce((a, l) => a + l.length + GAP, 0) - GAP;
  const [typed, setTyped] = useState(typedOnce ? Infinity : 0);
  const done = reduced || typed >= total;
  const [preview, setPreview] = useState(false);
  const [state, setState] = useState(false);

  useEffect(() => {
    if (reduced || !seen || typedOnce) return;
    let n = 0;
    const id = setInterval(() => {
      n += 1;
      setTyped(n);
      if (n >= total) {
        typedOnce = true;
        clearInterval(id);
      }
    }, 18);
    return () => clearInterval(id);
  }, [reduced, seen, total]);

  const act = (d: Demo) => {
    if (d === "send") {
      herald.send({
        app: "claude",
        appName: "Claude Code",
        icon: "claude",
        title: "Build finished",
        body: "All 214 tests passed in 38 s.",
        buttons: [
          { label: "Open", role: "open", primary: true, url: "the build log" },
          { label: "Reply", role: "dismiss" },
        ],
        speak: true,
      });
    } else if (d === "preview") setPreview((v) => !v);
    else setState((v) => !v);
  };

  const shown = reduced ? total : Math.min(typed, total);
  const starts = lines.reduce<number[]>((acc, l, i) => [...acc, i === 0 ? 0 : acc[i - 1] + lines[i - 1].length + GAP], []);
  const readout = JSON.stringify({ onScreen: herald.onScreen, stacks: herald.pending, history: herald.history, snoozed: herald.snoozed }).replace(/,/g, ", ").replace(/:/g, ": ");
  return (
    <ul ref={ref} className="mono m-0 mt-6 flex list-none flex-col border-t border-line p-0 text-[13px] leading-snug text-muted">
      {lines.map((l, i) => {
        const k = Math.max(0, Math.min(l.length, shown - starts[i]));
        const demo = DEMOS[TOOLS[i][0]];
        const open = demo === "preview" ? preview : demo === "state" ? state : undefined;
        return (
          <li key={l} className="tool-row min-h-[52px] border-b border-line py-3" style={{ opacity: done || k > 0 ? 1 : 0 }}>
            <div className="flex items-start gap-3">
              <Check aria-hidden className="mt-[3px] size-3.5 shrink-0 text-accent" />
              <span className="sr-only">{l}</span>
              <span className="flex min-w-0 flex-wrap items-center gap-y-2">
                <span aria-hidden className="min-w-0">
                  {l.slice(0, k)}
                  <span className="opacity-0">{l.slice(k)}</span>
                </span>
                {demo && (
                  <button
                    type="button"
                    className="tool-try btn btn-ghost btn-sm ml-3 shrink-0 !h-7 !px-3 !text-[13px]"
                    aria-label={`Try ${TOOLS[i][0]}`}
                    aria-expanded={open}
                    onClick={() => act(demo)}
                  >
                    {open ? "hide" : "try"}
                  </button>
                )}
              </span>
            </div>
            {demo === "preview" && preview && (
              <figure className="m-0 ml-[26px] mt-3 max-w-[460px]">
                <div className="overflow-hidden rounded-xl border border-line bg-bg p-2">
                  <Image src={asset("/shots/banner-plain.png")} alt="Banner rendered by render_preview" width={920} height={406} unoptimized className="h-auto w-full" />
                </div>
                <figcaption className="readout mt-2">render_preview returns a PNG from the real renderer, no window</figcaption>
              </figure>
            )}
            {demo === "state" && state && (
              <p className="m-0 ml-[26px] mt-3 readout rounded-lg border border-line bg-surface px-3 py-2 text-ink" role="status" aria-live="polite" aria-label="Herald state readout">{readout}</p>
            )}
          </li>
        );
      })}
    </ul>
  );
}
