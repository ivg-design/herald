"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent, PointerEvent, ReactNode } from "react";
import { useReducedMotion } from "framer-motion";
import { Download } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { useHeraldInternal } from "@/components/herald/internal";
import { asset } from "@/lib/config";
import type { ReleaseInfo } from "@/lib/release";

type Layout = "imageLeft" | "hero" | "compact";
type Slot = "icon" | "title" | "time" | "body" | "actions";
type CellName = Slot | "image";
interface Rect { x: number; y: number; w: number; h: number }
type Rects = Partial<Record<CellName, Rect>>;

const LAYOUTS: Layout[] = ["hero", "imageLeft", "compact"];
const ORDER: Slot[] = ["icon", "time", "title", "body", "actions"];
const CELLS: CellName[] = ["title", "body", "icon", "time", "image", "actions"];
const APP = { app: "herald.site", appName: "Herald · this page" };
const LEDE =
  "Any app declares the data it can send. You design, on a grid of any size, exactly how it shows up: persistent, interactive banners with history, sound and actions. They stay until you deal with them, sit above everything, and never steal focus.";
const FIRST_SENTENCE = "Any app declares the data it can send.";

/** The headline's three possible settings. The width axis fills the cell; the break follows the cell. */
const L1 = ["Notifications you’d actually design."];
const L2 = ["Notifications", "you’d actually design."];
const L3 = ["Notifications", "you’d actually", "design."];
const STRINGS = [...new Set([...L1, ...L2, ...L3])];
/** Georama's width axis. */
const AXIS = [62.5, 100, 150] as const;
const MIN_W = 58;

const clamp = (lo: number, hi: number, v: number) => Math.min(hi, Math.max(lo, v));
const clock = () => {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};
const sameRects = (a: Rects, b: Rects) =>
  CELLS.every((k) => {
    const p = a[k], q = b[k];
    if (!p || !q) return p === q;
    return Math.abs(p.x - q.x) < 0.5 && Math.abs(p.y - q.y) < 0.5 && Math.abs(p.w - q.w) < 0.5 && Math.abs(p.h - q.h) < 0.5;
  });

/** Width tables: for each string, its advance at the three axis stops, measured at 100 px. */
type Table = Record<string, [number, number, number]>;
const widthAt = (t: [number, number, number], wdth: number) =>
  wdth <= AXIS[1]
    ? t[0] + ((t[1] - t[0]) * (wdth - AXIS[0])) / (AXIS[1] - AXIS[0])
    : t[1] + ((t[2] - t[1]) * (wdth - AXIS[1])) / (AXIS[2] - AXIS[1]);
/** The widest setting (62.5–150) at which every line fits `room` px at `size` px; null when even the narrowest overflows. */
function solve(table: Table, lines: string[], room: number, size: number): number | null {
  const need = (w: number) => Math.max(...lines.map((l) => (table[l] ? widthAt(table[l], w) : 0))) * (size / 100);
  if (need(AXIS[0]) > room) return null;
  if (need(AXIS[2]) <= room) return AXIS[2];
  let lo: number = AXIS[0], hi: number = AXIS[2];
  for (let i = 0; i < 18; i++) {
    const mid = (lo + hi) / 2;
    if (need(mid) <= room) lo = mid;
    else hi = mid;
  }
  return Math.floor(lo * 2) / 2;
}

/** The headline's setting for the cell it is in: the break first, then the width axis fills the line. */
function fitTitle(table: Table | null, room: number, size: number, compact: boolean) {
  if (!table || !room || !size) return null;
  const sets = compact ? [L1, L2, L3] : [L3];
  for (const lines of sets) {
    const w = solve(table, lines, room, size);
    if (w !== null) return { lines, wdth: w, scale: 1 };
  }
  // Narrower than the axis can go: the size steps down as the last resort.
  const need = Math.max(...L3.map((l) => widthAt(table[l], AXIS[0]))) * (size / 100);
  return { lines: L3, wdth: AXIS[0], scale: Math.max(0.4, room / need) };
}

