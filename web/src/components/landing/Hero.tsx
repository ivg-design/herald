"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { KeyboardEvent, PointerEvent } from "react";
import { motion, useReducedMotion } from "framer-motion";
import { Download } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { useHeraldInternal } from "@/components/herald/internal";
import { asset } from "@/lib/config";
import type { ReleaseInfo } from "@/lib/release";

type Layout = "imageLeft" | "hero" | "compact";
type Slot = "icon" | "title" | "time" | "body" | "actions";

const LAYOUTS: Layout[] = ["imageLeft", "hero", "compact"];
const ORDER: Slot[] = ["icon", "time", "title", "body", "actions"];
const EASE = [0.16, 1, 0.3, 1] as const;
const APP = { app: "herald.site", appName: "Herald · this page" };
const TITLE = "Notifications you’d actually design.";
const LEDE =
  "Any app declares the data it can send. You design, on a grid of any size, exactly how it shows up: persistent, interactive banners with history, sound and actions. They stay until you deal with them, sit above everything, and never steal focus.";
const LINES = ["Notifications", "you’d actually design."] as const;
const FIRST_SENTENCE = "Any app declares the data it can send.";
const MIN_W = 58;
const GUTTER = 22;

const clamp = (lo: number, hi: number, v: number) => Math.min(hi, Math.max(lo, v));
const clock = () => {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

export default function Hero({ release }: { release: ReleaseInfo }) {
  const h = useHeraldInternal();
  const { ring } = h;
  const reduced = useReducedMotion();

  const [layout, setLayout] = useState<Layout>("imageLeft");
  const [taken, setTaken] = useState<Slot[]>(ORDER);
  const [done, setDone] = useState(false);
  const [sent, setSent] = useState("");
  const [time, setTime] = useState("");
  const [width, setWidth] = useState(100);
  const [dragging, setDragging] = useState(false);
  const [cellW, setCellW] = useState(0);
  const [natural, setNatural] = useState(0);
  const [canvasW, setCanvasW] = useState(0);
  const [cols, setCols] = useState(12);

  const stageRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);
  const titleFieldRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const timers = useRef<number[]>([]);

  const run = () => {
    const stack = h.cards.find((c) => c.app === APP.app);
    const held = h.quiet.hold && h.isQuiet();
    h.send({
      ...APP,
      icon: "herald",
      title: "Notifications you’d actually design.",
      body: FIRST_SENTENCE,
      buttons: [
        { label: "Open", role: "open", primary: true, url: "herald.ivg.design" },
        { label: "Snooze", role: "snooze" },
      ],
    });
    setSent(held ? `Sent · held until ${h.heldUntil}` : stack ? `Sent · stacked with ${APP.appName} (${stack.items.length + 1})` : "Sent");
  };
  const runRef = useRef(run);
  useEffect(() => {
    runRef.current = run;
  });

  const clear = useCallback(() => {
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
  }, []);
  const at = useCallback((ms: number, fn: () => void) => {
    timers.current.push(window.setTimeout(fn, ms));
  }, []);

  /** The load sequence: cells only, fields take their cells, hero to imageLeft, then send once. */
  const play = useCallback(() => {
    clear();
    setSent("");
    if (reduced) {
      setLayout("imageLeft");
      setTaken(ORDER);
      setDone(true);
      return;
    }
    setDone(false);
    setLayout("hero");
    setTaken([]);
    ORDER.forEach((s, i) => at(400 + 90 * i, () => setTaken((t) => (t.includes(s) ? t : [...t, s]))));
    at(1900, () => setLayout("imageLeft"));
    at(2600, () => runRef.current());
    at(2700, () => setDone(true));
  }, [at, clear, reduced]);

  const started = useRef(false);
  useLayoutEffect(() => {
    if (started.current) return;
    started.current = true;
    play();
  }, [play]);
  useEffect(() => clear, [clear]);

  const pick = (l: Layout) => {
    clear();
    setLayout(l);
    setTaken(ORDER);
    setDone(true);
  };

  // Real local clock, after mount, ticking on the minute.
  useEffect(() => {
    let t = 0;
    const tick = () => {
      setTime(clock());
      t = window.setTimeout(tick, 60000 - (Date.now() % 60000) + 50);
    };
    tick();
    return () => window.clearTimeout(t);
  }, []);

  // Measure the cell the headline sits in and the headline's natural width at wdth 100.
  useEffect(() => {
    const field = titleFieldRef.current;
    const span = measureRef.current;
    const canvas = canvasRef.current;
    if (!field || !span || !canvas) return;
    const read = () => {
      setCellW(field.getBoundingClientRect().width);
      setNatural(span.getBoundingClientRect().width);
      setCanvasW(Math.round(canvas.getBoundingClientRect().width));
      const w = window.innerWidth;
      setCols(w < 640 ? 4 : w < 1024 ? 6 : 12);
    };
    const ro = new ResizeObserver(read);
    ro.observe(field);
    ro.observe(span);
    ro.observe(canvas);
    read();
    void document.fonts?.ready.then(read);
    window.addEventListener("resize", read);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", read);
    };
  }, [layout]);

  // The width axis is bound to the cell: the longest line fills it. Below wdth 62 the size steps down instead.
  const fit = useMemo(() => {
    if (!cellW || !natural) return { wdth: 100, scale: 1 };
    const ratio = ((cellW - 6) / natural) * 0.97;
    return { wdth: Math.floor(clamp(62, 125, ratio * 100)), scale: ratio < 0.62 ? Math.max(0.4, ratio / 0.62) : 1 };
  }, [cellW, natural]);

  // Width handle.
  const moveTo = (clientX: number) => {
    const s = stageRef.current;
    if (!s) return;
    const r = s.getBoundingClientRect();
    const avail = Math.max(1, s.clientWidth - GUTTER);
    setWidth(Math.round(clamp(MIN_W, 100, ((clientX - r.left) / avail) * 100)));
  };
  const onDown = (e: PointerEvent<HTMLDivElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    setDragging(true);
    moveTo(e.clientX);
  };
  const onMove = (e: PointerEvent<HTMLDivElement>) => {
    if (dragging) moveTo(e.clientX);
  };
  const onUp = (e: PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    setDragging(false);
  };
  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    const d = e.key === "ArrowRight" || e.key === "ArrowUp" ? 2 : e.key === "ArrowLeft" || e.key === "ArrowDown" ? -2 : 0;
    if (!d) return;
    e.preventDefault();
    setWidth((w) => clamp(MIN_W, 100, w + d));
  };

  const on = (s: Slot) => taken.includes(s);
  const field = (s: Slot) => ({
    layout: dragging ? (false as const) : ("position" as const),
    layoutDependency: layout,
    initial: false as const,
    animate: on(s) ? { opacity: 1, x: 0, transition: { duration: reduced ? 0 : 0.42, ease: EASE } } : { opacity: 0, x: 48, transition: { duration: 0 } },
    transition: { layout: { duration: reduced ? 0 : 0.56, ease: EASE } },
    className: "hero-field",
  });
  const cell = (s: Slot | "image") => ({ className: `cell hero-c-${s}`, "data-filled": s === "image" ? "false" : on(s) ? "true" : "false" });
  const compact = layout === "compact";
  const rows = compact ? (cols === 12 ? 1 : 2) : 3;

  return (
    <section id="top" className="hero" data-layout={layout} data-done={done ? "true" : "false"} data-dragging={dragging ? "true" : "false"}>
      <div className="shell hero-shell">
        <div ref={stageRef} className="hero-stage">
          <div ref={canvasRef} className="hero-canvas" style={{ ["--tpl-w" as string]: width, width: `calc(var(--tpl-w) * 1%)` }}>
            <div className="g hero-grid">
              <div {...cell("icon")}>
                <span className="slot">icon</span>
                <motion.div {...field("icon")}>
                  <span className="hb-logo hero-icon">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={asset("/herald-logo.svg")} alt="Herald" className="hero-icon-img" />
                    {ring > 0 && <span key={ring} aria-hidden className="hb-logo-ping" />}
                  </span>
                </motion.div>
              </div>

              <div {...cell("title")}>
                <span className="slot">title</span>
                <span ref={measureRef} aria-hidden className="display display-xl hero-measure">{compact ? TITLE : LINES[1]}</span>
                <motion.div {...field("title")} ref={titleFieldRef}>
                  <h1
                    className="display display-xl hero-title"
                    style={{ fontVariationSettings: `"wdth" ${fit.wdth}`, ["--fit" as string]: fit.scale }}
                  >
                    {compact ? TITLE : <><span>{LINES[0]}</span> <span>{LINES[1]}</span></>}
                  </h1>
                </motion.div>
              </div>

              <div {...cell("time")}>
                <span className="slot">time</span>
                <motion.div {...field("time")}>
                  <span className="hero-time" suppressHydrationWarning>{time || "--:--"}</span>
                </motion.div>
              </div>

              {!compact && (
                <div {...cell("body")}>
                  <span className="slot">body</span>
                  <motion.div {...field("body")}>
                    <p className="lede hero-lede">{LEDE}</p>
                  </motion.div>
                </div>
              )}

              {layout === "imageLeft" && (
                <div {...cell("image")}>
                  <span className="slot">image</span>
                </div>
              )}

              <div {...cell("actions")}>
                <span className="slot">actions</span>
                <motion.div {...field("actions")}>
                  <div className="hero-actions">
                    <SiteLink href={release.dmgUrl} className="btn btn-primary">
                      <Download size={18} aria-hidden />
                      Download Herald · {release.version}
                    </SiteLink>
                    <SiteLink href="/docs/reference/http-api" className="btn btn-ghost">
                      Read the API docs
                    </SiteLink>
                    <button type="button" className="btn btn-ghost btn-sm" onClick={run}>
                      Send
                    </button>
                    <p className="readout hero-status" role="status" aria-live="polite">{sent}</p>
                  </div>
                </motion.div>
              </div>
            </div>

            <div
              className="hero-handle"
              role="slider"
              tabIndex={0}
              aria-label="Template width"
              aria-orientation="horizontal"
              aria-valuemin={MIN_W}
              aria-valuemax={100}
              aria-valuenow={width}
              aria-valuetext={`${width} percent`}
              onPointerDown={onDown}
              onPointerMove={onMove}
              onPointerUp={onUp}
              onPointerCancel={onUp}
              onKeyDown={onKey}
            >
              <span aria-hidden className="hero-handle-bar" />
            </div>
          </div>
        </div>

        <div className="hero-bar">
          <div className="hero-pick" role="group" aria-label="Template layout">
            {LAYOUTS.map((l) => (
              <button key={l} type="button" className="btn btn-ghost btn-sm hero-pick-btn" aria-pressed={layout === l} onClick={() => pick(l)}>
                {l}
              </button>
            ))}
            <button type="button" className="btn btn-ghost btn-sm" onClick={play}>
              Replay
            </button>
          </div>
          <label className="hero-range">
            <span className="readout">Width</span>
            <input type="range" min={MIN_W} max={100} step={1} value={width} onChange={(e) => setWidth(Number(e.target.value))} />
          </label>
          <p className="readout hero-readout">
            grid · {cols} × {rows} · {canvasW} pt
          </p>
        </div>
      </div>
    </section>
  );
}
