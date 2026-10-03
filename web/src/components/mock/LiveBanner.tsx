"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { AlarmClock, ChevronDown, Mic, Send, Square, X } from "lucide-react";
import MiniIcon from "@/components/landing/MiniIcon";
import { EASE } from "@/lib/config";

export interface BItem { id: string; title: string; body: string }
export type BRole = "open" | "deploy" | "snooze" | "dismiss";
export interface BButton { label: string; role: BRole; primary?: boolean; url?: string }
export interface ReplyCfg { transcript: string }

const RECEIPTS = ["received", "displayed", "spoken", "replied"];

/**
 * A Herald banner that behaves like one: Open runs the URL action, Deploy asks inline (Yes/Cancel), the callback
 * must answer before the banner goes, Snooze takes it away and brings it back, x dismisses (to History), a stack
 * shows a counter and fans out on click, and a cloud banner takes a typed or recorded reply.
 */
export default function LiveBanner({
  app,
  items,
  buttons = [],
  confirmText,
  reply,
  delay = 0,
  snoozeSeconds = 3,
  snoozeLabel = "9:00",
  onClose,
  onDismissItem,
}: {
  app: string;
  items: BItem[];
  buttons?: BButton[];
  confirmText?: string;
  reply?: ReplyCfg;
  delay?: number;
  snoozeSeconds?: number;
  snoozeLabel?: string;
  onClose: () => void;
  onDismissItem?: (id: string) => void;
}) {
  const reduce = useReducedMotion();
  const [phase, setPhase] = useState<"idle" | "confirm" | "working" | "snoozed">("idle");
  const [note, setNote] = useState<string | null>(null);
  const [left, setLeft] = useState(0);
  const [expanded, setExpanded] = useState(false);
  const timers = useRef<number[]>([]);
  const later = (fn: () => void, ms: number) => {
    timers.current.push(window.setTimeout(fn, ms));
  };
  useEffect(() => {
    const t = timers.current;
    return () => t.forEach(clearTimeout);
  }, []);

  const top = items[0];
  const count = items.length;
  const stacked = count > 1;
  const dur = reduce ? 0 : 0.32;

  const flash = (text: string, ms = 2600) => {
    setNote(text);
    later(() => setNote((n) => (n === text ? null : n)), ms);
  };

  const startSnooze = () => {
    let n = snoozeSeconds;
    setLeft(n);
    setPhase("snoozed");
    const id = window.setInterval(() => {
      n -= 1;
      setLeft(n);
      if (n <= 0) {
        clearInterval(id);
        setPhase("idle");
        flash(`Back from snooze (set for ${snoozeLabel})`);
      }
    }, 1000);
    timers.current.push(id);
  };

  const press = (b: BButton) => {
    if (b.role === "open") flash(`Opened ${b.url ?? "the link"}`);
    else if (b.role === "deploy") setPhase("confirm");
    else if (b.role === "snooze") startSnooze();
    else if (stacked) onDismissItem?.(top.id);
    else onClose();
  };
  const yes = () => {
    setPhase("working");
    later(() => {
      setPhase("idle");
      setNote("Callback answered 200 OK. Banner dismissed, kept in History.");
      later(onClose, 1500);
    }, 1100);
  };

  // reply state (cloud banners)
  const [text, setText] = useState("");
  const [rec, setRec] = useState(0);
  const [heard, setHeard] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const finishRec = () => {
    setRec(0);
    if (reply) {
      setHeard(reply.transcript);
      setText(reply.transcript);
      input.current?.focus();
    }
  };
  useEffect(() => {
    if (rec <= 0) return;
    const id = window.setTimeout(() => (rec === 1 ? finishRec() : setRec(rec - 1)), 1000);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rec]);
  const send = () => {
    const v = text.trim();
    if (!v) return;
    setSent(v);
    setText("");
    setHeard(null);
  };

  const enter = reduce ? { duration: 0 } : { duration: 0.52, ease: EASE.expo, delay };
  const ghosts = stacked && !expanded ? 2 : 0;

  return (
    <motion.div
      layout="position"
      role="group"
      aria-label={`${app} banner`}
      initial={reduce ? false : { opacity: 0, x: 24 }}
      animate={{ opacity: 1, x: 0, transition: enter }}
      exit={{ opacity: 0, x: reduce ? 0 : 24, transition: { duration: reduce ? 0 : 0.32, ease: EASE.expo } }}
      transition={{ layout: { duration: dur, ease: EASE.quint } }}
      style={{ paddingBottom: ghosts * 7 }}
      className="relative"
    >
      {ghosts > 0 &&
        [1, 0].map((g) => (
          <span key={g} aria-hidden className="mb absolute inset-x-0 bottom-0" style={{ height: 40, marginInline: (g + 1) * 7, opacity: 0.55 - g * 0.15, zIndex: 0 }} />
        ))}
      <div className="mb relative z-[1] p-3" style={{ borderRadius: 12 }}>
        {phase === "snoozed" ? (
          <p className="m-0 flex items-center gap-2.5 text-[13px]" role="status">
            <AlarmClock aria-hidden size={16} className="shrink-0 text-accent" />
            <span className="min-w-0 flex-1 truncate">
              <b className="font-semibold">{app}</b> snoozed · returns at {snoozeLabel}
            </span>
            <span className="mono shrink-0 text-[11px]" style={{ color: "var(--mb-muted)" }}>back in {Math.max(left, 0)} s (demo)</span>
          </p>
        ) : (
          <>
            <div className="flex items-start gap-2.5">
              <MiniIcon size={32} />
              {stacked ? (
                <button type="button" className="min-w-0 flex-1 cursor-pointer border-0 bg-transparent p-0 text-left text-inherit" aria-expanded={expanded} onClick={() => setExpanded((v) => !v)}>
                  <Head app={app} title={top.title} />
                </button>
              ) : (
                <div className="min-w-0 flex-1"><Head app={app} title={top.title} /></div>
              )}
              {stacked && (
                <motion.span
                  key={count}
                  initial={reduce ? false : { scale: 1.6 }}
                  animate={{ scale: 1 }}
                  transition={{ duration: 0.3, ease: EASE.quart }}
                  className="mono grid h-5 min-w-5 shrink-0 place-items-center rounded-full px-1.5 text-[11px] font-bold"
                  style={{ background: "var(--signal)", color: "#fff5f2" }}
                  aria-label={`${count} banners in this stack`}
                >
                  {count}
                </motion.span>
              )}
              {stacked && (
                <ChevronDown aria-hidden size={14} className="mt-1.5 shrink-0" style={{ color: "var(--mb-muted)", transform: expanded ? "rotate(180deg)" : "none", transition: "transform 200ms" }} />
              )}
              <button type="button" className="mb-x shrink-0" aria-label={stacked ? `Dismiss all ${count}` : "Dismiss"} onClick={onClose}>
                <X size={15} aria-hidden />
              </button>
            </div>
            <p className="m-0 mt-1.5 pl-[42px] text-[12.5px] leading-snug" style={{ color: "var(--mb-muted)" }}>{top.body}</p>

            <AnimatePresence initial={false}>
              {expanded && stacked && (
                <motion.ul
                  key="list"
                  initial={reduce ? false : { height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: dur, ease: EASE.quint }}
                  className="m-0 mt-2 list-none overflow-hidden p-0 pl-[42px]"
                >
                  {items.slice(1).map((it) => (
                    <li key={it.id} className="flex items-center gap-2 border-t py-1.5" style={{ borderColor: "var(--mb-line)" }}>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[12.5px] font-medium">{it.title}</span>
                        <span className="block truncate text-[11.5px]" style={{ color: "var(--mb-muted)" }}>{it.body}</span>
                      </span>
                      <button type="button" className="mb-x" aria-label={`Dismiss ${it.title}`} onClick={() => onDismissItem?.(it.id)}>
                        <X size={13} aria-hidden />
                      </button>
                    </li>
                  ))}
                </motion.ul>
              )}
            </AnimatePresence>

            {buttons.length > 0 && (
              <div className="mt-3 pl-[42px]">
                {phase === "confirm" ? (
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="mr-1 text-[13px] font-medium">{confirmText ?? "Run this action?"}</span>
                    <button type="button" className="mb-btn is-primary" onClick={yes}>Yes, deploy</button>
                    <button type="button" className="mb-btn" onClick={() => setPhase("idle")}>Cancel</button>
                  </div>
                ) : phase === "working" ? (
                  <p className="m-0 flex h-9 items-center gap-2 text-[13px]" role="status">
                    <motion.span aria-hidden className="size-2 rounded-full bg-accent" animate={reduce ? undefined : { opacity: [1, 0.25, 1] }} transition={{ duration: 0.8, repeat: Infinity }} />
                    Waiting for ci.bot to confirm the callback…
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {buttons.map((b) => (
                      <button key={b.label} type="button" className={`mb-btn ${b.primary ? "is-primary" : ""}`} onClick={() => press(b)}>
                        {b.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            {reply && (
              <div className="mt-3 pl-[42px]">
                {rec > 0 ? (
                  <div className="flex h-10 items-center gap-3 rounded-lg px-3 text-[13px]" style={{ background: "var(--mb-field)", border: "1px solid var(--mb-line)" }} role="status">
                    <motion.span aria-hidden className="size-2.5 rounded-full" style={{ background: "var(--signal)" }} animate={reduce ? undefined : { opacity: [1, 0.3, 1] }} transition={{ duration: 0.9, repeat: Infinity }} />
                    <span className="flex-1">Recording… <span className="mono">0:0{4 - rec}</span></span>
                    <button type="button" className="mb-btn" style={{ height: 30 }} onClick={finishRec}><Square size={12} aria-hidden />Stop</button>
                  </div>
                ) : (
                  <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); send(); }}>
                    <input ref={input} className="mb-input" value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a reply…" aria-label="Reply to the agent" />
                    <button type="button" className="mb-btn is-danger" style={{ height: 40 }} onClick={() => { setSent(null); setHeard(null); setRec(3); }}><Mic size={15} aria-hidden />Record</button>
                    <button type="submit" className="mb-btn is-primary" style={{ height: 40 }} disabled={!text.trim()}><Send size={14} aria-hidden />Send</button>
                  </form>
                )}
                {heard && <p className="m-0 mt-2 text-[12.5px]" style={{ color: "var(--mb-muted)" }}>Transcript: “{heard}” · press Send to deliver</p>}
                {sent && (
                  <p className="m-0 mt-2 text-[12.5px]" role="status">
                    You: “{sent}” · <b className="font-semibold text-accent">delivered to the agent</b>
                  </p>
                )}
                <p className="m-0 mt-2 text-[11.5px]" style={{ color: "var(--mb-muted)" }}>
                  Receipts:{" "}
                  {RECEIPTS.map((r, i) => {
                    const lit = i < 3 || !!sent;
                    return (
                      <span key={r} style={{ color: lit ? "var(--mb-ink)" : undefined, opacity: lit ? 1 : 0.55, transition: "opacity 300ms, color 300ms" }}>
                        {r}{i < 3 ? " · " : ""}
                      </span>
                    );
                  })}
                </p>
              </div>
            )}

            {note && (
              <p className="m-0 mt-2 pl-[42px] text-[12.5px]" role="status" style={{ color: "var(--accent)" }}>
                {note}
              </p>
            )}
          </>
        )}
      </div>
    </motion.div>
  );
}

function Head({ app, title }: { app: string; title: string }) {
  return (
    <>
      <span className="mono block text-[10px] uppercase leading-tight tracking-[0.06em]" style={{ color: "var(--mb-muted)" }}>{app}</span>
      <span className="block truncate text-[15px] font-medium leading-snug">{title}</span>
    </>
  );
}