function Glyph({ l }: { l: Layout }) {
  // The three layouts as the Designer's picker draws them: cells on a 12 × 9 field.
  const r = (x: number, y: number, w: number, h: number) => <rect key={`${x}-${y}`} x={x} y={y} width={w} height={h} rx={0.8} />;
  const cells =
    l === "hero"
      ? [r(0, 0, 18, 4.5), r(0, 5.5, 11, 3), r(12, 5.5, 2.5, 3), r(15.5, 5.5, 2.5, 3), r(0, 9.5, 18, 2.5)]
      : l === "imageLeft"
        ? [r(0, 0, 4, 12), r(5, 0, 9, 4.5), r(15, 0, 3, 4.5), r(5, 5.5, 9, 3), r(15, 5.5, 3, 3), r(5, 9.5, 13, 2.5)]
        : [r(0, 3, 18, 3.5), r(0, 7.5, 2, 2.5), r(3, 7.5, 3, 2.5), r(7, 7.5, 11, 2.5)];
  return (
    <svg aria-hidden viewBox="0 0 18 12" width="24" height="16" fill="currentColor">
      {cells}
    </svg>
  );
}

export default function Hero({ release }: { release: ReleaseInfo }) {
  const h = useHeraldInternal();
  const { ring } = h;
  const reduced = useReducedMotion();

  const [layout, setLayout] = useState<Layout>("hero");
  const [taken, setTaken] = useState<Slot[]>(ORDER);
  const [done, setDone] = useState(false);
  const [sent, setSent] = useState("");
  const [time, setTime] = useState("");
  const [width, setWidth] = useState(100);
  const [dragging, setDragging] = useState(false);
  const [gliding, setGliding] = useState(false);
  const [ready, setReady] = useState(false);
  const [rects, setRects] = useState<Rects>({});
  const [gridH, setGridH] = useState(0);
  const [reserve, setReserve] = useState(0);
  const [canvasW, setCanvasW] = useState(0);
  const [cols, setCols] = useState(12);
  const [gap, setGap] = useState(16);
  const [head, setHead] = useState(30);
  const [room, setRoom] = useState(0);
  const [size, setSize] = useState(0);
  const [table, setTable] = useState<Table | null>(null);

  const stageRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostTitleRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const timers = useRef<number[]>([]);
  const raf = useRef(0);
  const touring = useRef(false);
  const widthRef = useRef(100);
  const sizeRef = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    widthRef.current = width;
  }, [width]);

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
  const compactRef = useRef(h.compact);
  useEffect(() => {
    runRef.current = run;
    compactRef.current = h.compact;
  });

  const clear = useCallback(() => {
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
    cancelAnimationFrame(raf.current);
    touring.current = false;
    setGliding(false);
  }, []);
  const at = useCallback((ms: number, fn: () => void) => {
    timers.current.push(window.setTimeout(fn, ms));
  }, []);

  /** The handle moves by itself once: the canvas narrows and comes back, and the headline follows. */
  const glide = useCallback((to: number, ms: number, then?: () => void) => {
    setGliding(true);
    const from = widthRef.current;
    const t0 = performance.now();
    const step = (now: number) => {
      const p = clamp(0, 1, (now - t0) / ms);
      const e = p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2;
      setWidth(Math.round((from + (to - from) * e) * 10) / 10);
      if (p < 1) raf.current = requestAnimationFrame(step);
      else {
        setGliding(false);
        then?.();
      }
    };
    raf.current = requestAnimationFrame(step);
  }, []);

  /**
   * The load sequence. The template is on screen from the first paint; it is sent once, then it shows what a
   * template is: the same fields in the three built-in layouts, then the grid resized. Every move is a transform
   * inside a stage of reserved height, so nothing on the page shifts.
   */
  const tour = useCallback(
    (t0: number) => {
      touring.current = true;
      at(t0, () => setLayout("imageLeft"));
      at(t0 + 1500, () => setLayout("compact"));
      at(t0 + 3000, () => setLayout("hero"));
      at(t0 + 4300, () => {
        if (window.innerWidth >= 1024) glide(70, 1100, () => at(250, () => glide(100, 1000, () => (touring.current = false))));
        else touring.current = false;
      });
    },
    [at, glide],
  );

  const play = useCallback(
    (replay: boolean) => {
      clear();
      setSent("");
      setLayout("hero");
      setWidth(100);
      if (reduced) {
        setTaken(ORDER);
        setDone(true);
        return;
      }
      setDone(false);
      let t = 0;
      if (replay) {
        // Replay starts from the empty grid: cells only, then the fields take their cells.
        setTaken([]);
        ORDER.forEach((s, i) => at(400 + 90 * i, () => setTaken((x) => (x.includes(s) ? x : [...x, s]))));
        t = 500;
      }
      // The template is sent once. On narrow screens the arrival card would cover the headline, so only the bell counts.
      at(t + 1400, () => {
        runRef.current();
        if (window.innerWidth < 1024) compactRef.current();
      });
      at(t + 1500, () => setDone(true));
      tour(t + 2600);
    },
    [at, clear, reduced, tour],
  );

  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    play(false);
  }, [play]);
  useEffect(() => clear, [clear]);

  // The tour is the page's; the first thing the visitor does ends it and the template goes back to rest.
  useEffect(() => {
    const stop = (e: Event) => {
      if (!touring.current) return;
      clear();
      const inHero = e.target instanceof Node && !!stageRef.current?.closest("section")?.contains(e.target);
      if (!(inHero && e.type !== "wheel")) {
        setLayout("hero");
        setWidth(100);
      }
    };
    const opts = { passive: true, capture: true } as const;
    const evs = ["pointerdown", "keydown", "wheel", "touchstart"] as const;
    evs.forEach((ev) => window.addEventListener(ev, stop, opts));
    return () => evs.forEach((ev) => window.removeEventListener(ev, stop, opts));
  }, [clear]);

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

  // The width table: each headline string at the three stops of the axis, at 100 px.
  useEffect(() => {
    const m = measureRef.current;
    if (!m) return;
    const read = () => {
      const t: Table = {};
      m.querySelectorAll<HTMLElement>("[data-s]").forEach((el) => {
        const s = el.dataset.s as string;
        const i = Number(el.dataset.i);
        (t[s] ??= [0, 0, 0])[i] = el.getBoundingClientRect().width;
      });
      setTable(t);
    };
    read();
    void document.fonts?.ready.then(read);
  }, []);

  const compact = layout === "compact";

  const fit = fitTitle(table, room, size, compact);

  // The hidden grid solves the layout; the visible cells copy its boxes and move by transform only.
  const measure = useCallback(() => {
    const c = canvasRef.current;
    const g = ghostRef.current;
    const gt = ghostTitleRef.current;
    if (!c || !g) return;
    const cr = c.getBoundingClientRect();
    const next: Rects = {};
    g.querySelectorAll<HTMLElement>("[data-ghost]").forEach((el) => {
      const r = el.getBoundingClientRect();
      next[el.dataset.ghost as CellName] = { x: r.left - cr.left, y: r.top - cr.top, w: r.width, h: r.height };
    });
    // A cell that leaves the layout keeps its last box, so it can fade where it stood.
    setRects((p) => {
      const merged = { ...p, ...next };
      return sameRects(p, merged) ? p : merged;
    });
    const gh = Math.round(g.getBoundingClientRect().height);
    setGridH(gh);
    // The stage keeps the height of the tallest layout (hero, at full width) so nothing below it ever moves.
    const lineCount = gt?.querySelectorAll(".hero-title > span").length ?? 0;
    if (g.closest("section")?.getAttribute("data-layout") === "hero" && c.style.getPropertyValue("--tpl-w") === "100" && gh > 0 && lineCount === 3) setReserve(gh);
    setCanvasW(Math.round(cr.width));
    setGap(parseFloat(getComputedStyle(g).columnGap) || 16);
    setHead(g.offsetTop);
    const w = window.innerWidth;
    setCols(w < 640 ? 4 : w < 1024 ? 6 : 12);
    if (gt) setRoom(Math.floor(gt.getBoundingClientRect().width) - 2);
    if (sizeRef.current) setSize(parseFloat(getComputedStyle(sizeRef.current).fontSize) || 0);
    setReady(true);
  }, []);
  useLayoutEffect(() => {
    measure();
  });
  useEffect(() => {
    const g = ghostRef.current;
    if (!g) return;
    const ro = new ResizeObserver(measure);
    ro.observe(g);
    window.addEventListener("resize", measure);
    void document.fonts?.ready.then(measure);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, [measure]);

  // Width handle.
  const moveTo = (clientX: number) => {
    const s = stageRef.current;
    if (!s) return;
    const r = s.getBoundingClientRect();
    const avail = Math.max(1, s.clientWidth - (parseFloat(getComputedStyle(s).paddingRight) || 0));
    setWidth(Math.round(clamp(MIN_W, 100, ((clientX - r.left) / avail) * 100)));
  };
  const onDown = (e: PointerEvent<HTMLDivElement>) => {
    clear();
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
    clear();
    setWidth((w) => clamp(MIN_W, 100, Math.round(w) + d));
  };

  const on = (s: Slot) => taken.includes(s);
  const rows = compact ? 2 : 3;
  const live = dragging || gliding;
  const colF = canvasW ? Math.max(0, (canvasW - gap * (cols - 1)) / cols) : 0;
  const stageH = Math.max(reserve, gridH);
  const lift = ready && stageH > gridH ? Math.round((stageH - gridH) / 2) : 0;

  const titleStyle = fit
    ? ({ fontVariationSettings: `"wdth" ${fit.wdth}`, ["--fit" as string]: fit.scale } as CSSProperties)
    : undefined;
  const lines = fit?.lines ?? (compact ? L1 : L3);

  /** One field's content. The ghost copy is inert: same boxes, nothing to focus or read. */
  const content = (s: CellName, ghost: boolean): ReactNode => {
    switch (s) {
      case "icon":
        return (
          <span className="hb-logo hero-icon">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={asset("/herald-icon.png")}
              srcSet={`${asset("/herald-icon.png")} 512w, ${asset("/herald-icon-1024.webp")} 1024w`}
              sizes="(min-width: 1441px) 22vw, 220px"
              alt={ghost ? "" : "Herald app icon"}
              width={512}
              height={512}
              className="hero-icon-img"
            />
            {!ghost && ring > 0 && <span key={ring} aria-hidden className="hb-logo-ping" />}
          </span>
        );
      case "title": {
        const H = ghost === ready ? "div" : "h1";
        return (
          <H className="display display-xl hero-title" style={titleStyle} data-lines={lines.length}>
            {lines.map((l, i) => (
              <span key={l}>
                {l}
                {i < lines.length - 1 ? " " : ""}
              </span>
            ))}
          </H>
        );
      }
      case "time":
        return (
          <span className="hero-time" suppressHydrationWarning>
            {time || "--:--"}
          </span>
        );
      case "body":
        return <p className="lede hero-lede">{LEDE}</p>;
      case "actions":
        return (
          <div className="hero-actions">
            {ghost && ready ? (
              <>
                <span className="btn btn-primary">
                  <Download size={18} aria-hidden />
                  Download Herald · {release.version}
                </span>
                <span className="btn btn-ghost">Read the API docs</span>
                <span className="btn btn-ghost">Send</span>
                <span className="readout hero-status">{sent}</span>
              </>
            ) : (
              <>
                <SiteLink href={release.dmgUrl} className="btn btn-primary">
                  <Download size={18} aria-hidden />
                  Download Herald · {release.version}
                </SiteLink>
                <SiteLink href="/docs/reference/http-api" className="btn btn-ghost">
                  Read the API docs
                </SiteLink>
                <button type="button" className="btn btn-ghost" onClick={run}>
                  Send
                </button>
                <p className="readout hero-status" role="status" aria-live="polite">
                  {sent}
                </p>
              </>
            )}
          </div>
        );
      default:
        return null;
    }
  };

  const inLayout = (s: CellName) => (s === "body" ? !compact : s === "image" ? layout === "imageLeft" : true);

  return (
    <section
      id="top"
      className="hero blueprint"
      data-layout={layout}
      data-done={done ? "true" : "false"}
      data-dragging={live ? "true" : "false"}
      data-ready={ready ? "true" : "false"}
    >
      <div className="shell hero-shell">
        <div className="hero-bar">
          <div className="hero-pick" role="group" aria-label="Template layout">
            {LAYOUTS.map((l) => (
              <button key={l} type="button" className="hero-pick-btn" aria-pressed={layout === l} onClick={() => pick(l)}>
                <Glyph l={l} />
                {l}
              </button>
            ))}
            <button type="button" className="hero-pick-btn hero-replay" onClick={() => play(true)}>
              Replay
            </button>
          </div>
          <label className="hero-range">
            <span className="readout">Width</span>
            <input
              type="range"
              min={MIN_W}
              max={100}
              step={1}
              value={Math.round(width)}
              onChange={(e) => {
                clear();
                setWidth(Number(e.target.value));
              }}
            />
          </label>
          <p className="readout hero-readout">
            <span className="hero-readout-k">grid · </span>
            {cols} × {rows} · {String(canvasW).padStart(4, "\u2007")} pt
          </p>
        </div>

        <div ref={stageRef} className="hero-stage">
          <div
            ref={canvasRef}
            className="hero-canvas"
            style={{ ["--tpl-w" as string]: width, width: `calc(var(--tpl-w) * 1%)`, minHeight: reserve ? reserve + head : undefined }}
          >
            {/* column tracks, as the Designer's ruler draws them */}
            <div className="hero-ruler" aria-hidden data-cols={cols}>
              {Array.from({ length: cols }, (_, i) => (
                <span key={i} style={colF ? { width: colF, transform: `translate3d(${i * (colF + gap)}px, 0, 0)` } : undefined}>
                  {colF ? Math.round(colF) : ""}
                </span>
              ))}
            </div>

            {/* the solver: a real CSS grid. It is what the server renders; once measured it is hidden and the cells below copy it. */}
            <div ref={ghostRef} className="g hero-grid hero-ghost" aria-hidden={ready ? true : undefined} inert={ready ? true : undefined}>
              {CELLS.filter(inLayout).map((s) => (
                <div key={s} className={`cell hero-c-${s}`} data-ghost={s}>
                  <span className="slot">{s}</span>
                  <div className="hero-field" ref={s === "title" ? ghostTitleRef : undefined}>
                    {content(s, true)}
                  </div>
                </div>
              ))}
            </div>

            {ready && (
              <div className="hero-live" style={{ transform: `translate3d(0, ${lift}px, 0)` }}>
                {CELLS.map((s) => {
                  const r = rects[s];
                  const here = inLayout(s) && !!r;
                  if (!r) return null;
                  return (
                    <div
                      key={s}
                      className={`cell hero-cell hero-c-${s}`}
                      data-slot={s}
                      data-here={here ? "true" : "false"}
                      aria-hidden={here ? undefined : true}
                      inert={here ? undefined : true}
                      style={{ transform: `translate3d(${r.x}px, ${r.y}px, 0)`, width: r.w, height: r.h }}
                    >
                      <span className="slot">{s}</span>
                      {s !== "image" && (
                        <div className="hero-field" data-on={on(s as Slot) ? "true" : "false"}>
                          {content(s, false)}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}

            <div
              className="hero-handle"
              role="slider"
              tabIndex={0}
              aria-label="Template width"
              aria-orientation="horizontal"
              aria-valuemin={MIN_W}
              aria-valuemax={100}
              aria-valuenow={Math.round(width)}
              aria-valuetext={`${Math.round(width)} percent`}
              style={{ transform: `translate3d(${canvasW}px, 0, 0)` }}
              onPointerDown={onDown}
              onPointerMove={onMove}
              onPointerUp={onUp}
              onPointerCancel={onUp}
              onKeyDown={onKey}
            >
              <span aria-hidden className="hero-handle-bar" />
              <span aria-hidden className="hero-handle-grip" />
              <span aria-hidden className="hero-handle-tag">{String(canvasW).padStart(4, "\u2007")} pt</span>
            </div>
          </div>
        </div>

        {/* headline strings at the three stops of the width axis, for the fit */}
        <div ref={measureRef} className="hero-measure" aria-hidden>
          <span ref={sizeRef} className="hero-size" />
          {STRINGS.map((s) =>
            AXIS.map((a, i) => (
              <span key={`${s}-${a}`} data-s={s} data-i={i} className="display display-xl" style={{ fontVariationSettings: `"wdth" ${a}` }}>
                {s}
              </span>
            )),
          )}
        </div>
      </div>
    </section>
  );
}
