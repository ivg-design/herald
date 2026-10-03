"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, useReducedMotion } from "framer-motion";
import { EASE } from "@/lib/config";

const HOLD_MS = 2200;
const DUR = 0.4;

/** LERP-style swapper. Words are stacked in one inline-grid cell, so the width is the widest word. */
export default function WordSwapper({
  words,
  staticWord,
  onIndex,
  className,
}: {
  words: string[];
  staticWord: string;
  onIndex?: (i: number) => void;
  className?: string;
}) {
  const reduce = useReducedMotion();
  const [i, setI] = useState(0);
  const [hover, setHover] = useState(false);
  const [visible, setVisible] = useState(true);
  const [onScreen, setOnScreen] = useState(true);
  const ref = useRef<HTMLSpanElement>(null);
  const cb = useRef(onIndex);
  useEffect(() => {
    cb.current = onIndex;
  });

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(([e]) => setOnScreen(e.isIntersecting));
    io.observe(el);
    return () => io.disconnect();
  }, []);

  useEffect(() => {
    const on = () => setVisible(document.visibilityState === "visible");
    on();
    document.addEventListener("visibilitychange", on);
    return () => document.removeEventListener("visibilitychange", on);
  }, []);

  const running = !reduce && !hover && visible && onScreen && words.length > 1;
  const advance = useCallback(() => setI((p) => (p + 1) % words.length), [words.length]);

  useEffect(() => {
    if (!running) return;
    const t = setTimeout(advance, HOLD_MS);
    return () => clearTimeout(t);
  }, [running, i, advance]);

  useEffect(() => {
    cb.current?.(i);
  }, [i]);

  if (reduce) {
    return <span className={className}>{staticWord}.</span>;
  }

  return (
    <span
      ref={ref}
      className={className}
      style={{ display: "inline-grid", overflow: "hidden", verticalAlign: "bottom", padding: "0.12em 0 0.22em", margin: "-0.12em 0 -0.22em" }}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onFocus={() => setHover(true)}
      onBlur={() => setHover(false)}
    >
      {words.map((w, k) => {
        const active = k === i;
        const prev = k === (i - 1 + words.length) % words.length;
        return (
          <motion.span
            key={w}
            aria-hidden="true"
            style={{ gridArea: "1 / 1", whiteSpace: "nowrap", willChange: "transform, opacity" }}
            initial={false}
            animate={{ y: active ? "0%" : prev ? "-60%" : "60%", opacity: active ? 1 : 0 }}
            transition={prev && !active ? { duration: DUR, ease: EASE.quint } : active ? { duration: DUR, ease: EASE.quint } : { duration: 0 }}
          >
            {w}.
          </motion.span>
        );
      })}
    </span>
  );
}
