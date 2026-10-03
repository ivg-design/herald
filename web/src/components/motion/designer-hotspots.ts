// ============================================================================================
// RE-PLACE THESE AFTER DROPPING IN THE REAL SCREENSHOTS (public/designer-light.png / designer-dark.png).
// The positions below are a guess for a typical Designer layout (16:10 window). All values are
// PERCENTAGES of the screenshot frame (0..100):
//   dot    = centre of the numbered circle
//   region = the rectangle that stays lit when the hotspot is active (x,y = top-left, w,h = size)
//   card   = which side of the dot the info card opens on (on narrow screens a bottom caption is used)
// ============================================================================================

export interface Hotspot {
  id: string;
  n: number;
  title: string;
  body: string;
  dot: { x: number; y: number };
  region: { x: number; y: number; w: number; h: number };
  card: "left" | "right" | "top" | "bottom";
}

export const HOTSPOTS: Hotspot[] = [
  {
    id: "issuer",
    n: 1,
    title: "Issuer & templates",
    body: "Pick the app you are designing for; its manifest fields become the tokens you can place.",
    dot: { x: 9, y: 22 },
    region: { x: 0, y: 8, w: 18, h: 62 },
    card: "right",
  },
  {
    id: "preview",
    n: 2,
    title: "Live preview",
    body: "The real banner, light or dark, sample or last data, at least half the window.",
    dot: { x: 50, y: 14 },
    region: { x: 18, y: 8, w: 56, h: 22 },
    card: "bottom",
  },
  {
    id: "grid",
    n: 3,
    title: "Grid canvas",
    body: "Any rows × columns; drag the rulers to resize tracks, merge or split cells, drop components.",
    dot: { x: 46, y: 46 },
    region: { x: 18, y: 30, w: 56, h: 40 },
    card: "bottom",
  },
  {
    id: "inspector",
    n: 4,
    title: "Inspector",
    body: "Every property of the selected cell or component: binding, style, symbol, alignment, when empty.",
    dot: { x: 87, y: 36 },
    region: { x: 74, y: 8, w: 26, h: 62 },
    card: "left",
  },
  {
    id: "components",
    n: 5,
    title: "Components",
    body: "Text, image, icon, badge, progress, buttons, actions, Rive, drag onto a cell.",
    dot: { x: 30, y: 85 },
    region: { x: 0, y: 70, w: 52, h: 30 },
    card: "top",
  },
  {
    id: "actions",
    n: 6,
    title: "Actions",
    body: "Which buttons appear, their style, and what they run: scripts, Shortcuts, callbacks, Open app.",
    dot: { x: 76, y: 85 },
    region: { x: 52, y: 70, w: 48, h: 30 },
    card: "top",
  },
];
