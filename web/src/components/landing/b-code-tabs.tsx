"use client";
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { Check, Copy } from "lucide-react";
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
  const onCopy = async () => {
    if (await copyText(TABS[i].code)) {
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 1800);
    }
  };

  return (
    <div className="min-w-0 overflow-hidden rounded-xl bg-bg text-ink">
      <div className="flex items-center justify-between border-b border-line pr-2">
        <div role="tablist" aria-label="Language" className="flex overflow-x-auto" onKeyDown={onKey}>
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
              className="h-11 min-w-[56px] cursor-pointer px-4 text-[13px] font-medium transition-[background-color,color] duration-200"
              style={{ background: n === i ? "var(--surface)" : "transparent", color: n === i ? "var(--ink)" : "var(--muted)" }}
            >
              {t.label}
            </button>
          ))}
        </div>
        <button type="button" onClick={onCopy} className="mini-btn !h-9 shrink-0 cursor-pointer gap-1.5 !px-3" aria-label="Copy code">
          {copied ? <Check aria-hidden className="size-3.5" /> : <Copy aria-hidden className="size-3.5" />}
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      {TABS.map((t, n) => (
        <div key={t.id} role="tabpanel" id={`panel-${t.id}`} aria-labelledby={`tab-${t.id}`} hidden={n !== i} tabIndex={0}>
          <pre className="mono m-0 overflow-x-auto p-5 text-[12.5px] leading-[1.7]"><code>{t.code}</code></pre>
        </div>
      ))}
      <p className="sr-only" role="status" aria-live="polite">{copied ? "Copied to clipboard" : ""}</p>
    </div>
  );
}
