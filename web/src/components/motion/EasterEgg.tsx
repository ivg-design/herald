"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { EASE, asset } from "@/lib/config";

const SNOOZE_MS = 10_000;

export default function EasterEgg() {
  const reduce = useReducedMotion();
  const [open, setOpen] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || !e.shiftKey || e.key.toLowerCase() !== "h") return;
      const el = e.target as HTMLElement | null;
      if (el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return;
      e.preventDefault();
      setOpen(true);
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      if (timer.current) clearTimeout(timer.current);
    };
  }, []);

  const snooze = () => {
    setOpen(false);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setOpen(true), SNOOZE_MS);
  };
  const dismiss = () => {
    if (timer.current) clearTimeout(timer.current);
    setOpen(false);
  };

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          key="egg"
          role="status"
          aria-live="polite"
          initial={reduce ? false : { opacity: 0, x: 24 }}
          animate={{ opacity: 1, x: 0, transition: reduce ? { duration: 0 } : { duration: 0.52, ease: EASE.expo } }}
          exit={{ opacity: 0, x: reduce ? 0 : 24, transition: reduce ? { duration: 0 } : { duration: 0.39, ease: EASE.expo } }}
          className="fixed"
          style={{
            top: 16,
            right: 16,
            zIndex: 1000,
            width: 360,
            maxWidth: "calc(100vw - 32px)",
            background: "var(--surface)",
            border: "1px solid var(--line)",
            borderRadius: 12,
            padding: 14,
            color: "var(--ink)",
          }}
        >
          <div className="flex gap-3">
            <Image src={asset("/herald-icon.png")} alt="" width={40} height={40} unoptimized style={{ width: 40, height: 40, borderRadius: 9 }} className="shrink-0" />
            <div className="min-w-0">
              <div className="font-mono text-[10px] uppercase tracking-wider text-muted">Herald</div>
              <div className="text-[15px] font-medium">You found it.</div>
              <p className="mt-1 text-[13px] leading-snug text-muted">Banners that stay until you decide. This one will wait 10 seconds if you snooze it.</p>
            </div>
          </div>
          <div className="mt-3 flex gap-2 pl-[52px]">
            <button type="button" className="mini-btn" onClick={snooze} style={{ height: 40, padding: "0 16px", fontSize: 13 }}>Snooze</button>
            <button type="button" className="mini-btn" onClick={dismiss} style={{ height: 40, padding: "0 16px", fontSize: 13 }}>Dismiss</button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
