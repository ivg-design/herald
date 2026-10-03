"use client";
import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "framer-motion";
import { Check } from "lucide-react";
import { copyText, useInViewOnce } from "./b-hooks";

const SNIPPET = '{"mcpServers":{"herald":{"command":"herald-mcp"}}}';
const ROWS = [
  { name: "Claude Code", kind: "install" as const, done: true },
  { name: "Codex CLI", kind: "install" as const, done: false },
  { name: "Claude Desktop", kind: "install" as const, done: false },
  { name: "Generic (JSON)", kind: "copy" as const, done: false },
];

export function McpMock() {
  const [state, setState] = useState<Record<string, boolean>>({ "Claude Code": true });
  const [status, setStatus] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  const flip = (name: string, label: string, auto = false) => {
    setState((s) => ({ ...s, [name]: true }));
    setStatus(`${name}: ${label}`);
    if (auto) {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setState((s) => ({ ...s, [name]: false })), 2200);
    }
  };
  const onCopy = async (name: string) => {
    const ok = await copyText(SNIPPET);
    if (ok) flip(name, "Copied", true);
    else setStatus("Copy is not available in this browser.");
  };

  return (
    <div className="rounded-xl border border-line bg-surface p-4 md:p-5">
      <p className="mono m-0 mb-3 text-[12px] font-bold tracking-wide text-muted">Settings → MCP</p>
      <ul className="m-0 flex list-none flex-col gap-3 p-0">
        {ROWS.map((r) => {
          const on = !!state[r.name];
          return (
            <li key={r.name} className="flex min-h-12 items-center justify-between gap-3 rounded-lg border border-line bg-bg px-3.5 py-1.5">
              <span className="text-[14px] font-medium">{r.name}</span>
              {r.kind === "install" ? (
                <button
                  type="button"
                  disabled={on}
                  onClick={() => flip(r.name, "Installed")}
                  className="mini-btn is-primary !h-10 min-w-[84px] justify-center !px-3 disabled:cursor-default"
                  style={on ? { background: "var(--surface-2)", color: "var(--muted)" } : undefined}
                >
                  {on ? "Installed ✓" : "Install"}
                </button>
              ) : (
                <button type="button" onClick={() => onCopy(r.name)} className="mini-btn is-primary !h-10 min-w-[84px] justify-center !px-3" style={on ? { background: "var(--surface-2)", color: "var(--muted)" } : undefined}>
                  {on ? "Copied ✓" : "Copy config"}
                </button>
              )}
            </li>
          );
        })}
      </ul>
      <p className="sr-only" role="status" aria-live="polite">{status}</p>
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

export function ToolList() {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLUListElement>(null);
  const seen = useInViewOnce(ref, 0.5);
  const lines = TOOLS.map(([n, d]) => `${n}: ${d}`);
  const total = lines.reduce((a, l) => a + l.length, 0);
  const [typed, setTyped] = useState(0);

  useEffect(() => {
    if (reduced || !seen) return;
    let n = 0;
    const id = setInterval(() => {
      n += 1;
      setTyped(n);
      if (n >= total) clearInterval(id);
    }, 20);
    return () => clearInterval(id);
  }, [reduced, seen, total]);

  const shown = reduced ? total : typed;
  let used = 0;
  return (
    <ul ref={ref} className="mono m-0 mt-4 flex list-none flex-col gap-2.5 p-0 text-[12.5px] leading-snug text-muted">
      {lines.map((l) => {
        const k = Math.max(0, Math.min(l.length, shown - used));
        used += l.length;
        return (
          <li key={l} className="flex items-start gap-3">
            <Check aria-hidden className="mt-0.5 size-3.5 shrink-0 text-accent" />
            <span className="sr-only">{l}</span>
            <span aria-hidden>
              {l.slice(0, k)}
              <span className="opacity-0">{l.slice(k)}</span>
            </span>
          </li>
        );
      })}
    </ul>
  );
}
