"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { CSSProperties, KeyboardEvent, PointerEvent, ReactNode } from "react";
import { useReducedMotion } from "framer-motion";
import { Download, GripVertical } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { useHeraldInternal } from "@/components/herald/internal";
import { asset } from "@/lib/config";
import type { ReleaseInfo } from "@/lib/release";

/*
  The hero is a miniature of Herald's Designer, and the template it edits is the hero itself.
  A real CSS grid (.hero-ghost) solves the layout; the visible cells copy its boxes and move by transform only.
  Presets (hero / imageLeft / compact) are CSS; the first edit turns the grid into explicit tracks and placements
  (`custom`), read back from the solved grid, so rows stop being content-sized and the canvas keeps its height.
  What the visitor can do, each as the Designer does it:
    - drag a column or row divider on the rulers: the track takes a size, its neighbour gives way (24 pt minimum);
    - drag a field by its grip onto another cell: the two swap (GridEditing.move), the headline re-fits;
    - drag the right edge: the whole grid is resized;
    - pick a preset, Reset, Replay, Send.
*/

type Layout = "imageLeft" | "hero" | "compact";
type Slot = "icon" | "title" | "time" | "body" | "actions";
type CellName = Slot | "image";
interface Rect { x: number; y: number; w: number; h: number }
type Rects = Partial<Record<CellName, Rect>>;
interface Place { c0: number; c1: number; r0: number; r1: number }
interface Custom { cols: number[]; rows: number[]; place: Partial<Record<CellName, Place>> }

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
/** The Designer's floor for a track that gives way (GridEditing.minFlexibleColumn). */
const MIN_TRACK = 24;
/** Rows keep room for a cell's label and one line of content at page scale. */
const MIN_ROW = 64;
/** Room under the last line for descenders, in em (the title's padding-bottom in hero.css). */
const DESC = 0.16;

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
const sameList = (a: number[], b: number[]) => a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) < 0.5);
const pad4 = (n: number) => String(n).padStart(4, " ");

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
/** Condensed lines are set a little further apart so descenders never meet the next line's ascenders. */
const leading = (wdth: number) => 0.92 + 0.1 * clamp(0, 1, (112 - wdth) / 32);

interface Fit { lines: string[]; wdth: number; size: number; lh: number }
/**
 * The headline's setting for the cell it is in. `size` is the largest it may be; `roomH` (when the cell has a fixed
 * height) limits it further. Each candidate break gets the size that fits the height, then the width axis fills the
 * line; the candidate that ends up largest wins, the preferred break on a tie.
 */
