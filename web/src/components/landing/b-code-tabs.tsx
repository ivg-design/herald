"use client";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { Check, Copy, Play } from "lucide-react";
import { useHerald } from "@/components/herald/useHerald";
import SiteLink from "@/components/SiteLink";
import { copyText } from "./b-hooks";

const TABS = [
  {
    id: "curl",
    label: "curl",
    code: `curl -X POST http://127.0.0.1:48617/v1/notify \\
  -H "Authorization: Bearer $(cat ~/Library/Application\\ Support/Herald/token)" \\
  -H "Content-Type: application/json" \\
  -d '{"app":"ci.bot","title":"Build passed",
       "body":"142 tests, 0 failures",
       "buttons":[{"label":"Open","url":"https://ci.example.com/142"}],
       "speak":true}'`,
  },
  {
    id: "swift",
    label: "Swift",
    code: `import HeraldClient

let id = try await HeraldClient.shared.notify(HeraldNotification(
    app: "ci.bot", title: "Build passed", body: "142 tests, 0 failures",
    buttons: [HeraldButton(label: "Open", url: "https://ci.example.com/142")]))`,
  },
  {
    id: "python",
    label: "Python",
    code: `from herald import Herald

Herald().notify(app="ci.bot", title="Build passed", body="142 tests, 0 failures",
                buttons=[{"label": "Open", "url": "https://ci.example.com/142"}],
                speak=True)`,
  },
  {
    id: "node",
    label: "Node",
    code: `const { Herald } = require('./herald');

await new Herald().notify('ci.bot', 'Build passed', {
  body: '142 tests, 0 failures',
  buttons: [{ label: 'Open', url: 'https://ci.example.com/142' }],
  speak: true,
});`,
  },
  {
    id: "cli",
    label: "CLI",
    code: `herald notify --app ci.bot --title "Build passed" \\
  --body "142 tests, 0 failures" \\
  --button "Open=https://ci.example.com/142" --speak`,
  },
];

export default function CodeTabs() {
  const [i, setI] = useState(0);
  const [copied, setCopied] = useState(false);
  const [ran, setRan] = useState(false);
  const herald = useHerald();
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  const onKey = (e: KeyboardEvent) => {
    let n = i;
    if (e.key === "ArrowRight") n = (i + 1) % TABS.length;
    else if (e.key === "ArrowLeft") n = (i - 1 + TABS.length) % TABS.length;
    else if (e.key === "Home") n = 0;
    else if (e.key === "End") n = TABS.length - 1;
    else return;
    e.preventDefault();
    setI(n);
    refs.current[n]?.focus();
  };
  const onRun = () => {
    herald.send({
      app: "ci.bot",
      appName: "CI Bot",
      icon: "ci",
      title: "Build passed",
      body: "142 tests, 0 failures",
      buttons: [{ label: "Open", role: "open", primary: true, url: "ci.example.com/142" }],
      speak: true,
    });
    setRan(true);
  };
  const onCopy = async () => {
    if (await copyText(TABS[i].code)) {
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 1800);
    }
  };

  return (
    <div className="min-w-0">
      <div className="night overflow-hidden rounded-xl border border-line">
        <div className="flex items-center justify-between gap-2 border-b border-line px-2 py-2">
          <div role="tablist" aria-label="Language" className="flex gap-1 overflow-x-auto" onKeyDown={onKey}>
            {TABS.map((t, n) => (
              <button
                key={t.id}
                ref={(el) => { refs.current[n] = el; }}
                role="tab"
                id={`tab-${t.id}`}
                aria-selected={n === i}
                aria-controls={`panel-${t.id}`}
                tabIndex={n === i ? 0 : -1}
                onClick={() => setI(n)}
                className="btn btn-sm cursor-pointer !px-3.5"
                style={{
                  background: n === i ? "var(--surface-2)" : "transparent",
                  color: n === i ? "var(--ink)" : "var(--muted)",
                  borderColor: n === i ? "var(--blue)" : "transparent",
                }}
              >
                {t.label}
              </button>
            ))}
          </div>
          <div className="flex shrink-0 items-center gap-1.5">
            <button type="button" onClick={onCopy} className="btn btn-ghost btn-sm cursor-pointer" aria-label="Copy code">
              {copied ? <Check aria-hidden className="size-3.5" /> : <Copy aria-hidden className="size-3.5" />}
              {copied ? "Copied" : "Copy"}
            </button>
            <button type="button" onClick={onRun} className="btn btn-primary btn-sm cursor-pointer" aria-label="Run snippet">
              <Play aria-hidden className="size-3.5" /> Run
            </button>
          </div>
        </div>
        {TABS.map((t, n) => (
          <div key={t.id} role="tabpanel" id={`panel-${t.id}`} aria-labelledby={`tab-${t.id}`} hidden={n !== i} tabIndex={0}>
            <pre className="m-0 overflow-x-auto p-5 text-[13px] leading-[1.7]" style={{ fontFamily: "var(--font-mono)", letterSpacing: "0.02em", color: "var(--bone)" }}><code>{t.code}</code></pre>
          </div>
        ))}
        <p className="sr-only" role="status" aria-live="polite">{copied ? "Copied to clipboard" : ""}</p>
      </div>
      <p className="readout m-0 mt-3 min-h-[1.5em]" role="status" aria-live="polite" aria-label="Run outcome">
        {ran ? `Sent. Same payload, any language.` : ""}
      </p>
    </div>
  );
}

/** SHA-256 in mono, truncated, with a Copy button whose outcome reads "Copied". */
export function ShaCopy({ sha, href }: { sha: string; href: string | null }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const onCopy = async () => {
    if (await copyText(sha)) {
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 1800);
    }
  };
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      {href ? <SiteLink href={href} className="text-[15px] text-accent-text underline-offset-4 hover:underline">SHA-256</SiteLink> : <span className="text-[15px]">SHA-256</span>}
      <span className="mono text-muted" title={sha}>{sha.slice(0, 8)}…{sha.slice(-8)}</span>
      <button type="button" onClick={onCopy} className="btn btn-ghost btn-sm cursor-pointer" aria-label="Copy SHA-256">
        {copied ? <Check aria-hidden className="size-3.5" /> : <Copy aria-hidden className="size-3.5" />}
        {copied ? "Copied" : "Copy"}
      </button>
      <span className="sr-only" role="status" aria-live="polite">{copied ? "Copied" : ""}</span>
    </div>
  );
}
