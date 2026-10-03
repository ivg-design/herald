// Headless review screenshots. Usage: BASE=http://localhost:3202 OUT=/path node scripts/shoot.mjs [widths...]
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import puppeteer from "puppeteer-core";

const BASE = process.env.BASE || "http://localhost:3202";
const OUT = process.env.OUT || ".reviews/shots";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const widths = process.argv.slice(2).map(Number).filter(Boolean);
const W = widths.length ? widths : [1440, 1280, 834, 390];
mkdirSync(OUT, { recursive: true });
const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--window-position=-2000,-2000"] });
for (const w of W) {
  const page = await browser.newPage();
  await page.setViewport({ width: w, height: Math.round(w * 0.625), deviceScaleFactor: 1 });
  await page.goto(BASE + (process.env.PATHNAME || "/"), { waitUntil: "load", timeout: 60000 }); await new Promise((r) => setTimeout(r, 2500));
  // settle entrance animations and lazy content
  await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 600) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 120)); } window.scrollTo(0, 0); });
  await new Promise((r) => setTimeout(r, 1200));
  const path = join(OUT, `${process.env.NAME || "page"}-${w}.png`);
  await page.screenshot({ path, fullPage: true });
  const h = await page.evaluate(() => ({ h: document.body.scrollHeight, overflow: document.documentElement.scrollWidth > innerWidth }));
  console.log(`${path} ${w}x${h.h}${h.overflow ? "  HORIZONTAL OVERFLOW" : ""}`);
  await page.close();
}
await browser.close();
