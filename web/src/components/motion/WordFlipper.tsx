"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import { useReducedMotion } from "framer-motion";

export interface FlipPhrase {
  text: string;
  fontFamily: string;
  fontSize: string;
  fontWeight?: number;
  fontStyle?: string;
  letterSpacing?: string;
  fontVariationSettings?: string;
  /** Google Fonts css2 family spec, e.g. "Caveat:wght@700". Omit when the face is already loaded. */
  googleFamily?: string;
}

const INTERVAL = 2800;
const ANIM = 800; // 0.5 s flip + up to 0.3 s stagger
const LINK_ID = "herald-flip-fonts";

function phraseStyle(p: FlipPhrase): CSSProperties {
  return {
    fontFamily: p.fontFamily,
    fontSize: p.fontSize,
    fontWeight: p.fontWeight ?? 400,
    fontStyle: p.fontStyle ?? "normal",
    letterSpacing: p.letterSpacing ?? "0",
    fontVariationSettings: p.fontVariationSettings,
  };
}

function Chars({ phrase, mode }: { phrase: FlipPhrase; mode: "static" | "in" | "out" }) {
  const chars = phrase.text.split("");
  return (
    <span className={`flip-word flip-word-${mode}`} style={phraseStyle(phrase)} aria-hidden>
      {chars.map((ch, i) => (
        <span
          key={i}
          className="flip-char"
          style={{ "--flip-stagger": `${Math.round((i / Math.max(chars.length - 1, 1)) * 300) / 1000}s` } as CSSProperties}
        >
          {ch}
        </span>
      ))}
    </span>
  );
}

export default function WordFlipper({ phrases, className }: { phrases: FlipPhrase[]; className?: string }) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLSpanElement>(null);
  const [near, setNear] = useState(false);
  const [fontsReady, setFontsReady] = useState(false);
  const [current, setCurrent] = useState(0);
  const [flipping, setFlipping] = useState(false);
  const paused = useRef(false);
  const next = (current + 1) % phrases.length;

  // Lazy-load the display faces once the drum is within 500px of the viewport.
  useEffect(() => {
    const el = ref.current;
    if (!el || reduce) return;
    const io = new IntersectionObserver(([e]) => setNear(e.isIntersecting), { rootMargin: "500px" });
    io.observe(el);
    return () => io.disconnect();
  }, [reduce]);

  useEffect(() => {
    if (!near || reduce) return;
    const families = phrases.map((p) => p.googleFamily).filter(Boolean) as string[];
    if (!families.length || document.getElementById(LINK_ID)) {
      const t0 = setTimeout(() => setFontsReady(true), 0);
      return () => clearTimeout(t0);
    }
    const link = document.createElement("link");
    link.id = LINK_ID;
    link.rel = "stylesheet";
    link.href = `https://fonts.googleapis.com/css2?${families.map((f) => `family=${f}`).join("&")}&display=swap`;
    const done = () => setFontsReady(true);
    link.addEventListener("load", done);
    link.addEventListener("error", done);
    document.head.appendChild(link);
    const t = setTimeout(done, 2500);
    return () => clearTimeout(t);
  }, [near, reduce, phrases]);

  // Pause while hovered, while focus is inside the section, and while the tab is hidden.
  useEffect(() => {
    const el = ref.current;
    if (!el || reduce) return;
    const scope = el.closest("section") ?? el;
    let hover = false;
    let focus = false;
    const sync = () => { paused.current = hover || focus || document.hidden; };
    const on = (t: EventTarget, ev: string, fn: () => void) => { t.addEventListener(ev, fn); return () => t.removeEventListener(ev, fn); };
    const offs = [
      on(el, "mouseenter", () => { hover = true; sync(); }),
      on(el, "mouseleave", () => { hover = false; sync(); }),
      on(scope, "focusin", () => { focus = true; sync(); }),
      on(scope, "focusout", () => { focus = false; sync(); }),
      on(document, "visibilitychange", sync),
    ];
    return () => offs.forEach((f) => f());
  }, [reduce]);

  useEffect(() => {
    if (!near || !fontsReady || reduce || phrases.length < 2) return;
    let t1: ReturnType<typeof setTimeout>;
    let t2: ReturnType<typeof setTimeout>;
    const tick = () => {
      if (paused.current) { t1 = setTimeout(tick, 300); return; }
      setFlipping(true);
      t2 = setTimeout(() => {
        setCurrent((c) => (c + 1) % phrases.length);
        setFlipping(false);
        t1 = setTimeout(tick, INTERVAL - ANIM);
      }, ANIM);
    };
    t1 = setTimeout(tick, INTERVAL);
    return () => { clearTimeout(t1); clearTimeout(t2); };
  }, [near, fontsReady, reduce, phrases.length]);

  const shown = reduce ? 0 : current;
  return (
    <span ref={ref} className={`flip-drum ${className ?? ""}`} aria-live="polite">
      <span className="sr-only">{phrases[shown].text}</span>
      <Chars key={`w-${shown}`} phrase={phrases[shown]} mode={flipping ? "out" : "static"} />
      {flipping && <Chars key={`w-${next}`} phrase={phrases[next]} mode="in" />}
    </span>
  );
}
