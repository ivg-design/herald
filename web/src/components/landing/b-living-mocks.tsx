"use client";
import { useEffect, useRef, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import { EASE } from "@/lib/config";
import { useInViewOnce } from "./b-hooks";
import { WAVE } from "./b-wave";

const PANEL = "rounded-xl border border-paper-line bg-white p-4 min-h-[168px] text-paper-ink";
const SMALL = "text-[12px] text-paper-muted";

export function StackMock() {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInViewOnce(ref, 0.5);
  const [count, setCount] = useState(7);
  const collapsed = reduced ? true : seen;

  useEffect(() => {
    if (reduced || !seen) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCount(1);
    let n = 1;
    const id = setInterval(() => {
      n += 1;
      setCount(n);
      if (n >= 7) clearInterval(id);
    }, 170);
    return () => clearInterval(id);
  }, [reduced, seen]);

  const card = "absolute inset-x-0 flex h-[40px] items-center gap-3 rounded-lg border border-paper-line bg-white px-3 text-[13px]";
  const tile = <span aria-hidden className="size-4 shrink-0 rounded bg-[#e3e6ea]" />;
  const t = { duration: 0.6, ease: EASE.quint };
  return (
    <div ref={ref} className={PANEL}>
      <div className="relative h-[130px]" aria-hidden>
        <motion.div className={card} style={{ top: 0 }} initial={false} animate={{ y: collapsed ? 76 : 0, scale: collapsed ? 0.92 : 1, opacity: collapsed ? 0.5 : 0.75 }} transition={t}>{tile}<span className="text-paper-muted">Gmail · @rive.app</span></motion.div>
        <motion.div className={card} style={{ top: 44 }} initial={false} animate={{ y: collapsed ? 36 : 0, scale: collapsed ? 0.96 : 1, opacity: collapsed ? 0.7 : 0.85 }} transition={t}>{tile}<span className="text-paper-muted">Gmail · @rive.app</span></motion.div>
        <div className={`${card} border-[#c9d1d9]`} style={{ top: 88 }}>
          {tile}
          <span className="font-medium">Gmail · @rive.app</span>
          <span className="ml-auto flex h-5 min-w-5 items-center justify-center rounded-full bg-signal px-1.5 text-[11px] font-bold text-white mono">{count}</span>
        </div>
      </div>
      <p className={`m-0 mt-3 ${SMALL}`}>
        <span className="sr-only">Stack counter shows 7 banners from the same issuer. </span>
        Group by:{" "}
        <label className="mr-2"><span aria-hidden className="mr-1 text-[#1b6fb8]">○</span>app</label>
        <label className="mr-2"><span aria-hidden className="mr-1 text-[#1b6fb8]">◉</span>issuer</label>
        <label className="mr-2"><span aria-hidden className="mr-1 text-[#1b6fb8]">○</span>sender</label>
        · click to expand
      </p>
    </div>
  );
}

export function QuietMock() {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInViewOnce(ref, 0.5);
  const on = reduced ? true : seen;
  return (
    <div ref={ref} className={PANEL}>
      <div className="relative h-4 overflow-hidden rounded-full bg-[#e3e6ea]" role="img" aria-label="Day bar from 18:00 to 12:00 with quiet hours from 22:00 to 07:00 highlighted">
        <motion.div
          className="absolute inset-y-0 rounded-full bg-accent"
          style={{ left: "22.22%", width: "50%", transformOrigin: "left center" }}
          initial={false}
          animate={{ scaleX: on ? 1 : 0 }}
          transition={{ duration: 1, ease: EASE.quint }}
        />
      </div>
      <div className={`mt-3 flex items-center gap-2 ${SMALL}`}>
        <span className="mono">22:00</span>
        <span aria-hidden className="h-px flex-1 bg-paper-muted/50" />
        <span className="mono">07:00</span>
        <span className="hidden sm:inline">voice muted, banners silent</span>
      </div>
      <p className={`m-0 mt-1 sm:hidden ${SMALL}`}>voice muted, banners silent</p>
      <p className={`m-0 mt-3 ${SMALL}`}>
        Per app:{" "}
        <label className="mr-2 inline-block"><span aria-hidden className="mr-1 text-[#1b6fb8]">☑</span>mute sound</label>
        <label className="mr-2 inline-block"><span aria-hidden className="mr-1 text-[#1b6fb8]">☑</span>no voice</label>
        <label className="inline-block"><span aria-hidden className="mr-1 text-[#1b6fb8]">☐</span>hold banners until morning</label>
      </p>
    </div>
  );
}

export function VoiceMock() {
  const reduced = useReducedMotion();
  const [playing, setPlaying] = useState(false);
  const last = WAVE.length - 1;
  return (
    <div className={PANEL}>
      <button
        type="button"
        aria-label="Play the waveform animation"
        onClick={() => !reduced && !playing && setPlaying(true)}
        className="flex h-12 w-full items-end gap-[3px] rounded-md p-1 text-left on-paper cursor-pointer"
      >
        {WAVE.map((h, i) => (
          <motion.span
            key={i}
            aria-hidden
            className="w-[5px] rounded-full bg-accent"
            style={{ height: `${Math.round(h * 100)}%`, transformOrigin: "bottom" }}
            animate={playing ? { scaleY: [1, 1.5, 0.5, 1.25, 1] } : { scaleY: 1 }}
            transition={playing ? { duration: 0.7, delay: i * 0.05, ease: EASE.quart } : { duration: 0 }}
            onAnimationComplete={() => { if (playing && i === last) setPlaying(false); }}
          />
        ))}
      </button>
      <p className="m-0 mt-3 text-[13px] font-medium">“Build passed. One hundred forty-two tests.”</p>
      <p className={`m-0 mt-2 ${SMALL}`}>Kokoro, local, optional download · falls back to the system voice · text always lands in history</p>
    </div>
  );
}
