"use client";

import { useEffect, useId, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { AlarmClock, ChevronDown, Mic, Send, Square, Volume2, X } from "lucide-react";
import { HeraldMark } from "@/components/landing/MiniIcon";
import StatusRing, { type RingState } from "@/components/rive/StatusRing";
import { playVoice, sampleName, stopVoice, usePlayingKey } from "@/components/herald/voice";
import type { HeraldIcon } from "@/components/herald/types";
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
  icon = "herald",
  speaking = false,
  status,
  onClose,
  onDismissItem,
  onSnoozeChange,
  speak,
  onToggleVoice,
  fanMax = 3,
}: {
  app: string;
  items: BItem[];
  buttons?: BButton[];
  confirmText?: string;
  reply?: ReplyCfg;
  delay?: number;
  snoozeSeconds?: number;
  snoozeLabel?: string;
  icon?: HeraldIcon;
  /** Shows a small waveform next to the title while the banner is being spoken. */
  speaking?: boolean;
  /** Optional status ring shown next to the title. */
  status?: RingState;
  onClose: () => void;
  onDismissItem?: (id: string) => void;
  /** Reports snooze start/end so a host can count snoozed banners. */
  onSnoozeChange?: (snoozed: boolean) => void;
  /** Adds a "Play voice" / "Stop" button that plays the card's pre-rendered sample (click only). */
  onToggleVoice?: () => void;
  /** Standalone banners: same meaning as HeraldSend.speak. `true` plays voice-sample, a string plays /audio/<string>.mp3. */
  speak?: boolean | string;
  /** How many stacked items the fan shows; the rest collapse into a "+N more" line so the banner has a known tallest height. */
  fanMax?: number;
}) {
  const voiceKey = useId();
  const playingKey = usePlayingKey();
  const ownPlaying = playingKey === voiceKey;
  const sample = speak ? sampleName(speak) : undefined;
  const toggleVoice = onToggleVoice ?? (sample ? () => (ownPlaying ? stopVoice() : playVoice(voiceKey, sample)) : undefined);
  speaking = speaking || ownPlaying;
  useEffect(() => {
    return () => {
      if (playingKey === voiceKey) stopVoice();
    };
  }, [playingKey, voiceKey]);
  const reduce = useReducedMotion();
  const [phase, setPhase] = useState<"idle" | "confirm" | "working" | "done" | "snoozed">("idle");
  const [note, setNote] = useState<string | null>(null);
  const [left, setLeft] = useState(0);
  const [expanded, setExpanded] = useState(false);
  /** The fan clips only while its height animates, so a focus ring on a row's x is never cut. */
  const [settled, setSettled] = useState(true);
  const toggle = () => {
    setSettled(false);
    setExpanded((v) => !v);
  };
  const listId = useId();
  const timers = useRef<number[]>([]);
  const later = (fn: () => void, ms: number) => {
    timers.current.push(window.setTimeout(fn, ms));
  };
  const ticks = useRef<number[]>([]);
  const onSnoozeRef = useRef(onSnoozeChange);
  useEffect(() => {
    onSnoozeRef.current = onSnoozeChange;
  });
  useEffect(() => {
    const t = ticks.current;
    return () => {
      t.forEach(clearInterval);
      onSnoozeRef.current?.(false);
    };
  }, []);

  const top = items[0];
  const count = items.length;
  const stacked = count > 1;
  const rest = items.slice(1);
  const dur = reduce ? 0 : 0.32;

  const flash = (text: string, ms = 2600) => {
    setNote(text);
    later(() => setNote((n) => (n === text ? null : n)), ms);
  };

  const startSnooze = () => {
    let n = snoozeSeconds;
    setLeft(n);
    setPhase("snoozed");
    onSnoozeChange?.(true);
    const id = window.setInterval(() => {
      n -= 1;
      setLeft(n);
      if (n <= 0) {
        clearInterval(id);
        setPhase("idle");
        onSnoozeChange?.(false);
        flash(`Back from snooze (set for ${snoozeLabel})`);
      }
    }, 1000);
    ticks.current.push(id);
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
      setPhase("done");
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
    setSent(v.length > 56 ? `${v.slice(0, 55)}…` : v);
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
      exit={{ opacity: 0, x: reduce ? 0 : 24, transition: { duration: reduce ? 0 : 0.39, ease: EASE.expo } }}
      transition={{ layout: { duration: dur, ease: EASE.quint } }}
      style={{ paddingBottom: ghosts * 6 }}
      className="relative hb-card"
    >
      {ghosts > 0 && (
        <>
          <span aria-hidden className="hb-ghost" style={{ bottom: 6, marginInline: 7, opacity: 0.55 }} />
          <span aria-hidden className="hb-ghost" style={{ bottom: 0, marginInline: 14, opacity: 0.4 }} />
        </>
      )}
      <div className="mb relative z-[1] p-3 font-sans">
        {phase === "snoozed" ? (
          <p className="m-0 flex items-center gap-2.5 text-[13px]" role="status">
            <AlarmClock aria-hidden size={16} className="shrink-0 text-blue" />
            <span className="min-w-0 flex-1 truncate">
              <b className="font-semibold">{app}</b> snoozed · returns at {snoozeLabel}
            </span>
            <span className="shrink-0 font-mono text-[11px]" style={{ color: "var(--mb-muted)" }}>back in {Math.max(left, 0)} s (demo)</span>
          </p>
        ) : (
          <>
            <div className="flex items-start gap-2.5">
              <HeraldMark icon={icon} size={32} />
              {stacked ? (
                <button type="button" className="min-w-0 flex-1 cursor-pointer border-0 bg-transparent p-0 text-left text-inherit" aria-expanded={expanded} aria-controls={listId} onClick={toggle}>
                  <Head app={app} title={top.title} speaking={speaking} status={status} />
                </button>
              ) : (
                <div className="min-w-0 flex-1"><Head app={app} title={top.title} speaking={speaking} status={status} /></div>
              )}
              {stacked && (
                <button type="button" className="hb-chip" aria-label={`${count} banners in this stack`} aria-expanded={expanded} aria-controls={listId} onClick={toggle}>
                  <motion.span
                    key={count}
                    initial={reduce ? false : { scale: 1.6 }}
                    animate={{ scale: 1 }}
                    transition={{ duration: 0.3, ease: EASE.quart }}
                    className="grid h-5 min-w-5 place-items-center rounded-full px-1.5 font-mono text-[11px] font-semibold"
                    style={{ background: "var(--red)", color: "#fff" }}
                  >
                    {count}
                  </motion.span>
                </button>
              )}
              {stacked && (
                <button type="button" className="hb-chip hb-chip-chev" aria-label={expanded ? "Collapse stack" : "Expand stack"} aria-expanded={expanded} aria-controls={listId} onClick={toggle}>
                  <ChevronDown aria-hidden size={14} style={{ transform: expanded ? "rotate(180deg)" : "none", transition: "transform 200ms" }} />
                </button>
              )}
              <button type="button" className="mb-x shrink-0" aria-label={stacked ? `Dismiss all ${count}` : "Dismiss"} onClick={onClose}>
                <X size={15} aria-hidden />
              </button>
            </div>
            <p className="m-0 mt-1.5 pl-[42px] text-[13.5px] leading-[1.45]" style={{ color: "var(--mb-muted)" }}>{top.body}</p>

            <AnimatePresence initial={false}>
              {expanded && stacked && (
                <motion.ul
                  key="list"
                  id={listId}
                  initial={reduce ? false : { height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: dur, ease: EASE.quint }}
                  onAnimationComplete={() => setSettled(true)}
                  className="m-0 mt-2 list-none p-0 pl-[42px]"
                  style={{ overflow: settled || reduce ? "visible" : "hidden" }}
                >
                  {rest.slice(0, fanMax).map((it) => (
                    <li key={it.id} className="flex items-center gap-2 border-t py-1" style={{ borderColor: "var(--mb-line)" }}>
                      <span className="min-w-0 flex-1 truncate text-[13px]">
                        <span className="font-medium">{it.title}</span>
                        <span className="ml-2 text-[11.5px]" style={{ color: "var(--mb-muted)" }}>{it.body}</span>
                      </span>
                      <button type="button" className="mb-x shrink-0" aria-label={`Dismiss ${it.title}`} onClick={() => onDismissItem?.(it.id)}>
                        <X size={13} aria-hidden />
                      </button>
                    </li>
                  ))}
                  {rest.length > fanMax && (
                    <li className="border-t py-1.5 text-[12px]" style={{ borderColor: "var(--mb-line)", color: "var(--mb-muted)" }}>
                      +{rest.length - fanMax} more, dismiss one to see the next
                    </li>
                  )}
                </motion.ul>
              )}
            </AnimatePresence>

            {(buttons.length > 0 || !!toggleVoice || phase === "done") && (
              <div className={phase === "idle" ? "mt-3 pl-[42px]" : "mt-3 border-t pl-[42px] pt-3"} style={phase === "idle" ? undefined : { borderColor: "var(--mb-line)" }}>
                {phase === "confirm" ? (
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="mr-1 text-[13.5px] font-medium">{confirmText ?? "Run this action?"}</span>
                    <button type="button" className="mb-btn is-primary" onClick={yes}>Yes, deploy</button>
                    <button type="button" className="mb-btn" onClick={() => setPhase("idle")}>Cancel</button>
                  </div>
                ) : phase === "working" ? (
                  <p className="m-0 flex min-h-9 items-center gap-2 text-[13px]" role="status">
                    <StatusRing state="working" size={20} />
                    Waiting for {app} to confirm the callback…
                  </p>
                ) : phase === "done" ? (
                  <p className="m-0 flex min-h-9 items-center gap-2 text-[13px]" role="status">
                    <StatusRing state="done" size={20} />
                    Callback answered 200 OK. Banner dismissed, kept in History.
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {buttons.map((b) => (
                      <button key={b.label} type="button" className={`mb-btn ${b.primary ? "is-primary" : ""}`} onClick={() => press(b)}>
                        {b.label}
                      </button>
                    ))}
                    {toggleVoice && (
                      <button type="button" className="mb-btn hb-play" aria-pressed={speaking} onClick={toggleVoice}>
                        {speaking ? <Square size={12} aria-hidden /> : <Volume2 size={14} aria-hidden />}
                        {speaking ? "Stop" : "Play voice"}
                      </button>
                    )}
                  </div>
                )}
              </div>
            )}

            {reply && (
              <div className="mt-3 pl-[42px]">
                {rec > 0 ? (
                  <div className="flex h-10 items-center gap-3 rounded-lg px-3 text-[13px]" style={{ background: "var(--mb-field)", border: "1px solid var(--mb-line)" }} role="status">
                    <motion.span aria-hidden className="size-2.5 rounded-full" style={{ background: "var(--red)" }} animate={reduce ? undefined : { opacity: [1, 0.3, 1] }} transition={{ duration: 0.9, repeat: Infinity }} />
                    <span className="flex-1">Recording… <span className="font-mono">0:0{4 - rec}</span></span>
                    <button type="button" className="mb-btn" style={{ height: 30 }} onClick={finishRec}><Square size={12} aria-hidden />Stop</button>
                  </div>
                ) : (
                  <form className="flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); send(); }}>
                    <input ref={input} className="mb-input" style={{ flex: "1 1 160px" }} value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a reply…" aria-label="Reply to the agent" />
                    <button type="button" className="mb-btn is-danger" style={{ height: 40 }} onClick={() => { setSent(null); setHeard(null); setRec(3); }}><Mic size={15} aria-hidden />Record</button>
                    <button type="submit" className="mb-btn is-primary" style={{ height: 40 }} disabled={!text.trim()}><Send size={14} aria-hidden />Send</button>
                  </form>
                )}
                {heard && <p className="m-0 mt-2 text-[12.5px]" style={{ color: "var(--mb-muted)" }}>Transcript: “{heard}” · press Send to deliver</p>}
                {sent && (
                  <p className="m-0 mt-2 text-[12.5px]" role="status">
                    You: “{sent}” · <b className="font-semibold text-blue">delivered to the agent</b>
                  </p>
                )}
                <p className="m-0 mt-2 text-[11.5px]" style={{ color: "var(--mb-muted)" }}>
                  Receipts:{" "}
                  {RECEIPTS.map((r, i) => {
                    const lit = i < 3 || !!sent;
                    return (
                      <span key={r} style={{ color: lit ? "var(--mb-ink)" : undefined, opacity: lit ? 1 : 0.85, transition: "opacity 300ms, color 300ms" }}>
                        {r}{i < 3 ? " · " : ""}
                      </span>
                    );
                  })}
                </p>
              </div>
            )}

            {note && (
              <p className="m-0 mt-2 pl-[42px] text-[12.5px]" role="status" style={{ color: "var(--blue)" }}>
                {note}
              </p>
            )}
          </>
        )}
      </div>
    </motion.div>
  );
}

function Head({ app, title, speaking, status }: { app: string; title: string; speaking: boolean; status?: RingState }) {
  return (
    <>
      <span className="block truncate font-mono text-[12px] leading-tight tracking-[0.02em]" style={{ color: "var(--mb-muted)" }}>{app}</span>
      <span className="flex items-center gap-2">
        <span className="block min-w-0 truncate text-[15px] font-semibold leading-snug">{title}</span>
        {speaking && (
          <span className="hb-wave" role="img" aria-label="Speaking">
            <i /><i /><i /><i /><i />
          </span>
        )}
        {status && <StatusRing state={status} size={16} />}
      </span>
    </>
  );
}
