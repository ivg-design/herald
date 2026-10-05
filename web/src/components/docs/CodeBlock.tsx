"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { Check, Copy } from "lucide-react";

interface Props {
  children?: ReactNode;
  "data-raw"?: string;
  "data-lang"?: string;
  "data-title"?: string;
}

const LABELS: Record<string, string> = { sh: "shell", bash: "shell", shell: "shell", zsh: "shell", json: "JSON", js: "JavaScript", javascript: "JavaScript", ts: "TypeScript", swift: "Swift", python: "Python", py: "Python", http: "HTTP", yaml: "YAML", md: "Markdown", toml: "TOML", text: "text", txt: "text", html: "HTML", css: "CSS", xml: "XML", ini: "INI", diff: "diff", lua: "Lua" };

async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.cssText = "position:fixed;opacity:0;top:0;left:0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      ta.remove();
      return ok;
    } catch {
      return false;
    }
  }
}

export default function CodeBlock({ children, "data-raw": raw = "", "data-lang": lang, "data-title": title }: Props) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  const label = lang ? LABELS[lang] ?? lang : "";

  async function onCopy() {
    const ok = await copyText(raw);
    setState(ok ? "copied" : "failed");
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setState("idle"), 1800);
  }

  return (
    <div className="code-block" data-titled={title ? "" : undefined}>
      <div className="code-bar">
        {title && <span className="code-title">{title}</span>}
        <span className="code-lang">{label}</span>
        <button type="button" className="code-copy" onClick={onCopy} data-state={state}>
          {state === "copied" ? <Check size={14} aria-hidden /> : <Copy size={14} aria-hidden />}
          <span>{state === "copied" ? "Copied" : state === "failed" ? "Copy failed" : "Copy"}</span>
        </button>
        <span className="sr-only" aria-live="polite" role="status">
          {state === "copied" ? "Copied to clipboard" : state === "failed" ? "Copy failed" : ""}
        </span>
      </div>
      <pre>{children}</pre>
    </div>
  );
}
