// Regions are measured on the RAW window capture (2560 x 1664 px). The published screenshots place that capture on a
// gradient canvas with an 80 px margin at 2x (2720 x 1824) and scale it uniformly, so a raw rectangle converts to
// percentages of the framed image with toPct() below. Re-measure on .shots-raw/designer-*.png if the UI changes.

export interface Rect { x: number; y: number; w: number; h: number }

export interface Hotspot {
  id: string;
  n: number;
  title: string;
  body: string;
  /** Rectangle on the raw capture, px. */
  raw: Rect;
  /** Same rectangle as percentages of the framed image (derived). */
  region: Rect;
  /** Centre of the numbered dot, percent of the framed image (sits on a blank spot inside the region). */
  dot: { x: number; y: number };
  /** Where the card opens relative to the region; `at` picks which end of that side it hugs. */
  card: { side: "left" | "right" | "above" | "below"; at: "start" | "end" };
}

const CANVAS_W = 2720;
const CANVAS_H = 1824;
const MARGIN = 80;

export function toPct(r: Rect): Rect {
  return {
    x: ((MARGIN + r.x) / CANVAS_W) * 100,
    y: ((MARGIN + r.y) / CANVAS_H) * 100,
    w: (r.w / CANVAS_W) * 100,
    h: (r.h / CANVAS_H) * 100,
  };
}

const rawDot = (x: number, y: number) => ({ x: ((MARGIN + x) / CANVAS_W) * 100, y: ((MARGIN + y) / CANVAS_H) * 100 });

type Def = Omit<Hotspot, "region" | "dot"> & { rawDot: { x: number; y: number } };

const DEFS: Def[] = [
  {
    id: "issuer", n: 1, title: "Issuer & templates",
    body: "Pick the app you are designing for. Its manifest fields become the tokens you place; each issuer keeps its own templates and a default.",
    raw: { x: 0, y: 133, w: 458, h: 530 }, rawDot: { x: 420, y: 250 },
    card: { side: "right", at: "start" },
  },
  {
    id: "preview", n: 2, title: "Live preview",
    body: "The real banner, rendered by the same code that draws it on screen. Sample data or the last real notification, light or dark. Send test shows it for real.",
    raw: { x: 463, y: 133, w: 1405, h: 762 }, rawDot: { x: 512, y: 269 },
    card: { side: "below", at: "start" },
  },
  {
    id: "grid", n: 3, title: "Grid canvas",
    body: "Any rows × columns. Drag the rulers to resize tracks, merge or split cells, drop components, align on nine points. The dashed cells are empty slots.",
    raw: { x: 463, y: 900, w: 1405, h: 764 }, rawDot: { x: 512, y: 1062 },
    card: { side: "above", at: "start" },
  },
  {
    id: "inspector", n: 4, title: "Inspector",
    body: "Everything about the selection: name, accent, what empty fields do (collapse or leave in place), grid width, gap, padding, every column and row.",
    raw: { x: 1873, y: 133, w: 687, h: 1531 }, rawDot: { x: 2496, y: 320 },
    card: { side: "left", at: "start" },
  },
  {
    id: "components", n: 5, title: "Components",
    body: "Text, image, app icon, time, button, actions, icon button, badge, stack count, progress, Rive animation, spacer. Drag onto a cell or click to add.",
    raw: { x: 0, y: 672, w: 458, h: 495 }, rawDot: { x: 410, y: 705 },
    card: { side: "right", at: "start" },
  },
  {
    id: "assets", n: 6, title: "Assets & fields",
    body: "Rive files the issuer ships, and the issuer’s fields with their sample values. Drag a field onto a cell to bind it.",
    raw: { x: 0, y: 1171, w: 458, h: 493 }, rawDot: { x: 410, y: 1194 },
    card: { side: "right", at: "end" },
  },
];

export const HOTSPOTS: Hotspot[] = DEFS.map(({ rawDot: d, ...h }) => ({ ...h, region: toPct(h.raw), dot: rawDot(d.x, d.y) }));
