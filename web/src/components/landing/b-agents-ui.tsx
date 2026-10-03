"use client";
import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { Check } from "lucide-react";
import { asset } from "@/lib/config";
import { useHerald } from "@/components/herald/useHerald";
import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { copyText } from "./b-hooks";

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
    <div className="mt-5">
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
        {failed ? "Copy is not available in this browser." : copied ? "Copied the herald-mcp config." : "How to install opens the steps for that client in the docs. The app does the same in one click."}
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

export function ToolList() {
  const herald = useHerald();
  const [preview, setPreview] = useState(false);
  const [state, setState] = useState(false);

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

  const readout = JSON.stringify({ onScreen: herald.onScreen, stacks: herald.pending, history: herald.history, snoozed: herald.snoozed }).replace(/,/g, ", ").replace(/:/g, ": ");
  return (
    <ul className="mono m-0 mt-5 flex list-none flex-col border-t border-line p-0 text-[13px] leading-snug text-muted">
      {TOOLS.map(([name, desc]) => {
        const demo = DEMOS[name];
        const open = demo === "preview" ? preview : demo === "state" ? state : undefined;
        return (
          <li key={name} className="tool-row min-h-[52px] border-b border-line py-3">
            <div className="flex items-start gap-3">
              <Check aria-hidden className="mt-[3px] size-3.5 shrink-0 text-accent" />
              <span className="flex min-w-0 flex-wrap items-center gap-y-2">
                <span className="min-w-0">
                  <span className="text-ink">{name}</span>: {desc}
                </span>
                {demo && (
                  <button
                    type="button"
                    className="tool-try btn btn-ghost btn-sm ml-3 shrink-0 !h-7 !px-3 !text-[13px]"
                    aria-label={`Try ${name}`}
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
