// Full-page screenshots of docs pages, headless. Usage: BASE=http://localhost:3297 node scripts/shoot-docs.mjs <outdir> <widths,comma> <path> [path...]
import puppeteer from "puppeteer-core";
import { mkdirSync } from "node:fs";
const [out, widths, ...paths] = process.argv.slice(2);
const BASE = process.env.BASE || "http://localhost:3297";
mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: "new", args: ["--no-first-run", "--window-position=-2000,-2000"] });
try {
  const page = await browser.newPage();
  for (const w of widths.split(",").map(Number)) {
    await page.setViewport({ width: w, height: 900, deviceScaleFactor: 1 });
    for (const p of paths) {
      await page.goto(BASE + p, { waitUntil: "networkidle0", timeout: 30000 });
      await page.evaluate(() => document.querySelectorAll("img[loading=lazy]").forEach((i) => (i.loading = "eager")));
      await new Promise((r) => setTimeout(r, 250));
      const name = p.replace(/^\/docs\/?/, "").replace(/\//g, "__") || "index";
      // YS=0,1200 takes viewport-sized pieces at those scroll offsets instead of one full-page image.
      if (process.env.YS) {
        for (const y of process.env.YS.split(",").map(Number)) {
          await page.screenshot({ path: `${out}/${name}-${w}-y${y}.png`, clip: { x: 0, y, width: w, height: Number(process.env.H || 1100) }, captureBeyondViewport: true });
        }
      } else await page.screenshot({ path: `${out}/${name}-${w}.png`, fullPage: true });
    }
  }
} finally { await browser.close(); }
