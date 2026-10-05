// Herald: composites raw window captures (screencapture -l -o, 2x, alpha corners) onto a vivid diagonal gradient with a
// soft drop shadow and a consistent margin. Writes <name>@2x.png and <name>.png (1x) into public/shots.
//
//   node scripts/frame-shots.mjs <rawDir> [--out public/shots] [--margin 40]
//   node scripts/frame-shots.mjs <rawDir> --docs --out public/shots/docs
//
// --docs frames the documentation set made by `scripts/docs-screenshots.sh` (raw captures plus the shots-meta.json the capture mode
// writes): every shot is composited with a margin of about 6.5 % of its width per side (more for small banners), written as
// <name>@2x.png and <name>.png (1x), and manifest.json (an array) is written next to them.
//
// Gradients are parameterised per shot in GRADIENTS (angle in degrees, CSS-style: 135 = top-left to bottom-right).
import { readdirSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { basename, extname, join, resolve } from "node:path";
import sharp from "sharp";

const GRADIENTS = {
  sunset: { angle: 150, stops: ["#f6b25c", "#ef7a6b", "#e0508a", "#b44fd0"] },
  ocean:  { angle: 140, stops: ["#37d0e6", "#3a8cf0", "#5a4de0", "#8a3fd6"] },
  forest: { angle: 150, stops: ["#c6e05a", "#4cc98a", "#1fa4b0", "#2f6fd8"] },
  berry:  { angle: 145, stops: ["#ff9a8b", "#ff5e8e", "#c23fcf", "#6a47e6"] },
  lagoon: { angle: 135, stops: ["#ffe27a", "#7be0a3", "#2ec6d6", "#3b82f6"] },
  ember:  { angle: 155, stops: ["#ffd166", "#ff8a4c", "#f0506e", "#a83fd0"] },
};
// shot name -> gradient preset (anything unlisted uses the default)
const PRESET = {
  "designer-light": "ocean", "designer-dark": "berry", "quick-send": "lagoon", "symbol-browser": "forest", history: "ember",
  "banner-plain": "sunset", "banner-confirm": "ember", "banner-reply": "ocean",
  "settings-general": "lagoon", "settings-apps": "forest", "settings-mcp": "ocean", "settings-cloud": "berry",
  "settings-quiet-hours": "sunset", "settings-voice": "ember",
};
const DEFAULT_PRESET = "sunset";
// --docs: gradient per shot (varied, harmonious: cool for the designer, warm for settings, and so on); "-dark" shots get the same
// preset darkened so a pair reads as one set.
const DOCS_PRESET = (name) => {
  const n = name.replace(/-dark$/, "");
  if (n === "designer-overview") return "ocean";
  if (n.startsWith("designer-inspector")) return "lagoon";
  if (["designer-palette", "designer-live-preview", "designer-grid-editing"].includes(n)) return "forest";
  if (n.startsWith("designer-action")) return "berry";
  if (n.startsWith("designer-")) return "ocean";
  if (n.startsWith("settings-cloud")) return "berry";
  if (n === "settings-apps" || n === "settings-actions") return "forest";
  if (n.startsWith("settings-")) return "sunset";
  if (n.startsWith("history")) return "ember";
  if (n === "menu") return "lagoon";
  if (n.startsWith("banner-stack")) return "ocean";
  if (n.startsWith("banner-")) return ["sunset", "ocean", "berry", "lagoon", "ember", "forest"][[...n].reduce((a, c) => a + c.charCodeAt(0), 0) % 6];
  return DEFAULT_PRESET;
};
const darken = (g) => ({ ...g, stops: g.stops.map((c) => "#" + [1, 3, 5].map((i) => Math.round(parseInt(c.slice(i, i + 2), 16) * 0.42).toString(16).padStart(2, "0")).join("")) });

const args = process.argv.slice(2);
const flag = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const rawDir = resolve(args[0] ?? ".shots-raw");
const outDir = resolve(flag("--out", "public/shots"));
const MARGIN = Number(flag("--margin", 40)) * 2; // px at 2x
mkdirSync(outDir, { recursive: true });

function gradientSvg(w, h, { angle, stops }) {
  const a = ((angle - 90) * Math.PI) / 180; // CSS angle -> vector
  const cx = w / 2, cy = h / 2, len = Math.abs(w * Math.cos(a)) + Math.abs(h * Math.sin(a));
  const x1 = cx - (Math.cos(a) * len) / 2, y1 = cy - (Math.sin(a) * len) / 2;
  const x2 = cx + (Math.cos(a) * len) / 2, y2 = cy + (Math.sin(a) * len) / 2;
  const s = stops.map((c, i) => `<stop offset="${(i / (stops.length - 1)) * 100}%" stop-color="${c}"/>`).join("");
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${s}</linearGradient></defs><rect width="${w}" height="${h}" fill="url(#g)"/></svg>`);
}

async function shadowOf(win, blur, opacity) {
  const { width, height } = await sharp(win).metadata();
  const alpha = await sharp(win).ensureAlpha().extractChannel(3).raw().toBuffer();
  const a = Buffer.alloc(width * height * 4, 0);
  for (let i = 0; i < width * height; i++) a[i * 4 + 3] = Math.round(alpha[i] * opacity);
  return sharp(a, { raw: { width, height, channels: 4 } }).blur(blur).png().toBuffer();
}

/** Frame `win` (PNG buffer, 2x) on a canvas. If `canvas` is given the window is scaled to fit inside it instead of sizing the canvas to the window. */
export async function frame(win, preset, canvas, margin = MARGIN, gradient) {
  let { width: ww, height: wh } = await sharp(win).metadata();
  let W, H;
  if (canvas) {
    W = canvas.w; H = canvas.h;
    const scale = Math.min((W * 0.8) / ww, (H * canvas.fill) / wh);
    ww = Math.round(ww * scale); wh = Math.round(wh * scale);
    win = await sharp(win).resize(ww, wh, { kernel: "lanczos3" }).png().toBuffer();
  } else { W = ww + margin * 2; H = wh + margin * 2; }
  const left = Math.round((W - ww) / 2), top = Math.round((H - wh) / 2);
  const pad = Math.min(80, margin - 4);
  const sh1 = await shadowOf(await sharp(win).extend({ top: pad, bottom: pad, left: pad, right: pad, background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer(), 28, 0.38);
  const sh2 = await shadowOf(await sharp(win).extend({ top: pad, bottom: pad, left: pad, right: pad, background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer(), 6, 0.3);
  return sharp(gradientSvg(W, H, gradient ?? GRADIENTS[preset] ?? GRADIENTS[DEFAULT_PRESET]))
    .composite([
      { input: sh1, left: left - pad, top: top - pad + 22 },
      { input: sh2, left: left - pad, top: top - pad + 6 },
      { input: win, left, top },
    ])
    .png();
}


const DOCS = args.includes("--docs");
if (DOCS) {
  const meta = JSON.parse(readFileSync(join(rawDir, "shots-meta.json"), "utf8"));
  const order = { designer: 0, settings: 1, history: 2, menu: 3, banners: 4 };
  meta.sort((a, b) => (order[a.section] - order[b.section]) || a.name.localeCompare(b.name));
  const out = [];
  for (const m of meta) {
    const rawFile = join(rawDir, `${m.name}.png`);
    if (!existsSync(rawFile)) continue;
    const { width: rw } = await sharp(rawFile).metadata();
    const small = m.section === "banners" || m.section === "menu";
    const margin = Math.max(small ? 80 : 56, Math.round(rw * (small ? 0.11 : 0.065)));
    const preset = DOCS_PRESET(m.name);
    const g = m.name.endsWith("-dark") ? darken(GRADIENTS[preset]) : GRADIENTS[preset];
    const buf = await (await frame(rawFile, preset, undefined, margin, g)).toBuffer();
    const { width, height } = await sharp(buf).metadata();
    mkdirSync(outDir, { recursive: true });
    await sharp(buf).png({ compressionLevel: 9 }).toFile(join(outDir, `${m.name}@2x.png`));
    const w1 = Math.round(width / 2), h1 = Math.round(height / 2);
    await sharp(buf).resize(w1, h1, { kernel: "lanczos3" }).png({ compressionLevel: 9 }).toFile(join(outDir, `${m.name}.png`));
    console.log(`${m.name}: ${w1}x${h1} (@2x ${width}x${height})`);
    out.push({ file: `${m.name}.png`, file2x: `${m.name}@2x.png`, framed: true, width: w1, height: h1, width2x: width, height2x: height,
               appearance: m.appearance, title: m.title, shows: m.shows, section: m.section });
  }
  writeFileSync(join(outDir, "manifest.json"), JSON.stringify(out, null, 2) + "\n");
  process.exit(0);
}

const manifest = {};
const save = async (img, name, { max = 0, dir = outDir } = {}) => {
  let buf = await img.toBuffer();
  let { width, height } = await sharp(buf).metadata();
  if (max && width > max) { buf = await sharp(buf).resize(max, null, { kernel: "lanczos3" }).png().toBuffer(); ({ width, height } = await sharp(buf).metadata()); }
  await sharp(buf).png({ compressionLevel: 9 }).toFile(join(dir, `${name}.png`));
  console.log(`${name}: ${width}x${height}`);
  return { w: width, h: height };
};
const publicDir = resolve(outDir, "..");
for (const f of readdirSync(rawDir).filter((f) => extname(f) === ".png").sort()) {
  const name = basename(f, ".png");
  const framed = await frame(join(rawDir, f), PRESET[name] ?? DEFAULT_PRESET);
  if (name.startsWith("designer-")) manifest[name] = await save(framed, name, { max: 2000, dir: publicDir });
  else manifest[name] = await save(framed, name, { max: name.startsWith("banner-") ? 1000 : 1800 });
}
writeFileSync(join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2));
// the page reads dims of the designer shots from the same manifest