function fitTitle(table: Table | null, room: number, roomH: number | null, base: number, prefer: string[][]): Fit | null {
  if (!table || !room || !base) return null;
  let best: Fit | null = null;
  for (const lines of prefer) {
    let size = base;
    let lh = 0.92;
    let wdth: number = AXIS[0];
    for (let pass = 0; pass < 3; pass++) {
      if (roomH !== null) size = Math.min(base, roomH / (lines.length * lh + DESC));
      const w = solve(table, lines, room, size);
      if (w === null) {
        // Narrower than the axis can go: the size steps down as the last resort.
        const need = Math.max(...lines.map((l) => widthAt(table[l], AXIS[0])));
        size = Math.min(size, (room / need) * 100);
        wdth = AXIS[0];
      } else wdth = w;
      lh = leading(wdth);
    }
    if (roomH !== null) size = Math.min(size, roomH / (lines.length * lh + DESC));
    size = Math.max(12, Math.floor(size * 10) / 10);
    if (!best || size > best.size * 1.02) best = { lines, wdth, size, lh };
  }
  return best;
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

const px = (s: string) => s.split(" ").map((v) => parseFloat(v)).filter((n) => Number.isFinite(n));

export default function Hero({ release }: { release: ReleaseInfo }) {
  const h = useHeraldInternal();
  const { ring } = h;
  const reduced = useReducedMotion();

  const [layout, setLayout] = useState<Layout>("hero");
  const [custom, setCustom] = useState<Custom | null>(null);
  const [taken, setTaken] = useState<Slot[]>(ORDER);
  const [done, setDone] = useState(false);
  const [sent, setSent] = useState("");
  const [time, setTime] = useState("");
  const [width, setWidth] = useState(100);
  const [live, setLive] = useState(false);
  const [ready, setReady] = useState(false);
  const [rects, setRects] = useState<Rects>({});
  const [gridH, setGridH] = useState(0);
  const [reserve, setReserve] = useState(0);
  const [canvasW, setCanvasW] = useState(0);
  const [nCols, setNCols] = useState(12);
  const [colPx, setColPx] = useState<number[]>([]);
  const [rowPx, setRowPx] = useState<number[]>([]);
  const [gap, setGap] = useState(16);
  const [head, setHead] = useState(30);
  const [room, setRoom] = useState(0);
  const [roomH, setRoomH] = useState(0);
  const [base, setBase] = useState(0);
  const [table, setTable] = useState<Table | null>(null);
  const [picked, setPicked] = useState<Slot | null>(null);
  const [drag, setDrag] = useState<{ slot: Slot; dx: number; dy: number; over: CellName | null } | null>(null);
  const [track, setTrack] = useState<{ axis: "col" | "row"; i: number } | null>(null);

  const sectionRef = useRef<HTMLElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLDivElement>(null);
  const ghostRef = useRef<HTMLDivElement>(null);
  const ghostTitleRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const sizeRef = useRef<HTMLSpanElement>(null);
  const timers = useRef<number[]>([]);
  const raf = useRef(0);
  const touring = useRef(false);
  const customRef = useRef<Custom | null>(null);
  const rectsRef = useRef<Rects>({});
  const grab = useRef<{ x: number; y: number; a: number; b: number } | null>(null);
  const moved = useRef(false);
  const reserveKey = useRef("");
  useEffect(() => {
    customRef.current = custom;
    rectsRef.current = rects;
  });

  /** One line saying where each field sits, for the banner that Send puts under the bell. */
  const arrangement = () => {
    const c = customRef.current;
    if (!c) return `${layout} preset, ${canvasW} pt wide.`;
    const span = (a: number, b: number) => (b - a === 1 ? `${a}` : `${a}–${b - 1}`);
    const parts = ORDER.filter((s) => c.place[s]).map((s) => `${s} r${span(c.place[s]!.r0, c.place[s]!.r1)} c${span(c.place[s]!.c0, c.place[s]!.c1)}`);
    return `Your layout: ${parts.join(", ")}. Columns ${c.cols.map((v) => Math.round(v)).join(" ")} pt.`;
  };
  const run = () => {
    const stack = h.cards.find((c) => c.app === APP.app);
    const held = h.quiet.hold && h.isQuiet();
    h.send({
      ...APP,
      icon: "herald",
      title: "Notifications you’d actually design.",
      body: customRef.current ? arrangement() : FIRST_SENTENCE,
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
    setLive(false);
  }, []);
  const at = useCallback((ms: number, fn: () => void) => {
    timers.current.push(window.setTimeout(fn, ms));
  }, []);

  /** The grid as it is solved right now, as explicit tracks and placements. Presets are CSS until the first edit. */
  const freeze = useCallback((): Custom | null => {
    if (customRef.current) return customRef.current;
    const g = ghostRef.current;
    if (!g) return null;
    const cs = getComputedStyle(g);
    const place: Custom["place"] = {};
    g.querySelectorAll<HTMLElement>("[data-ghost]").forEach((el) => {
      const s = getComputedStyle(el);
      const c0 = parseInt(s.gridColumnStart, 10), r0 = parseInt(s.gridRowStart, 10);
      const ce = s.gridColumnEnd, re = s.gridRowEnd;
      const c1 = ce.startsWith("span") ? c0 + parseInt(ce.slice(4), 10) : parseInt(ce, 10) || c0 + 1;
      const r1 = re.startsWith("span") ? r0 + parseInt(re.slice(4), 10) : parseInt(re, 10) || r0 + 1;
      place[el.dataset.ghost as CellName] = { c0, c1, r0, r1 };
    });
    const c: Custom = { cols: px(cs.gridTemplateColumns), rows: px(cs.gridTemplateRows), place };
    customRef.current = c;
    return c;
  }, []);
  const edit = useCallback(
    (fn: (c: Custom) => Custom) => {
      const c = freeze();
      if (!c) return;
      const next = fn(c);
      customRef.current = next;
      setCustom(next);
    },
    [freeze],
  );

  /** A value animated by hand (the tour's own track resize): frames go through state, cells follow without easing. */
  const animate = useCallback((ms: number, frame: (p: number) => void, then?: () => void) => {
    setLive(true);
    const t0 = performance.now();
    const step = (now: number) => {
      const p = clamp(0, 1, (now - t0) / ms);
      frame(p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
      if (p < 1) raf.current = requestAnimationFrame(step);
      else {
        setLive(false);
        then?.();
      }
    };
    raf.current = requestAnimationFrame(step);
  }, []);

  const swap = useCallback(
    (a: CellName, b: CellName) => {
      if (a === b) return;
      edit((c) => {
        if (!c.place[a] || !c.place[b]) return c;
        return { ...c, place: { ...c.place, [a]: c.place[b], [b]: c.place[a] } };
      });
    },
    [edit],
  );
  /** Track `i` takes `d` more points; the next one gives way. Both keep the Designer's 24 pt floor. */
  const resize = useCallback(
    (axis: "col" | "row", i: number, a0: number, b0: number, d: number) => {
      edit((c) => {
        const list = axis === "col" ? [...c.cols] : [...c.rows];
        if (i + 1 >= list.length) return c;
        const min = axis === "col" ? MIN_TRACK : MIN_ROW;
        const dd = clamp(Math.min(0, min - a0), Math.max(0, b0 - min), d);
        list[i] = a0 + dd;
        list[i + 1] = b0 - dd;
        return axis === "col" ? { ...c, cols: list } : { ...c, rows: list };
      });
    },
    [edit],
  );

  /**
   * The load sequence. The template is on screen from the first paint; it is sent once, then it shows what a
   * template is: the same fields in the three built-in layouts, then two edits (a field moved, a column resized)
   * and back. Every move is a transform inside a canvas of reserved height, so nothing on the page shifts.
   */
  const tour = useCallback(
    (t0: number) => {
      touring.current = true;
      at(t0, () => setLayout("imageLeft"));
      at(t0 + 1500, () => setLayout("compact"));
      at(t0 + 3000, () => setLayout("hero"));
      at(t0 + 4300, () => swap("icon", "time"));
      at(t0 + 5300, () => {
        const c = freeze();
        const i = c ? Math.floor(c.cols.length * 0.66) - 1 : -1;
        if (!c || i < 0 || i + 1 >= c.cols.length) return;
        const a0 = c.cols[i], b0 = c.cols[i + 1];
        const d = Math.min(a0 - MIN_TRACK, b0 * 0.9);
        animate(800, (p) => resize("col", i, a0, b0, -d * p));
      });
      at(t0 + 7000, () => {
        customRef.current = null;
        setCustom(null);
        touring.current = false;
      });
    },
    [animate, at, freeze, resize, swap],
  );

  const reset = useCallback(() => {
    customRef.current = null;
    setCustom(null);
    setWidth(100);
    setPicked(null);
    setTrack(null);
  }, []);

  const play = useCallback(
    (replay: boolean) => {
      clear();
      setSent("");
      setLayout("hero");
      reset();
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
    [at, clear, reduced, reset, tour],
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
      const inHero = e.target instanceof Node && !!sectionRef.current?.contains(e.target);
      if (!(inHero && e.type !== "wheel")) setLayout("hero");
      customRef.current = null;
      setCustom(null);
    };
    const opts = { passive: true, capture: true } as const;
    const evs = ["pointerdown", "keydown", "wheel", "touchstart"] as const;
    evs.forEach((ev) => window.addEventListener(ev, stop, opts));
    return () => evs.forEach((ev) => window.removeEventListener(ev, stop, opts));
  }, [clear]);

  const pick = (l: Layout) => {
    clear();
    reset();
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
  // In a preset the headline keeps the height of three lines at the open leading: where it has to condense (and the
  // leading opens so lines do not touch) it gives up a little size instead of growing out of its cell.
  const fit = fitTitle(table, room, custom ? roomH : compact ? null : (3 * 0.92 + DESC) * base, base, custom ? [L3, L2, L1] : compact ? [L1, L2, L3] : [L3]);

  // The hidden grid solves the layout; the visible cells copy its boxes and move by transform only.
  const measure = useCallback(() => {
    const c = canvasRef.current;
    const g = ghostRef.current;
    const gt = ghostTitleRef.current;
    const sec = sectionRef.current;
    if (!c || !g || !sec) return;
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
    const gcs = getComputedStyle(g);
    const cols = px(gcs.gridTemplateColumns), rows = px(gcs.gridTemplateRows);
    setColPx((p) => (sameList(p, cols) ? p : cols));
    setRowPx((p) => (sameList(p, rows) ? p : rows));
    setNCols(cols.length || 12);
    setGap(parseFloat(gcs.columnGap) || 16);
    setHead(g.offsetTop);
    const gh = Math.round(g.getBoundingClientRect().height);
    setGridH(gh);
    setCanvasW(Math.round(cr.width));
    if (gt) {
      const cell = gt.parentElement as HTMLElement;
      const s = getComputedStyle(cell);
      setRoom(Math.floor(gt.getBoundingClientRect().width) - 2);
      setRoomH(Math.max(0, cell.clientHeight - parseFloat(s.paddingTop) - parseFloat(s.paddingBottom)));
    }
    if (sizeRef.current) setBase(parseFloat(getComputedStyle(sizeRef.current).fontSize) || 0);
    // The canvas keeps the height of the tallest preset at full width, so no layout change moves the page.
    // The other presets are tried on the solver in this same pass, before anything is painted.
    const key = `${gh}:${Math.round(cr.width)}`;
    if (!customRef.current && key !== reserveKey.current && c.style.getPropertyValue("--tpl-w") === "100" && gh > 0 && sec.dataset.layout === "hero" && (gt?.querySelectorAll(".hero-title > span").length ?? 0) === 3) {
      reserveKey.current = key;
      let tallest = gh;
      for (const l of ["imageLeft", "compact"] as const) {
        sec.dataset.layout = l;
        tallest = Math.max(tallest, Math.round(g.getBoundingClientRect().height));
      }
      sec.dataset.layout = "hero";
      setReserve(tallest);
    }
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
    const onResize = () => {
      // Tracks are in points of the old canvas: a new window size goes back to the preset.
      if (customRef.current && px(getComputedStyle(g).gridTemplateColumns).length !== customRef.current.cols.length) {
        customRef.current = null;
        setCustom(null);
      }
      measure();
    };
    window.addEventListener("resize", onResize);
    void document.fonts?.ready.then(measure);
    return () => {
      ro.disconnect();
      window.removeEventListener("resize", onResize);
    };
  }, [measure]);

  // ----- the right edge: the whole grid is resized -----
  const moveTo = (clientX: number) => {
    const s = stageRef.current;
    if (!s) return;
    const r = s.getBoundingClientRect();
    const avail = Math.max(1, s.clientWidth - (parseFloat(getComputedStyle(s).paddingRight) || 0));
    setWidth(Math.round(clamp(MIN_W, 100, ((clientX - r.left) / avail) * 100)));
  };
  const onDown = (e: PointerEvent<HTMLDivElement>) => {
    clear();
    const c = freeze();
    if (c) setCustom(c);
    e.currentTarget.setPointerCapture(e.pointerId);
    setLive(true);
    moveTo(e.clientX);
  };
  const onMove = (e: PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) moveTo(e.clientX);
  };
  const onUp = (e: PointerEvent<HTMLDivElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    setLive(false);
  };
  const onKey = (e: KeyboardEvent<HTMLDivElement>) => {
    const d = e.key === "ArrowRight" || e.key === "ArrowUp" ? 2 : e.key === "ArrowLeft" || e.key === "ArrowDown" ? -2 : 0;
    if (!d) return;
    e.preventDefault();
    clear();
    const c = freeze();
    if (c) setCustom(c);
    setWidth((w) => clamp(MIN_W, 100, Math.round(w) + d));
  };

  // ----- track dividers -----
  const trackDown = (axis: "col" | "row", i: number) => (e: PointerEvent<HTMLElement>) => {
    clear();
    const c = freeze();
    if (!c) return;
    const list = axis === "col" ? c.cols : c.rows;
    grab.current = { x: e.clientX, y: e.clientY, a: list[i], b: list[i + 1] };
    e.currentTarget.setPointerCapture(e.pointerId);
    setLive(true);
    setTrack({ axis, i });
  };
  const trackMove = (axis: "col" | "row", i: number) => (e: PointerEvent<HTMLElement>) => {
    const g = grab.current;
    if (!g || !e.currentTarget.hasPointerCapture(e.pointerId)) return;
    // Column tracks are fr weights of the canvas; a pointer distance is the same number of points at full width.
    const scale = axis === "col" && canvasRef.current ? (customRef.current?.cols.reduce((s, v) => s + v, 0) ?? 1) / Math.max(1, canvasRef.current.getBoundingClientRect().width - gap * (nCols - 1)) : 1;
    resize(axis, i, g.a, g.b, (axis === "col" ? e.clientX - g.x : e.clientY - g.y) * scale);
  };
  const trackUp = (e: PointerEvent<HTMLElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    grab.current = null;
    setLive(false);
  };
  const step = (axis: "col" | "row", i: number, d: number) => {
    clear();
    const c = freeze();
    if (!c) return;
    const list = axis === "col" ? c.cols : c.rows;
    if (i + 1 >= list.length) return;
    resize(axis, i, list[i], list[i + 1], d);
    setTrack({ axis, i });
  };
  const trackKey = (axis: "col" | "row", i: number) => (e: KeyboardEvent<HTMLElement>) => {
    const fwd = axis === "col" ? "ArrowRight" : "ArrowDown", back = axis === "col" ? "ArrowLeft" : "ArrowUp";
    if (e.key !== fwd && e.key !== back) return;
    e.preventDefault();
    step(axis, i, e.key === fwd ? 8 : -8);
  };

  // ----- moving a field -----
  const cellAt = (x: number, y: number): CellName | null => {
    const c = canvasRef.current;
    if (!c) return null;
    const cr = c.getBoundingClientRect();
    const cur = customRef.current;
    for (const k of CELLS) {
      const r = rectsRef.current[k];
      if (!r || (cur && !cur.place[k])) continue;
      if (x - cr.left >= r.x && x - cr.left <= r.x + r.w && y - cr.top >= r.y && y - cr.top <= r.y + r.h) return k;
    }
    return null;
  };
  const gripDown = (e: PointerEvent<HTMLButtonElement>) => {
    clear();
    const c = freeze();
    if (c) setCustom(c);
    grab.current = { x: e.clientX, y: e.clientY, a: 0, b: 0 };
    moved.current = false;
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const gripMove = (s: Slot) => (e: PointerEvent<HTMLButtonElement>) => {
    const g = grab.current;
    if (!g || !e.currentTarget.hasPointerCapture(e.pointerId)) return;
    const dx = e.clientX - g.x, dy = e.clientY - g.y;
    if (!moved.current && Math.hypot(dx, dy) < 4) return;
    moved.current = true;
    const over = cellAt(e.clientX, e.clientY);
    setDrag({ slot: s, dx, dy, over: over === s ? null : over });
  };
  const gripUp = (s: Slot) => (e: PointerEvent<HTMLButtonElement>) => {
    if (e.currentTarget.hasPointerCapture(e.pointerId)) e.currentTarget.releasePointerCapture(e.pointerId);
    grab.current = null;
    if (moved.current) {
      const over = cellAt(e.clientX, e.clientY);
      if (over && over !== s) swap(s, over);
      setPicked(null);
    }
    setDrag(null);
  };
  /** Tap path (touch and keyboard): pick a field, then pick the cell it should go to. */
  const gripClick = (s: Slot) => () => {
    if (moved.current) {
      moved.current = false;
      return;
    }
    clear();
    setPicked((p) => {
      if (p && p !== s) {
        swap(p, s);
        return null;
      }
      return p === s ? null : s;
    });
  };
  const gripKey = (s: Slot) => (e: KeyboardEvent<HTMLButtonElement>) => {
    const dir = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (e.key === "Escape") setPicked(null);
    if (!dir) return;
    e.preventDefault();
    clear();
    const c = freeze();
    const from = rectsRef.current[s];
    if (!c || !from) return;
    // The nearest cell in that direction, by centre.
    const cx = from.x + from.w / 2, cy = from.y + from.h / 2;
    let best: CellName | null = null, bestD = Infinity;
    for (const k of CELLS) {
      const r = rectsRef.current[k];
      if (k === s || !r || !c.place[k]) continue;
      const dx = r.x + r.w / 2 - cx, dy = r.y + r.h / 2 - cy;
      const along = dx * dir[0] + dy * dir[1], across = Math.abs(dx * dir[1]) + Math.abs(dy * dir[0]);
      if (along <= 4) continue;
      const d = along + across * 2;
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    if (best) swap(s, best);
  };
  const cellClick = (k: CellName) => () => {
    if (picked && picked !== k) {
      swap(picked, k);
      setPicked(null);
    }
  };

  const on = (s: Slot) => taken.includes(s);
  const edited = !!custom;
  const rows = rowPx.length || (compact ? 2 : 3);
  const snap = live || !!drag;
  const stageH = Math.max(reserve, gridH);
  const lift = ready && stageH > gridH ? Math.round((stageH - gridH) / 2) : 0;
  const inLayout = (s: CellName) => (custom ? !!custom.place[s] : s === "body" ? !compact : s === "image" ? layout === "imageLeft" : true);

  // Once fitted, every line sits at the top of the headline and is put on its own baseline by transform, so a
  // change of size, break or leading moves no line in layout (nothing for the page to shift).
  const titleStyle = fit
    ? ({ fontVariationSettings: `"wdth" ${fit.wdth}`, fontSize: `${fit.size}px`, height: `${(fit.lines.length * fit.lh + DESC).toFixed(3)}em`, paddingBottom: 0 } as CSSProperties)
    : undefined;
  const lines = fit?.lines ?? (compact ? L1 : L3);

  const ghostGrid: CSSProperties | undefined = custom
    ? { gridTemplateColumns: custom.cols.map((v) => `minmax(0, ${v}fr)`).join(" "), gridTemplateRows: custom.rows.map((v) => `${v}px`).join(" ") }
    : undefined;
  const ghostCell = (s: CellName): CSSProperties | undefined => {
    const p = custom?.place[s];
    return p ? { gridColumn: `${p.c0} / ${p.c1}`, gridRow: `${p.r0} / ${p.r1}` } : undefined;
  };

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
          <H className="display display-xl hero-title" style={titleStyle} data-lines={lines.length} data-fit={fit ? "true" : "false"}>
            {lines.map((l, i) => (
              <span key={l} style={fit ? { position: "absolute", left: 0, top: 0, transform: `translate3d(0, ${(fit.lh * i).toFixed(3)}em, 0)` } : undefined}>
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
                <SiteLink href="/docs/api/overview" className="btn btn-ghost">
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

  // ruler geometry, in canvas px
  const colX = colPx.reduce<number[]>((a, w, i) => [...a, i === 0 ? 0 : a[i - 1] + colPx[i - 1] + gap], []);
  const rowGap = gap;
  const rowY = rowPx.reduce<number[]>((a, v, i) => [...a, i === 0 ? 0 : a[i - 1] + rowPx[i - 1] + rowGap], []);
  const sel = track && (track.axis === "col" ? colPx[track.i] : rowPx[track.i]);

  return (
    <section
      ref={sectionRef}
      id="top"
      className="hero blueprint"
      data-layout={layout}
      data-done={done ? "true" : "false"}
      data-dragging={snap ? "true" : "false"}
      data-ready={ready ? "true" : "false"}
      data-edited={edited ? "true" : "false"}
      data-picking={picked ? "true" : "false"}
    >
      <div className="shell hero-shell">
        <div className="hero-bar">
          <div className="hero-pick" role="group" aria-label="Template layout">
            {LAYOUTS.map((l) => (
              <button key={l} type="button" className="hero-pick-btn" aria-pressed={layout === l && !edited} onClick={() => pick(l)}>
                <Glyph l={l} />
                {l}
              </button>
            ))}
            <button type="button" className="hero-pick-btn hero-replay" onClick={() => play(true)}>
              Replay
            </button>
            <button type="button" className="hero-pick-btn hero-reset" disabled={!edited && width === 100} onClick={() => { clear(); reset(); }}>
              Reset
            </button>
          </div>
          {track && sel ? (
            <div className="hero-stepper" role="group" aria-label={`${track.axis === "col" ? "Column" : "Row"} ${track.i + 1} size`}>
              <span className="readout">
                {track.axis} {track.i + 1}
              </span>
              <button type="button" className="hero-pick-btn" aria-label="Smaller" onClick={() => step(track.axis, track.i, -8)}>
                −
              </button>
              <span className="readout hero-stepper-v">{Math.round(sel)} pt</span>
              <button type="button" className="hero-pick-btn" aria-label="Larger" onClick={() => step(track.axis, track.i, 8)}>
                +
              </button>
            </div>
          ) : (
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
                  const c = freeze();
                  if (c) setCustom(c);
                  setWidth(Number(e.target.value));
                }}
              />
            </label>
          )}
          <p className="readout hero-readout">
            <span className="hero-readout-k">grid · </span>
            {nCols} × {rows} · {pad4(canvasW)} pt
            <span className="hero-hint"> · {picked ? `now pick a cell for ${picked}` : "drag a field, a divider or the edge"}</span>
          </p>
        </div>

        <div ref={stageRef} className="hero-stage">
          <div
            ref={canvasRef}
            className="hero-canvas"
            style={{ ["--tpl-w" as string]: width, width: `calc(var(--tpl-w) * 1%)`, height: reserve ? stageH + head : undefined }}
          >
            {/* column tracks with their dividers, as the Designer's ruler draws them */}
            <div className="hero-ruler" data-cols={nCols}>
              {colPx.map((w, i) => (
                <button
                  key={`c${i}`}
                  type="button"
                  className="hero-ruler-track"
                  aria-label={`Column ${i + 1}, ${Math.round(w)} points`}
                  aria-pressed={track?.axis === "col" && track.i === i}
                  disabled={i === colPx.length - 1}
                  style={{ width: w, transform: `translate3d(${colX[i]}px, 0, 0)` }}
                  onClick={() => setTrack((t) => (t?.axis === "col" && t.i === i ? null : { axis: "col", i }))}
                >
                  {Math.round(w)}
                </button>
              ))}
              {colPx.slice(0, -1).map((w, i) => (
                <div
                  key={`d${i}`}
                  className="hero-divider hero-divider-col"
                  role="separator"
                  tabIndex={0}
                  aria-orientation="vertical"
                  aria-label={`Resize column ${i + 1}`}
                  aria-valuenow={Math.round(w)}
                  aria-valuemin={MIN_TRACK}
                  style={{ transform: `translate3d(${colX[i] + w + gap / 2}px, 0, 0)`, ["--guide" as string]: `${head + gridH + lift}px` }}
                  onPointerDown={trackDown("col", i)}
                  onPointerMove={trackMove("col", i)}
                  onPointerUp={trackUp}
                  onPointerCancel={trackUp}
                  onKeyDown={trackKey("col", i)}
                  onDoubleClick={() => edit((c) => ({ ...c, cols: c.cols.map(() => c.cols.reduce((s, v) => s + v, 0) / c.cols.length) }))}
                />
              ))}
            </div>
            {/* row tracks, left of the canvas */}
            <div className="hero-rows" style={{ top: head, transform: `translate3d(0, ${lift}px, 0)` }}>
              {rowPx.map((v, i) => (
                <span key={`r${i}`} className="hero-rows-track" aria-hidden style={{ height: v, transform: `translate3d(0, ${rowY[i]}px, 0)` }}>
                  {Math.round(v)}
                </span>
              ))}
              {rowPx.slice(0, -1).map((v, i) => (
                <div
                  key={`rd${i}`}
                  className="hero-divider hero-divider-row"
                  role="separator"
                  tabIndex={0}
                  aria-orientation="horizontal"
                  aria-label={`Resize row ${i + 1}`}
                  aria-valuenow={Math.round(v)}
                  aria-valuemin={MIN_ROW}
                  style={{ transform: `translate3d(0, ${rowY[i] + v + rowGap / 2}px, 0)`, ["--guide" as string]: `${canvasW}px` }}
                  onPointerDown={trackDown("row", i)}
                  onPointerMove={trackMove("row", i)}
                  onPointerUp={trackUp}
                  onPointerCancel={trackUp}
                  onKeyDown={trackKey("row", i)}
                />
              ))}
            </div>

            {/* the solver: a real CSS grid. It is what the server renders; once measured it is hidden and the cells below copy it. */}
            <div ref={ghostRef} className="g hero-grid hero-ghost" style={ghostGrid} aria-hidden={ready ? true : undefined} inert={ready ? true : undefined}>
              {CELLS.filter(inLayout).map((s) => (
                <div key={s} className={`cell hero-c-${s}`} data-ghost={s} style={ghostCell(s)}>
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
                  const d = drag && drag.slot === s ? drag : null;
                  return (
                    <div
                      key={s}
                      className={`cell hero-cell hero-c-${s}`}
                      data-slot={s}
                      data-here={here ? "true" : "false"}
                      data-over={drag?.over === s ? "true" : "false"}
                      data-picked={picked === s ? "true" : "false"}
                      data-drag={d ? "true" : "false"}
                      aria-hidden={here ? undefined : true}
                      inert={here ? undefined : true}
                      style={{
                        transform: `translate3d(${r.x + (d ? d.dx : 0)}px, ${r.y + (d ? d.dy : 0)}px, 0)`,
                        width: r.w,
                        height: r.h,
                      }}
                      onClick={picked ? cellClick(s) : undefined}
                    >
                      <span className="slot">{s}</span>
                      {s !== "image" && (
                        <>
                          <button
                            type="button"
                            className="hero-grip"
                            aria-label={`Move ${s}`}
                            aria-pressed={picked === s}
                            onPointerDown={gripDown}
                            onPointerMove={gripMove(s)}
                            onPointerUp={gripUp(s)}
                            onPointerCancel={gripUp(s)}
                            onClick={(e) => {
                              e.stopPropagation();
                              gripClick(s)();
                            }}
                            onKeyDown={gripKey(s)}
                          >
                            <GripVertical aria-hidden />
                          </button>
                          <div className="hero-field" data-on={on(s) ? "true" : "false"}>
                            {content(s, false)}
                          </div>
                        </>
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
              <span aria-hidden className="hero-handle-tag">{pad4(canvasW)} pt</span>
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
