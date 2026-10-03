"use client";
import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "framer-motion";
import { useInViewOnce } from "./b-hooks";

type Phase = "buttons" | "moving" | "strip";

/** Inline-confirmation demo: an invisible cursor presses Deploy, the row is swapped for Yes/Cancel, then returns. */
export default function ConfirmDemo() {
  const reduced = useReducedMotion();
  const box = useRef<HTMLDivElement>(null);
  const deploy = useRef<HTMLButtonElement>(null);
  const seen = useInViewOnce(box, 0.5);
  const [phase, setPhase] = useState<Phase>("buttons");
  const [pressed, setPressed] = useState(false);
  const [cursor, setCursor] = useState({ x: 0, y: 0, show: false });

  useEffect(() => {
    if (reduced || !seen) return;
    const b = box.current, d = deploy.current;
    if (!b || !d) return;
    const br = b.getBoundingClientRect(), dr = d.getBoundingClientRect();
    const tx = dr.left - br.left + dr.width * 0.55, ty = dr.top - br.top + dr.height * 0.6;
    const timers: ReturnType<typeof setTimeout>[] = [];
    const at = (ms: number, fn: () => void) => timers.push(setTimeout(fn, ms));
    setCursor({ x: tx + 90, y: ty + 46, show: false });
    at(350, () => { setPhase("moving"); setCursor({ x: tx, y: ty, show: true }); });
    at(1250, () => setPressed(true));
    at(1400, () => { setPressed(false); setPhase("strip"); setCursor((c) => ({ ...c, show: false })); });
    at(4200, () => setPhase("buttons"));
    return () => timers.forEach(clearTimeout);
  }, [reduced, seen]);

  const strip = reduced ? true : phase === "strip";
  const fade = "transition-[opacity,transform] duration-300 ease-[var(--ease-quint)]";

  return (
    <div ref={box} className="relative rounded-xl border border-line bg-surface p-4 max-w-[440px]">
      <div className="flex items-center gap-3">
        <span aria-hidden className="size-6 shrink-0 rounded-md bg-surface-2" />
        <p className="m-0 text-[15px] font-semibold">Deploy build 4f2a to production?</p>
      </div>
      <p className="mt-3 mb-4 text-[13px] leading-snug text-muted">Inline confirmation replaces the button row. No dialog, no focus change.</p>
      <div className="relative h-9">
        <div className={`absolute inset-0 flex items-center gap-2 ${fade}`} style={{ opacity: strip ? 0 : 1, transform: strip ? "translateY(-4px)" : "none", pointerEvents: strip ? "none" : "auto" }} aria-hidden={strip}>
          <button ref={deploy} type="button" tabIndex={strip ? -1 : 0} className="mini-btn is-primary !h-9 !px-4 !text-[13px]" style={{ transform: pressed ? "scale(0.96)" : "none", transition: "transform 120ms var(--ease-quart)" }}>Deploy</button>
          <button type="button" tabIndex={strip ? -1 : 0} className="mini-btn !h-9 !px-4 !text-[13px]">Logs</button>
          <button type="button" tabIndex={strip ? -1 : 0} className="mini-btn !h-9 !px-4 !text-[13px]">Snooze</button>
        </div>
        <div className={`absolute inset-0 flex items-center gap-2 ${fade}`} style={{ opacity: strip ? 1 : 0, transform: strip ? "none" : "translateY(4px)", pointerEvents: strip ? "auto" : "none" }} aria-hidden={!strip}>
          <button type="button" tabIndex={strip ? 0 : -1} className="mini-btn is-primary !h-9 !px-4 !text-[13px]">Yes, deploy</button>
          <button type="button" tabIndex={strip ? 0 : -1} className="mini-btn !h-9 !px-4 !text-[13px]">Cancel</button>
        </div>
      </div>
      <span
        aria-hidden
        className="pointer-events-none absolute left-0 top-0 size-3.5 rounded-full border-2 border-ink bg-ink/30"
        style={{ transform: `translate(${cursor.x}px, ${cursor.y}px) scale(${pressed ? 0.7 : 1})`, opacity: cursor.show ? 1 : 0, transition: "transform 850ms var(--ease-quint), opacity 250ms var(--ease-quart)" }}
      />
    </div>
  );
}
