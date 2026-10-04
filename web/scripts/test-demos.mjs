// Headless behaviour tests for every interactive part of the Herald page.
// Usage: BASE=http://localhost:3221 node scripts/test-demos.mjs   (serve a built site first; never port 3102)
import puppeteer from "puppeteer-core";

const BASE = process.env.BASE || "http://localhost:3221";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let pass = 0, fail = 0;
const failed = [];
const ok = (c, name, extra = "") => {
  c ? pass++ : (fail++, failed.push(name));
  console.log(`${c ? "PASS" : "FAIL"}  ${name}${c ? "" : extra ? "  [" + String(extra).slice(0, 200) + "]" : ""}`);
};

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: "new",
  args: ["--no-first-run", "--window-position=-2000,-2000", "--window-size=1440,900"],
});
for (const sig of ["uncaughtException", "unhandledRejection"]) process.on(sig, async (e) => { console.error(sig, e); await browser.close().catch(() => {}); process.exit(2); });
const ctx = browser.defaultBrowserContext();
await ctx.overridePermissions(BASE, ["clipboard-read", "clipboard-write", "clipboard-sanitized-write"]);
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900 });
const errors = [];
page.on("pageerror", (e) => errors.push("pageerror: " + String(e)));
page.on("console", (m) => {
  if (m.type() !== "error") return;
  const url = m.location()?.url || "";
  if (/favicon/i.test(url) || /favicon/i.test(m.text())) return;
  if (/\/docs\/guides\/nope$/.test(url)) return; // the 404 the round-2 section asks for
  errors.push(`console: ${m.text()} ${url}`);
});

// ---------- helpers ----------
async function waitFor(fn, timeout = 4000, step = 100) {
  const end = Date.now() + timeout;
  for (;;) {
    let v = false;
    try { v = await fn(); } catch { v = false; }
    if (v) return v;
    if (Date.now() > end) return false;
    await sleep(step);
  }
}
const text = (sel) => page.$eval(sel, (e) => e.innerText).catch(() => "");
const has = async (sel, s) => (await text(sel)).includes(s);
const waitText = (sel, s, t = 4000) => waitFor(() => has(sel, s), t);
const waitGone = (sel, s, t = 4000) => waitFor(async () => !(await has(sel, s)), t);
const exists = (sel) => page.$(sel).then((e) => !!e);
const scrollToSel = async (sel, block = "center") => {
  await page.evaluate((sel, block) => document.querySelector(sel)?.scrollIntoView({ block, behavior: "instant" }), sel, block);
  await sleep(450);
};
const scrollTop = async () => { await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" })); await sleep(500); };
// find a button/link by exact visible text or aria-label inside a scope
async function findBtn(scope, label, starts = false) {
  const h = await page.evaluateHandle((scope, label, starts) => {
    const root = document.querySelector(scope);
    if (!root) return null;
    const m = (s) => (starts ? s.startsWith(label) : s === label);
    return [...root.querySelectorAll("button, a, label")].find((b) => m(b.innerText.trim()) || m(b.getAttribute("aria-label") || "")) || null;
  }, scope, label, starts);
  return h.asElement();
}
async function clickBtn(scope, label, opts = {}) {
  const el = await findBtn(scope, label, opts.starts);
  if (!el) throw new Error(`no "${label}" in ${scope}`);
  await el.evaluate((e) => e.scrollIntoView({ block: "center", behavior: "instant" }));
  await sleep(200);
  await el.click();
  await page.mouse.move(2, 2); // keep the pointer off the header bell
}
const jsClick = (scope, label, starts = false) =>
  page.evaluate((scope, label, starts) => {
    const root = document.querySelector(scope);
    const m = (s) => (starts ? s.startsWith(label) : s === label);
    const b = [...(root?.querySelectorAll("button, a, label") ?? [])].find((x) => m(x.innerText.trim()) || m(x.getAttribute("aria-label") || ""));
    if (!b) return false;
    b.click();
    return true;
  }, scope, label, starts);
const bellLabel = () => page.$eval(".hb-bell", (e) => e.getAttribute("aria-label")).catch(() => "");
const bellCount = async () => { const m = (await bellLabel()).match(/Show (\d+)/); return m ? Number(m[1]) : 0; };
const historyN = async () => { const m = (await text("main")).match(/(\d+) dismissed · kept in History/); return m ? Number(m[1]) : 0; };
const overlayText = () => text("#herald-overlay");
const section = async (name, fn) => {
  try { await fn(); } catch (e) { ok(false, `${name}: section crashed`, e.message); }
};
const ENT = /&[a-z#0-9]+;/i;

async function load(path, w = 1440, h = 900) {
  await page.setViewport({ width: w, height: h });
  await page.goto(BASE + path, { waitUntil: "load" });
  await sleep(1800);
}

// ============ 1 hero canvas ============
await section("hero", async () => {
  const S = "section#top";
  const st = () => page.$eval(S, (e) => ({ l: e.dataset.layout, d: e.dataset.done }));
  const pageErr0 = errors.length;
  await page.setViewport({ width: 1440, height: 900 });
  // record the earliest hero state from inside the page (a MutationObserver installed before any script runs)
  const probe = await page.evaluateOnNewDocument(() => {
    window.__early = null;
    window.__cls = 0;
    window.__layouts = [];
    new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; }).observe({ type: "layout-shift", buffered: true });
    const snap = () => {
      const t = document.querySelector("section#top"), o = document.querySelector("#herald-overlay");
      if (t && window.__layouts[window.__layouts.length - 1] !== t.dataset.layout) window.__layouts.push(t.dataset.layout);
      if (!t || t.dataset.layout !== "hero" || window.__early) return;
      window.__early = { l: t.dataset.layout, d: t.dataset.done, bell: document.querySelector(".hb-bell")?.getAttribute("aria-label") || "", ov: o ? o.innerText : "", ovExists: !!o, dock: !!document.querySelector("#top .hd, [aria-label='Herald banners']"), t: performance.now() };
    };
    new MutationObserver(snap).observe(document, { subtree: true, childList: true, attributes: true });
    document.addEventListener("DOMContentLoaded", snap);
  });
  await page.goto(BASE + "/", { waitUntil: "load" });
  await page.removeScriptToEvaluateOnNewDocument(probe.identifier);
  await page.mouse.move(2, 2);
  await waitFor(() => page.evaluate(() => !!window.__early), 5000, 20);
  const first = await page.evaluate(() => window.__early);
  ok(!!first, "hero: the load sequence is observable (section#top reaches data-layout=hero after hydration)");
  ok(first && !first.dock, "hero: no dock in the hero");
  ok(first && first.ov.trim() === "" && !/Show \d+/.test(first.bell), "hero: the Herald overlay starts empty (no seeded banners)", JSON.stringify(first));
  ok(first && first.l === "hero" && first.d === "false", "hero: load sequence starts at data-layout=hero, not done", JSON.stringify(first));
  // sequence end state
  ok(await waitFor(async () => (await bellCount()) === 1, 3000, 100), "hero: auto-send at about 1.9 s puts 1 on the bell", await bellLabel());
  ok(await waitFor(async () => (await st()).d === "true", 2500, 100), "hero: data-done becomes true after the sequence", JSON.stringify(await st()));
  ok(await waitFor(() => exists('#herald-overlay .hb-arrival[data-open="true"]'), 2000), "hero: auto-send shows one arrival card");
  ok((await page.$$eval('#herald-overlay .hb-arrival [aria-label$=" banner"]', (n) => n.length)) === 1, "hero: exactly one arrival banner card");
  ok(await has("#top [role=status]", "Sent"), "hero: status reads 'Sent' after the auto-send", await text("#top [role=status]"));
  // round 2: the template tours its three layouts once, by transform only, then the handle glides; nothing shifts
  const ptNow = async () => Number((/(\d+)\s*pt/.exec((await text(".hero-readout")).replace(/\u2007/g, "")) || [])[1] || 0);
  const pt0 = await ptNow();
  ok(await waitFor(async () => (await st()).l === "imageLeft", 4000, 50), "hero tour: the template moves to imageLeft by itself", JSON.stringify(await st()));
  ok(await waitFor(async () => (await st()).l === "compact", 3000, 50), "hero tour: then to compact", JSON.stringify(await st()));
  ok(await page.$eval("#top h1.hero-title", (e) => e.querySelectorAll("span").length === 1), "hero tour: in compact the headline is one line");
  ok(await waitFor(async () => (await st()).l === "hero", 3000, 50), "hero tour: and back to hero", JSON.stringify(await st()));
  const edState = () => page.evaluate(() => ({ ed: document.querySelector("#top").dataset.edited, icon: Math.round(document.querySelector('.hero-live [data-slot="icon"]').getBoundingClientRect().left), time: Math.round(document.querySelector('.hero-live [data-slot="time"]').getBoundingClientRect().left), cols: [...document.querySelectorAll(".hero-ruler-track")].map((e) => Number(e.textContent)) }));
  const ed0 = await edState();
  ok(await waitFor(async () => { const e = await edState(); return e.ed === "true" && e.icon > e.time; }, 4000, 50), "hero tour: a field is moved (icon and time swap cells)", JSON.stringify(await edState()));
  ok(await waitFor(async () => { const e = await edState(); return Math.max(...e.cols) > ed0.cols[0] + 30 && Math.min(...e.cols) === 24; }, 4000, 50), "hero tour: a column divider is dragged; one track takes the width, its neighbour stops at 24 pt", JSON.stringify((await edState()).cols));
  ok(await waitFor(async () => { const e = await edState(); return e.ed === "false" && e.icon < e.time && e.cols.every((c) => c === ed0.cols[0]); }, 4000, 50), "hero tour: the template goes back to the preset", JSON.stringify(await edState()));
  await sleep(700);
  const tourEnd = await page.evaluate(() => ({ cls: +window.__cls.toFixed(4), layouts: window.__layouts }));
  ok(tourEnd.layouts.join(">") === "hero>imageLeft>compact>hero", "hero tour: hero > imageLeft > compact > hero, once", tourEnd.layouts.join(">"));
  ok(tourEnd.cls < 0.01, `hero tour: cumulative layout shift stays under 0.01 through load, tour and glide (${tourEnd.cls})`);
  await sleep(1500);
  ok((await st()).l === "hero" && (await page.evaluate(() => window.__layouts.length)) === 4, "hero tour: it does not loop", JSON.stringify(await st()));
  ok((await page.$$eval("h1", (h) => h.length)) === 1, "hero: exactly one h1 in the document once the canvas is live");
  ok(await page.$eval("#top h1.hero-title", (e) => e.querySelectorAll("span").length === 3), "hero: the headline is set on three lines in the hero layout");
  ok(await page.$eval("#top", (e) => e.classList.contains("blueprint") && getComputedStyle(e).backgroundColor === "rgb(21, 84, 192)"), "hero: the canvas is on the blueprint ground");
  const ruler = await page.$$eval("#top .hero-ruler-track", (s) => s.map((e) => e.textContent.trim()));
  ok(ruler.length === 12 && ruler.every((x) => /^\d+$/.test(x)), "hero: the column ruler shows 12 track widths", ruler.join(","));
  // a real pointer drag on the handle
  const hb = await page.$eval(".hero-handle", (e) => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  const wdDrag0 = await page.$eval("#top h1.hero-title", (e) => parseFloat((e.style.fontVariationSettings.match(/"wdth"\s*([\d.]+)/) || [])[1]));
  await page.mouse.move(hb.x, hb.y);
  await page.mouse.down();
  for (let i = 1; i <= 10; i++) { await page.mouse.move(hb.x - i * 40, hb.y); await sleep(20); }
  await sleep(200);
  const dragMid = { pt: await ptNow(), wd: await page.$eval("#top h1.hero-title", (e) => parseFloat((e.style.fontVariationSettings.match(/"wdth"\s*([\d.]+)/) || [])[1])), fs: await page.$eval("#top h1.hero-title", (e) => getComputedStyle(e).fontSize), ruler: await page.$eval("#top .hero-ruler-track", (e) => Number(e.textContent)) };
  ok(dragMid.pt < pt0 - 300, "hero drag: dragging the handle with the mouse narrows the canvas", `${pt0} -> ${dragMid.pt}`);
  ok(dragMid.wd < wdDrag0 && dragMid.wd >= 62.5, "hero drag: the headline condenses on the width axis instead of shrinking", `${wdDrag0} -> ${dragMid.wd}`);
  const fsBase = parseFloat(await page.$eval(".hero-size", (e) => getComputedStyle(e).fontSize));
  ok(parseFloat(dragMid.fs) >= fsBase * 0.85 && parseFloat(dragMid.fs) <= fsBase, "hero drag: the headline keeps its size (it gives up at most 15 % for the wider leading of a condensed setting)", `${dragMid.fs} of ${fsBase}`);
  ok(dragMid.ruler < Number(ruler[0]), "hero drag: the ruler follows the tracks", `${ruler[0]} -> ${dragMid.ruler}`);
  const tcell = await page.evaluate(() => { const t = document.querySelector("#top .hero-live .hero-c-time"), x = t.querySelector(".hero-time"); const a = t.getBoundingClientRect(), b = x.getBoundingClientRect(); return { cell: Math.round(a.right), text: Math.round(b.left + x.scrollWidth) }; });
  ok(tcell.text <= tcell.cell, "hero drag: the time stays inside its cell at the narrow end", JSON.stringify(tcell));
  for (let i = 10; i >= -1; i--) { await page.mouse.move(hb.x - i * 40, hb.y); await sleep(15); }
  await page.mouse.up();
  await page.mouse.move(2, 2);
  await sleep(500);
  ok((await ptNow()) === pt0, "hero drag: dragging back restores the full width", `${await ptNow()}`);
  await sleep(300);
  await clickBtn("#top .hero-pick", "imageLeft");
  await sleep(700);

  // structure
  const cells = await page.$$eval("#top .cell", (c) => c.map((e) => e.className));
  for (const c of ["icon", "title", "time", "body", "actions", "image"]) ok(cells.some((x) => x.includes(`hero-c-${c}`)), `hero: cell hero-c-${c} exists in imageLeft`, cells.join("|"));
  const slots = await page.$$eval("#top .cell .slot", (s) => s.map((e) => e.textContent.trim()));
  ok(slots.length >= 6 && ["icon", "title", "time", "body", "actions", "image"].every((x) => slots.includes(x)), "hero: every cell carries a .slot label", slots.join("|"));
  const h1w = await page.$eval("#top h1.hero-title", (e) => e.style.fontVariationSettings);
  ok(/"wdth"\s*\d+/.test(h1w), "hero: h1.hero-title has inline font-variation-settings wdth", h1w);
  const btns = await page.$$eval("#top .hero-pick button", (b) => b.map((x) => [x.innerText.trim(), x.getAttribute("aria-pressed")]));
  ok(["imageLeft", "hero", "compact", "Replay"].every((n) => btns.some((b) => b[0] === n)), "hero: layout buttons imageLeft / hero / compact and Replay", JSON.stringify(btns));
  ok(btns.find((b) => b[0] === "imageLeft")?.[1] === "true", "hero: imageLeft is aria-pressed once picked", JSON.stringify(btns));
  ok(await exists(".hero-handle[role=slider]"), "hero: width handle is a slider at 1440");
  ok(/grid · 12 × 3 · \s*\d+ pt/.test(await text(".hero-readout")), "hero: readout reads 'grid · 12 × 3 · N pt'", await text(".hero-readout"));

  // layouts at 1440: wdth differs, compact removes the body
  const wd = () => page.$eval("#top h1.hero-title", (e) => Number((e.style.fontVariationSettings.match(/"wdth"\s*(\d+)/) || [])[1]));
  await clickBtn("#top .hero-pick", "hero");
  await sleep(900);
  const wHero = await wd();
  ok(await has("#top .hero-readout", "12 × 3") && (await st()).l === "hero", "hero: 'hero' layout selects (aria-pressed) and keeps 12 × 3", JSON.stringify(await st()));
  await clickBtn("#top .hero-pick", "imageLeft");
  await sleep(900);
  const wImg = await wd();
  ok(wHero !== wImg && wHero > 0 && wImg > 0, "hero: wdth differs between hero and imageLeft at 1440", `${wHero} vs ${wImg}`);
  await clickBtn("#top .hero-pick", "compact");
  await sleep(900);
  ok(!(await exists("#top .hero-ghost .hero-c-body")) && (await exists('#top .hero-live .hero-c-body[data-here="false"][inert]')), "hero: compact collapses the body cell (out of the grid, hidden and inert)");
  ok(await has("#top .hero-readout", "12 × 2"), "hero: compact reads 12 × 2 at 1440", await text(".hero-readout"));
  const cfill = await page.evaluate(() => { const h = document.querySelector("#top h1.hero-title"), c = h.closest(".cell"); return { spans: h.querySelectorAll("span").length, w: Math.round(h.querySelector("span").getBoundingClientRect().width), cell: Math.round(c.getBoundingClientRect().width) }; });
  ok(cfill.spans === 1 && cfill.w > cfill.cell * 0.85, "hero: compact sets the headline on one line across the canvas", JSON.stringify(cfill));
  await clickBtn("#top .hero-pick", "imageLeft");
  await sleep(700);

  // headline never overflows its cell
  const overflow = () => page.evaluate(() => {
    const h1 = document.querySelector("#top h1.hero-title");
    const cell = h1.closest(".cell");
    const hs = [...h1.querySelectorAll("span")].map((s) => s.getBoundingClientRect().right);
    return { h1: Math.round(h1.getBoundingClientRect().right), spans: Math.max(0, ...hs.map(Math.round)), cell: Math.round(cell.getBoundingClientRect().right), sw: h1.scrollWidth, cw: h1.clientWidth };
  });
  for (const [w, h] of [[1440, 900], [1280, 800], [834, 1100], [390, 844]]) {
    await page.setViewport({ width: w, height: h });
    await page.goto(BASE + "/", { waitUntil: "load" });
    await waitFor(async () => (await st()).d === "true", 6000, 100);
    await sleep(600);
    for (const l of ["imageLeft", "hero", "compact"]) {
      await clickBtn("#top .hero-pick", l);
      await sleep(900);
      const o = await overflow();
      ok(o.h1 <= o.cell + 1 && o.spans <= o.cell + 1, `hero: headline stays inside its cell at ${w} in ${l}`, JSON.stringify(o));
    }
    await clickBtn("#top .hero-pick", "imageLeft");
    await sleep(500);
  }

  // handle (>=1024) and range (<1024)
  await page.setViewport({ width: 1440, height: 900 });
  await page.goto(BASE + "/", { waitUntil: "load" });
  await waitFor(async () => (await st()).d === "true", 6000, 100);
  await sleep(700);
  const pt = async () => Number((/(\d+)\s*pt/.exec((await text(".hero-readout")).replace(/\u2007/g, "")) || [])[1] || 0);
  const w0 = await pt(), wd0 = await wd();
  await page.focus(".hero-handle");
  for (let i = 0; i < 8; i++) await page.keyboard.press("ArrowLeft");
  await sleep(900);
  const w1 = await pt(), wd1 = await wd();
  ok(w1 < w0, "hero: ArrowLeft on the handle narrows the canvas, readout number drops", `${w0} -> ${w1}`);
  ok(wd1 !== wd0 || wd1 >= 62, "hero: wdth changes with the canvas or stays >= 62", `${wd0} -> ${wd1}`);
  ok(wd1 >= 62, "hero: wdth never below 62 after narrowing", String(wd1));
  ok(Number(await page.$eval(".hero-handle", (e) => e.getAttribute("aria-valuenow"))) < 100, "hero: handle aria-valuenow drops");
  await page.setViewport({ width: 834, height: 1100 });
  await page.goto(BASE + "/", { waitUntil: "load" });
  await sleep(800);
  ok(await page.evaluate(() => { const r = document.querySelector(".hero-range input[type=range]"); return !!r && getComputedStyle(r.closest(".hero-range")).display !== "none" && r.getBoundingClientRect().width > 0; }), "hero: a range input is shown below 1024");

  // Send stacks with a counter
  await page.setViewport({ width: 1440, height: 900 });
  await page.goto(BASE + "/", { waitUntil: "load" });
  await waitFor(async () => (await st()).d === "true", 6000, 100);
  await sleep(500);
  ok(await waitFor(async () => (await bellCount()) === 1, 2000), "hero: fresh load, bell count 1 after the auto-send", await bellLabel());
  await clickBtn("#top", "Send");
  ok(await waitFor(async () => (await text("#top [role=status]")).includes("Sent · stacked with Herald · this page (2)"), 2000), "hero: Send stacks with a counter (2)", await text("#top [role=status]"));
  ok(await waitFor(async () => (await bellCount()) === 2, 1500), "hero: bell count equals pending after Send (2)", await bellLabel());
  ok(await waitFor(() => exists('#herald-overlay [aria-label="2 banners in this stack"]'), 2000), "hero: Send makes a stack with counter 2");
  ok(!(await exists('[aria-label="Herald banners"]')) && !(await has("#top", "Run it")), "hero: the old dock and 'Run it' are gone");
  await page.mouse.move(700, 500);
  await waitFor(async () => !(await exists('#herald-overlay .hb-arrival[data-open="true"]')), 6000, 200);
  ok(errors.length === pageErr0, "hero: no console errors during the hero tests", errors.slice(pageErr0).join(" | "));
});

// ============ 2 why ============
await section("why", async () => {
  await scrollToSel("#why");
  const w = await page.evaluate(() => {
    const mac = document.querySelector('#why [data-testid="mac-alert"]');
    const img = document.querySelector('#why [data-testid="herald-banner"]');
    const old = document.querySelector('#why img[src*="banner-plain"]');
    const frames = [...document.querySelectorAll("#why .sbs-frame")].map((f) => f.getBoundingClientRect().height);
    return { mac: !!mac, img: !!img, old: !!old, frames, txt: document.querySelector("#why").innerText };
  });
  ok(w.mac, "why: a faithful macOS Notification Center alert mock is present");
  ok(w.img && !w.old, "why: the Herald side is a live banner (data-testid=herald-banner), not the banner-plain image");
  await clickBtn("#why", "Open site");
  ok(await waitFor(() => has("#why", "Opened the site"), 1500), "why: 'Open site' shows an outcome line", await text("#why .sbs-out[role=status]"));
  ok(w.frames.length === 2 && Math.abs(w.frames[0] - w.frames[1]) < 1, "why: both frames render at the same height", w.frames.join("/"));
  ok(!/\b5 s\b|five seconds|Gone\./.test(w.txt), "why: no five-second premise anywhere in the section");
  ok(/Notification Center/.test(w.txt) && /Herald/.test(w.txt) && /History|history/.test(w.txt), "why: ledger argues layout, actions, history, grouping, voice, focus, agents");
  const labels = await page.$$eval("#why .ledger-label", (l) => l.map((e) => e.innerText.trim().toLowerCase()));
  ok(["persistence", "history", "focus", "layout", "actions", "grouping", "voice", "agents"].every((x) => labels.includes(x)), "why: ledger rows include persistence, history and focus", labels.join("|"));
  ok(!(await exists("#herald-overlay .hb-stack[data-open='true']")), "why: nothing pops over the page just from reading the section");
});

// ============ 3 overlay and bell ============
await section("overlay", async () => {
  // let the auto-collapse (6 s after the send) finish
  await waitFor(() => page.$eval(".hb-bell", (e) => e.getAttribute("aria-expanded") === "false"), 9000, 200);
  const attr = (n) => page.$eval(".hb-bell", (e, n) => e.getAttribute(n), n);
  ok((await attr("aria-controls")) === "herald-overlay", "bell: aria-controls is herald-overlay");
  ok((await attr("aria-expanded")) === "false", "bell: aria-expanded false when collapsed");
  const click = () => page.$eval(".hb-bell", (e) => e.click());
  await click();
  ok(await waitFor(async () => (await attr("aria-expanded")) === "true", 1500), "bell: click expands the overlay (aria-expanded true)");
  ok(await page.$eval("#herald-overlay .hb-stack", (e) => e.dataset.open === "true").catch(() => false), "bell: overlay stack is open");
  await click();
  ok(await waitFor(async () => (await attr("aria-expanded")) === "false", 1500), "bell: second click collapses it");
  await click();
  await waitFor(async () => (await attr("aria-expanded")) === "true", 1500);
  await page.keyboard.press("Escape");
  ok(await waitFor(async () => (await attr("aria-expanded")) === "false", 1500), "overlay: Escape closes it");
  // hover opens (real mouse)
  const box = await (await page.$(".hb-bell")).boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  ok(await waitFor(async () => (await attr("aria-expanded")) === "true", 1500), "bell: hovering it with a mouse opens the overlay");
  ok(await has("#herald-overlay", "Dismiss all"), "overlay: header has 'Dismiss all'");
  await jsClick("#herald-overlay", "Dismiss all");
  await page.mouse.move(700, 500);
  ok(await waitFor(async () => (await bellLabel()) === "Show Herald banners", 2500), "overlay: after Dismiss all the bell count is 0", await bellLabel());
});

// ============ 4 flow ============
await section("flow", async () => {
  const FLOW = "#flow";
  const out = () => text('#flow [aria-label="Send test outcome"]');
  const summary = () => page.$eval('#flow [role="status"]', (e) => e.innerText).catch(() => "");
  await clickBtn(FLOW, "Send test");
  ok(await waitFor(async () => (await out()).includes("Sent through the template"), 1500), "flow: Send test outcome says 'Sent through the template'", await out());
  await clickBtn(FLOW, "Send body empty");
  ok(await waitFor(async () => (await summary()).includes("Row 2 collapsed"), 1500), "flow: emptying body collapses row 2", await summary());
  const bannerH = () => page.$eval("#flow article:nth-of-type(3) .mb", (e) => e.getBoundingClientRect().height);
  await sleep(800);
  const h1 = await bannerH();
  await clickBtn(FLOW, "keep space");
  await sleep(700);
  const h2 = await bannerH();
  ok(h2 > h1 + 8, `flow: keep space makes the banner taller (${Math.round(h1)} -> ${Math.round(h2)} px)`);
  await clickBtn(FLOW, "collapse");
  await sleep(600);
  await clickBtn(FLOW, "Send body empty"); // body filled again
  await clickBtn(FLOW, "Send log empty");
  ok((await summary()).includes("each row still has a filled cell"), "flow: one empty cell does not collapse a row", await summary());
  await clickBtn(FLOW, "Send action empty");
  await clickBtn(FLOW, "Send body empty");
  ok(await waitFor(async () => (await summary()).includes("Row 2 and 3 collapsed"), 1500), "flow: both buttons empty collapses row 3 too", await summary());
  await clickBtn(FLOW, "Send test");
  ok(await waitFor(async () => (await out()).includes("Sent through the template"), 1500), "flow: Send test after changes still reports the template", await out());
  ok(!(await exists("#flow [role=tab]")) && !(await has(FLOW, "1 · Manifest")), "flow: no step tabs ('1 · Manifest' is gone)");
  await page.mouse.move(700, 500);
});

// ============ 5 designer ============
await section("designer", async () => {
  await scrollToSel("#designer .dz-frame");
  const n = await page.$$eval("#designer button.dz-hot", (b) => b.length);
  ok(n === 6, `designer: six hotspot buttons (${n})`);
  const labels = await page.$$eval("#designer button.dz-hot", (b) => b.map((x) => x.getAttribute("aria-label")));
  ok(labels.every((l, i) => l.startsWith(`${i + 1}. `)), "designer: hotspots are numbered 1 to 6 in aria-label", labels.map((l) => l.slice(0, 12)).join("|"));
  const hot = await page.$("#designer button.dz-hot[aria-label^='3. ']");
  if (!hot) return ok(false, "designer: grid canvas hotspot present");
  await hot.hover();
  ok(await waitFor(async () => (await text("#designer .dz-card")).includes("Any rows × columns"), 1500), "designer: hovering the grid canvas shows 'Any rows × columns' card", await text("#designer .dz-card"));
  ok(await exists("#designer .dz-lit"), "designer: dim layer / highlight outline (.dz-lit) is present");
  ok(await page.$eval("#designer .dz-legend li:nth-child(3)", (e) => e.dataset.on === "true"), "designer: legend item 3 gets the active state");
  ok(await page.$eval("#designer button.dz-hot[aria-label^='3. ']", (e) => e.getAttribute("aria-expanded") === "true"), "designer: hotspot aria-expanded true while active");
  await page.mouse.move(2, 2);
  ok(await waitFor(async () => !(await exists("#designer .dz-card")), 1500), "designer: leaving the hotspot hides the card");
  const src = () => page.$eval("#designer .dz-clip img", (e) => e.getAttribute("src"));
  const s0 = await src();
  await clickBtn("#designer", "Light");
  await sleep(300);
  const s1 = await src();
  ok(s0 !== s1 && /light/.test(s1), "designer: Light toggle switches the image src", `${s0} -> ${s1}`);
  await clickBtn("#designer", "Dark");
  await sleep(300);
  ok((await src()) === s0 && /dark/.test(s0), "designer: Dark toggle switches it back", await src());
  await page.mouse.move(2, 2);
});

// ============ 6 actions ============
await section("actions", async () => {
  await scrollToSel("#actions .flip-drum");
  ok(await exists("#actions .flip-drum"), "actions: flipper .flip-drum exists");
  const word = () => page.$eval("#actions .flip-drum .sr-only", (e) => e.textContent.trim());
  const w0 = await word();
  ok(w0.length > 0, "actions: flipper has a phrase", w0);
  const changed = await waitFor(async () => (await word()) !== w0, 9000, 200);
  ok(changed, "actions: the flipper phrase changes by itself", `${w0} -> ${await word()}`);
  await clickBtn("#actions", "Deploy");
  ok(await waitText("#actions", "Deploy 4f2a to production?", 1500) && (await has("#actions", "Yes, deploy")) && (await has("#actions", "Cancel")), "actions: demo banner Deploy shows the confirmation strip");
});

// ============ 7 living ============
await section("living", async () => {
  await scrollToSel("#living");
  await clickBtn("#living", "+1 from the same sender");
  ok(await waitFor(() => exists('#living [aria-label="4 banners in this stack"]'), 1500), "living: +1 from the same sender, counter 4");
  const badge = '#living button[aria-label="4 banners in this stack"]';
  ok(await exists(badge), "living: the red count badge is a button");
  await page.$eval(badge, (b) => b.click());
  ok(await waitFor(() => page.$eval(badge, (b) => b.getAttribute("aria-expanded") === "true"), 1500), "living: clicking the badge fans the stack out (aria-expanded true)");
  ok(await page.$eval(badge, (b) => !!document.getElementById(b.getAttribute("aria-controls") || "")), "living: badge aria-controls points at the fanned-out list");
  await jsClick("#living", "Collapse stack");
  ok(await waitFor(() => page.$eval(badge, (b) => b.getAttribute("aria-expanded") === "false"), 1500), "living: the chevron button collapses it again");
  const sentence = () => page.evaluate(() => {
    const el = [...document.querySelectorAll("#living [role=status]")].find((e) => /muted/.test(e.innerText) && /–/.test(e.innerText));
    return el ? el.innerText : "";
  });
  const outcome = () => text('#living [aria-label="Quiet hours outcome"]');
  ok((await sentence()) === "voice and sound muted 22:00–07:00", "living: default sentence reads 'voice and sound muted 22:00–07:00'", await sentence());
  await clickBtn("#living", "Pretend it is 23:30");
  ok(await page.$eval("#living button[aria-pressed]", () => true) && (await page.evaluate(() => [...document.querySelectorAll("#living button")].find((b) => b.innerText.includes("Pretend")).getAttribute("aria-pressed"))) === "true", "living: Pretend it is 23:30 is aria-pressed true");
  await jsClick("#living", "hold banners until morning");
  ok((await sentence()).includes("banners held until morning"), "living: hold checkbox adds 'banners held until morning'", await sentence());
  await clickBtn("#living", "Send one now");
  ok(await waitFor(async () => (await outcome()).includes("Held until 07:00"), 1500), "living: held in quiet hours says 'Held until 07:00'", await outcome());
  await jsClick("#living", "hold banners until morning");
  await clickBtn("#living", "Send one now");
  ok(await waitFor(async () => (await outcome()).includes("Shown, voice and sound muted"), 1500), "living: hold off says 'Shown, voice and sound muted ...'", await outcome());
  // sliders
  await page.focus('#living input[aria-label="Quiet hours start"]');
  await page.keyboard.press("ArrowLeft"); await page.keyboard.press("ArrowLeft");
  await page.focus('#living input[aria-label="Quiet hours end"]');
  await page.keyboard.press("ArrowRight");
  ok(await waitFor(async () => (await sentence()).includes("21:00–07:30"), 1500), "living: quiet-hours sliders update the sentence to 21:00–07:30", await sentence());
  await jsClick("#living", "no voice");
  ok(await waitFor(async () => (await sentence()).startsWith("sound muted 21:00"), 1500), "living: 'no voice' checkbox changes the sentence", await sentence());
  await jsClick("#living", "no voice");
  await clickBtn("#living", "Pretend it is 23:30"); // back to the real clock
  // voice: audio is never triggered by tests; only assert the explicit Play control exists and is unpressed
  const voice = await page.evaluate(() => {
    const b = [...document.querySelectorAll("#living button[aria-pressed]")].find((x) => /^(Play|Stop)/.test(x.innerText.trim()));
    return b ? { t: b.innerText.trim(), pressed: b.getAttribute("aria-pressed") } : null;
  });
  ok(!!voice && voice.pressed === "false" && /^Play/.test(voice.t), "living: voice has an explicit Play button, aria-pressed false (not clicked)", JSON.stringify(voice));
});

// ============ 8 cloud ============
await section("cloud", async () => {
  await scrollToSel("#cloud");
  const input = '#cloud input[aria-label="Reply to the agent"]';
  await page.type(input, "Ship it");
  await clickBtn("#cloud", "Send");
  ok(await waitText("#cloud", "delivered to the agent", 1500), "cloud: typed reply Send shows 'delivered to the agent'");
  await clickBtn("#cloud", "Record");
  ok(await waitText("#cloud", "Recording", 1500), "cloud: Record shows 'Recording'");
  ok(await waitText("#cloud", "Transcript:", 5000), "cloud: after about 3 s the 'Transcript:' line appears");
  const val = await page.$eval(input, (e) => e.value).catch(() => "");
  ok(val.length > 0, "cloud: transcript fills the reply input", val);
});

// ============ 9 agents ============
await section("agents", async () => {
  await scrollToSel("#agents ul.mono");
  const hrefs = await page.$$eval("#agents a", (as) => as.map((a) => a.getAttribute("href")));
  ok(hrefs.filter((h) => h && h.startsWith("/docs/more/mcp-guide") && true).length === 3 && (await page.$$eval("#agents a", (as) => as.filter((a) => a.innerText.trim() === "How to install").length)) === 3, "agents: three 'How to install' links to /docs/more/mcp-guide", JSON.stringify(hrefs));
  await clickBtn("#agents", "Copy config");
  await sleep(300);
  const clip = await page.evaluate(() => navigator.clipboard.readText()).catch((e) => "ERR " + e.message);
  ok(clip.includes("herald-mcp"), "agents: Copy config copies JSON containing herald-mcp", clip);
  ok(await has("#agents", "Copied"), "agents: Copy config shows Copied state");
  await clickBtn("#agents", "Try render_preview");
  ok(await waitFor(() => page.$eval('#agents img[alt*="render_preview"]', (e) => (e.currentSrc || e.src).includes("/shots/banner-plain.png")), 2000), "agents: Try render_preview shows /shots/banner-plain.png");
  await clickBtn("#agents", "Try list_history / list_stacks");
  ok(await waitFor(async () => (await text('#agents [aria-label="Herald state readout"]')).includes("onScreen"), 1500), "agents: list_history / list_stacks shows a readout containing onScreen", await text('#agents [aria-label="Herald state readout"]'));
  await clickBtn("#agents", "Try send_test / speak");
  ok(await waitFor(async () => (await overlayText()).includes("Build finished"), 2500), "agents: send_test / speak adds a Claude Code banner (overlay shows 'Build finished')", await overlayText());
  ok((await overlayText()).toLowerCase().includes("claude code"), "agents: banner is labelled Claude Code");
  await page.mouse.move(700, 500);
});

// ============ 10 integrate ============
await section("integrate", async () => {
  await scrollToSel("#integrate");
  await clickBtn("#integrate", "Python");
  ok(await waitFor(() => page.$eval("#panel-python", (e) => !e.hidden && e.innerText.includes("from herald import Herald")), 1500), "integrate: Python tab shows 'from herald import Herald'");
  await clickBtn("#integrate", "Copy code");
  await sleep(300);
  const clip = await page.evaluate(() => navigator.clipboard.readText()).catch(() => "");
  ok(clip.includes("from herald import Herald"), "integrate: Copy code copies the shown tab", clip.slice(0, 60));
  await clickBtn("#integrate", "Run snippet");
  ok(await waitFor(async () => (await text('#integrate [aria-label="Run outcome"]')).includes("Sent"), 1500), "integrate: Run snippet outcome says 'Sent'", await text('#integrate [aria-label="Run outcome"]'));
  ok(await waitFor(() => exists('#herald-overlay .hb-arrival[data-open="true"]'), 1500), "arrival: a send from a lower section shows one arrival card under the bell");
  ok(!(await exists('#herald-overlay .hb-stack[data-open="true"]')) && !(await has("#herald-overlay", "Dismiss all")), "arrival: the full stack (Dismiss all) stays closed");
  ok((await page.$$eval('#herald-overlay .hb-arrival [aria-label$=" banner"]', (n) => n.length)) === 1, "arrival: exactly one banner card in the arrival");
  ok(await waitFor(async () => !(await exists('#herald-overlay .hb-arrival[data-open="true"]')), 6000), "arrival: it goes away by itself after about 4 s");
  const al = await page.evaluate(() => { const a = document.querySelector(".hb-overlay-in"), sh = document.querySelector("main .shell"); return a && sh ? Math.abs(a.getBoundingClientRect().right - sh.getBoundingClientRect().right) : 999; });
  ok(al < 1, "arrival: overlay column is aligned to the page shell, no 100vw maths", String(al));
});

// ============ 11 easter egg ============
await section("egg", async () => {
  await page.evaluate(() => document.activeElement?.blur());
  await page.mouse.move(700, 500);
  await page.keyboard.down("Meta");
  await page.keyboard.down("Shift");
  await page.keyboard.press("h");
  await page.keyboard.up("Shift");
  await page.keyboard.up("Meta");
  ok(await waitFor(async () => (await overlayText()).includes("You found it."), 2000), "egg: Cmd+Shift+H shows 'You found it.' in the page's Herald", await overlayText());
  await jsClick('#herald-overlay [aria-label="Herald banner"]', "Snooze");
  ok(await waitFor(async () => !(await overlayText()).includes("You found it.") && (await overlayText()).includes("snoozed"), 2000), "egg: Snooze hides the banner and shows the snoozed line", await overlayText());
});

// ============ 11b round 2: layout, fold, nowrap, grid banner, docs ============
const PH = ["IVG Design","Claude Code","Claude Desktop","Codex CLI","Apple Silicon","SF Symbols","Notification Center","Apple Shortcut","Apple Shortcuts","macOS 13.1+","macOS 13.1","Developer ID","Kokoro voice","WebWatcher"];
const RX = [["\\d+\\.\\d+\\.\\d+(?: \\(Build \\d+\\))?","g"],["Build \\d+","g"],["⌘[⇧⌥⌃]*[A-Z0-9]","g"],["macOS \\d+(?:\\.\\d+)?\\+?","g"]];
function nowrapCheck(PH, RX) {
  const rxs = RX.map(([s, f]) => new RegExp(s, f)), out = [];
  const wk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n;
  while ((n = wk.nextNode())) {
    const t = n.textContent, pe = n.parentElement;
    if (!pe || pe.closest("script,style,noscript,pre,code") || !pe.getClientRects().length) continue;
    const ms = [];
    for (const ph of PH) { let i = -1; while ((i = t.indexOf(ph, i + 1)) >= 0) ms.push([i, ph.length]); }
    for (const rx of rxs) { rx.lastIndex = 0; let m; while ((m = rx.exec(t))) ms.push([m.index, m[0].length]); }
    for (const [i, l] of ms) {
      const r = document.createRange(); r.setStart(n, i); r.setEnd(n, i + l);
      const tops = new Set([...r.getClientRects()].filter((x) => x.width > 0).map((x) => Math.round(x.top)));
      if (tops.size > 1) out.push(t.slice(i, i + l));
    }
  }
  return out;
}
await section("round2", async () => {
  await load("/", 1440, 900);
  const h3n = await page.$$eval("#living h3", (h) => h.length);
  ok(h3n === 3, "living: three h3 headings", String(h3n));
  await scrollToSel("#agents ul.mono");
  await sleep(300);
  const rows = await page.$$eval("#agents ul.mono li", (li) => li.map((e) => ({ t: e.innerText.trim(), o: getComputedStyle(e).opacity })));
  ok(rows.every((r) => r.t.length > 0 || Number(r.o) === 0), "agents: untyped rows are invisible, never a bare check mark", JSON.stringify(rows).slice(0, 120));
  ok(await waitFor(async () => (await page.$$eval("#agents ul.mono li", (li) => li.every((e) => e.innerText.trim().length > 0 && getComputedStyle(e).opacity === "1"))), 9000), "agents: every tool row is typed within 9 s");
  // Rive grid -> banner piece
  await scrollToSel('[data-testid="grid-banner"]');
  ok(await exists('[data-testid="grid-banner"]'), "designer: the Rive grid-to-banner piece is on the page");
  ok(await waitFor(() => page.$eval('[data-testid="grid-banner"]', (e) => e.dataset.loaded === "true"), 8000), "designer: grid-banner.riv loads (Rive runtime, self-hosted wasm)");
  await page.$eval('[data-testid="grid-banner"]', (e) => e.click());
  ok(await waitFor(() => page.$eval('[data-testid="grid-banner"]', (e) => e.dataset.plays === "1"), 1500), "designer: clicking the piece replays the assembly");
  // phone: no dock; the headline sits inside the canvas and nothing overflows
  await load("/", 390, 844);
  const fold = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, h1t: document.querySelector("#top h1").getBoundingClientRect().top, dock: !!document.querySelector("#top .hd") }));
  ok(!fold.dock && fold.h1t < 844, "mobile 390: headline is on the first screen, no dock", JSON.stringify(fold));
  ok(fold.sw <= 390, `mobile 390: no horizontal overflow after the hero (scrollWidth ${fold.sw})`);
  // v3 global rules
  for (const [w, h] of [[1440, 900], [1280, 800], [834, 1100], [390, 844]]) {
    await load("/", w, h);
    await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 700) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 40)); } window.scrollTo(0, 0); });
    const g = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
    ok(g.sw <= g.cw, `v3: no horizontal overflow at ${w} on /`, JSON.stringify(g));
  }
  await load("/", 1440, 900);
  ok((await page.$$eval(".eyebrow", (e) => e.length)) === 0, "v3: no .eyebrow elements on /");
  const ff = await page.evaluate(() => getComputedStyle(document.body).fontFamily);
  ok(/^["']?Georama/i.test(ff), "v3: body font-family starts with Georama (not WebWatcher's Archivo)", ff);
  ok((await page.$$eval(".section-dark, .section-paper", (e) => e.length)) === 0, "v3: no element with class section-dark / section-paper");
  // proper nouns never wrap
  for (const [w, h] of [[1440, 900], [834, 1100], [390, 844]]) {
    for (const path of ["/", "/changelog", "/docs/getting-started/install"]) {
      await load(path, w, h);
      const bad = await page.evaluate(nowrapCheck, PH, RX);
      ok(bad.length === 0, `nowrap: no proper noun / version / key combo breaks across lines at ${w} on ${path}`, bad.join(" | "));
    }
  }
  // docs: solo grid without a rail, tables fit the article (no horizontal scroll anywhere; see scripts/test-docs-hscroll.mjs)
  await load("/docs/getting-started/install", 1440, 900);
  ok(await page.$eval(".docs-grid", (g) => g.classList.contains("docs-grid--solo") && !document.querySelector(".docs-rail")), "docs: a page without headings drops the empty rail column");
  await load("/docs/reference/http-api", 1440, 900);
  const tbl = await page.evaluate(() => { const a = document.querySelector("#docs-main article, #docs-main").getBoundingClientRect(); return [...document.querySelectorAll(".docs-table")].map((t) => Math.round(t.getBoundingClientRect().right - a.right)); });
  ok(tbl.length > 0 && tbl.every((d) => d <= 1), "docs: every table fits inside the article (no scroller, no overflow)", tbl.join("/"));
  await load("/docs/reference/http-api", 390, 844);
  ok(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), "docs 390: the API reference has no horizontal page overflow");
  ok(await page.evaluate(() => !!document.querySelector("html") && getComputedStyle(document.documentElement).scrollbarGutter.includes("stable")), "layout: html has scrollbar-gutter: stable (no shift when a scrollbar appears)");
});

// ============ 12 docs ============
await section("docs", async () => {
  await load("/docs/more/mcp-guide", 1800, 900);
  const d = await page.evaluate(() => {
    const brand = document.querySelector(".docs-brand");
    const icon = document.querySelector(".docs-brand-icon").getBoundingClientRect();
    const head = document.querySelector(".docs-header").getBoundingClientRect();
    const side = document.querySelector("#docs-sidebar").getBoundingClientRect();
    const main = document.querySelector("#docs-main").getBoundingClientRect();
    const rail = document.querySelector(".docs-rail");
    const railTxt = rail ? rail.innerText : "";
    return { href: brand.getAttribute("href"), ih: icon.height, hh: head.height, sideLeft: side.left, mainRight: main.right, vw: innerWidth, railTxt, pager: document.querySelector(".docs-pager")?.innerText ?? "" };
  });
  ok(d.href === "/", "docs: .docs-brand links to the home route", d.href);
  ok(Math.abs(d.ih - (d.hh - 5)) <= 1.5, `docs: .docs-brand-icon height = header height - 5 (${d.ih} vs ${d.hh})`);
  ok(d.sideLeft > 100, `docs: layout centred at 1800 (sidebar left ${Math.round(d.sideLeft)})`);
  ok(Math.abs(d.sideLeft - (d.vw - d.mainRight)) < 260, `docs: left and right margins are balanced (${Math.round(d.sideLeft)} vs ${Math.round(d.vw - d.mainRight)})`);
  ok(d.railTxt.length > 0 && !ENT.test(d.railTxt), "docs: no HTML entities in the on-this-page rail", d.railTxt.slice(0, 80));
  ok(d.pager.length > 0 && !ENT.test(d.pager), "docs: no HTML entities in the pager", d.pager);
  const side = await page.$eval("#docs-sidebar", (e) => e.innerText);
  ok(!ENT.test(side), "docs: no HTML entities in the sidebar", side.match(ENT)?.[0]);
  await page.keyboard.press("/");
  await sleep(400);
  await page.keyboard.type("settings");
  await sleep(500);
  const hits = await page.$$eval(".docs-hit", (h) => h.map((e) => e.innerText).join("|"));
  ok(hits.length > 0, "docs: '/' opens search and 'settings' finds results", hits.slice(0, 100));
  ok(hits.length > 0 && !ENT.test(hits), "docs: search results contain no entities", hits.slice(0, 100));
  await page.keyboard.press("Escape");
});

// ============ 13 landing header 1440 and 390 ============
await section("header", async () => {
  await load("/", 1440, 900);
  const l = await page.evaluate(() => {
    const h = document.querySelector("header").getBoundingClientRect();
    const i = document.querySelector(".site-brand-icon").getBoundingClientRect();
    return { hh: h.height, ih: i.height, href: document.querySelector(".site-brand").getAttribute("href") };
  });
  ok(l.href === "/", ".site-brand links home", l.href);
  ok(Math.abs(l.ih - 54) <= 1.5, `landing: .site-brand-icon height is 54 (${l.ih})`);
  ok(l.hh >= 64 && l.hh <= 65, `landing: header is a 64 px bar + 1 px border (${l.hh})`);

  await load("/", 390, 800);
  const m = await page.evaluate(() => {
    const vis = (el) => !!el && getComputedStyle(el).display !== "none" && el.getBoundingClientRect().width > 0;
    const hdr = document.querySelector("header");
    const q = (s) => [...hdr.querySelectorAll(s)];
    return {
      sw: document.documentElement.scrollWidth,
      bell: vis(hdr.querySelector(".hb-bell")),
      burger: vis(hdr.querySelector('button[aria-label="Open menu"]')),
      links: q("a").filter((a) => a.closest("nav") === null && vis(a) && !a.classList.contains("site-brand")).map((a) => a.innerText.trim()),
      nav: vis(hdr.querySelector('nav[aria-label="Primary"]')),
    };
  });
  ok(m.sw <= 390, `mobile 390: no horizontal overflow (scrollWidth ${m.sw})`);
  ok(m.bell && m.burger, "mobile 390: header shows bell and hamburger", JSON.stringify(m));
  ok(m.links.length === 0 && !m.nav, "mobile 390: header shows nothing else (no GitHub, Download, nav)", JSON.stringify(m.links));
});

// ============ large monitors: only the hero scales ============
await section("large", async () => {
  const base = {};
  for (const [w, h] of [[1440, 900], [1920, 1080], [2560, 1440], [2681, 1589], [3440, 1440]]) {
    await page.setViewport({ width: w, height: h });
    const probe = await page.evaluateOnNewDocument(() => { window.__cls = 0; new PerformanceObserver((l) => { for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value; }).observe({ type: "layout-shift", buffered: true }); });
    await page.goto(BASE + "/", { waitUntil: "load" });
    await page.removeScriptToEvaluateOnNewDocument(probe.identifier);
    await page.mouse.move(2, 2);
    await waitFor(() => page.$eval("#top", (e) => e.dataset.ready === "true"), 5000, 50);
    await sleep(900);
    const m = () => page.evaluate(() => {
      const c = document.querySelector(".hero-canvas").getBoundingClientRect();
      const cells = [...document.querySelectorAll('.hero-live .hero-cell[data-here="true"]')].map((e) => e.getBoundingClientRect());
      const h1 = document.querySelector("#top h1"), cell = h1.closest(".cell").getBoundingClientRect();
      const px = (sel, prop) => parseFloat(getComputedStyle(document.querySelector(sel))[prop]);
      const hd = document.querySelector("header > .shell"), hs = getComputedStyle(hd);
      return {
        wShare: c.width / innerWidth, bottom: Math.max(...cells.map((r) => r.bottom)) / innerHeight, heroH: document.querySelector("#top").getBoundingClientRect().height + 64 - innerHeight,
        over: document.documentElement.scrollWidth - document.documentElement.clientWidth, title: px("#top h1", "fontSize"), lede: px("#top .hero-live .hero-lede", "fontSize"), btn: px("#top .hero-live .btn-primary", "height"), slot: px("#top .hero-live .slot", "fontSize"),
        inCell: Math.max(...[...h1.querySelectorAll("span")].map((s) => s.getBoundingClientRect().right)) <= cell.right + 1,
        pt: Number((/(\d+)\s*pt/.exec(document.querySelector(".hero-readout").innerText.replace(/\u2007/g, "")) || [])[1]), cw: Math.round(c.width),
        col: Number(document.querySelector(".hero-ruler-track").textContent), gap: parseFloat(getComputedStyle(document.querySelector(".hero-ghost")).columnGap),
        hdr: Math.round(hd.getBoundingClientRect().left + parseFloat(hs.paddingLeft)) - Math.round(c.left),
        why: px("#why .display-l", "fontSize"), dl: px("#download .display-l", "fontSize"), nav: px("header nav a", "fontSize"), body: px("body", "fontSize"),
      };
    });
    const r = await m();
    if (w === 1440) Object.assign(base, r);
    const tag = `large ${w}×${h}`;
    ok(r.over <= 0, `${tag}: no horizontal overflow`, String(r.over));
    ok(r.pt === r.cw && Math.abs(r.col - (r.cw - 11 * r.gap) / 12) <= 1, `${tag}: the readout and the ruler state the real canvas (${r.pt} pt, ${r.col} per column)`, JSON.stringify({ pt: r.pt, cw: r.cw, col: r.col }));
    ok(r.inCell, `${tag}: the headline stays inside its cell`);
    ok(Math.abs(r.heroH) <= 1, `${tag}: the hero is exactly the first screen`, String(r.heroH));
    if (w > 1440) {
      ok(r.wShare >= 0.78 && r.wShare <= 0.86, `${tag}: the canvas takes about 80 % of the window (${(r.wShare * 100).toFixed(1)} %)`);
      ok(r.bottom >= 0.9 && r.bottom <= 1, `${tag}: the template reaches the bottom of the first screen (${(r.bottom * 100).toFixed(1)} %)`);
      ok(r.title > base.title * 1.25, `${tag}: the headline grows (${base.title} → ${r.title.toFixed(0)} px)`);
      ok(r.lede <= base.lede * 1.31 && r.btn <= base.btn * 1.31 && r.slot <= base.slot * 1.31 && r.lede >= base.lede, `${tag}: lede, buttons and labels grow by at most 1.3`, JSON.stringify({ lede: r.lede, btn: r.btn, slot: r.slot }));
      ok(r.why <= 66 && r.dl <= 66 && r.nav === base.nav && r.body === base.body && (await page.evaluate(() => [...document.querySelectorAll("main > section:not(.hero), body > footer")].every((e) => (getComputedStyle(e).zoom || "1") === "1"))), `${tag}: nothing outside the hero is scaled`, JSON.stringify({ why: r.why, dl: r.dl, nav: r.nav, body: r.body }));
      ok(Math.abs(r.hdr) <= 1, `${tag}: the header's content edge is the canvas's edge`, String(r.hdr));
    } else {
      ok(Math.abs(r.title - 124) < 0.5 && r.lede === 20 && r.btn === 44 && r.slot === 11 && r.cw === 1178, `${tag}: unchanged at 1440 (124 px headline, 1178 pt canvas, 44 px buttons)`, JSON.stringify({ t: r.title, l: r.lede, b: r.btn, s: r.slot, cw: r.cw }));
    }
    // the tour, then each layout by hand
    ok(await waitFor(() => page.$eval("#top", (e) => e.dataset.layout === "compact"), 7000, 50), `${tag}: the tour still runs (reaches compact)`);
    await waitFor(() => page.$eval("#top", (e) => e.dataset.layout === "hero"), 4000, 50);
    await sleep(3600);
    const cls = await page.evaluate(() => +window.__cls.toFixed(4));
    ok(cls < 0.01, `${tag}: load, tour and glide shift nothing (CLS ${cls})`);
    for (const l of ["imageLeft", "compact"]) {
      await jsClick("#top .hero-pick", l);
      await sleep(800);
      const q = await m();
      ok(q.inCell && q.over <= 0 && q.bottom <= 1.001 && q.bottom >= (l === "compact" ? 0.62 : 0.88), `${tag}: ${l} fits its cells and stays filled (bottom at ${(q.bottom * 100).toFixed(0)} %)`, JSON.stringify({ inCell: q.inCell, over: q.over }));
    }
  }
  ok(await page.$eval("#top .hero-live .hero-icon-img", (e) => /herald-icon/.test(e.currentSrc) && !/\.svg/.test(e.currentSrc) && e.alt === "Herald app icon" && getComputedStyle(e.parentElement).backgroundColor === "rgba(0, 0, 0, 0)"), "hero: the icon cell shows the real app icon (PNG/WebP), with no tile behind it");
  ok(await page.$eval("#top .hero-live .hero-icon-img", (e) => e.naturalWidth >= e.getBoundingClientRect().width), "hero: the icon source is at least as large as it is drawn at 3440");
});

// ============ demos never move the page ============
await section("stable", async () => {
  const IDS = ["why", "flow", "actions", "living", "cloud", "agents", "integrate"];
  for (const [w, h] of [[1440, 900], [390, 844]]) {
    await load("/", w, h);
    await page.mouse.move(2, 2);
    await page.keyboard.press("Escape");
    await sleep(11500); // let the hero tour end so only the demo under test changes anything
    for (const id of IDS) {
      await scrollToSel("#" + id, "start");
      const geo = () => page.evaluate((id) => { const s = document.getElementById(id); const n = s.nextElementSibling; return { h: Math.round(s.getBoundingClientRect().height), next: Math.round(n.getBoundingClientRect().top + scrollY), doc: document.documentElement.scrollHeight }; }, id);
      const g0 = await geo();
      let worst = 0, worstAt = "", clicks = 0;
      const check = async (label) => { const g = await geo(); const d = Math.max(Math.abs(g.h - g0.h), Math.abs(g.next - g0.next), Math.abs(g.doc - g0.doc)); if (d > worst) { worst = d; worstAt = label; } };
      if (id === "cloud") { const inp = await page.$("#cloud input"); if (inp) { await inp.type("Ship it, and tell me when it is live so I can check the page myself"); await check("typed reply"); } }
      for (let pass = 0; pass < 3; pass++) {
        const n = await page.$$eval(`#${id} button:not([disabled])`, (b) => b.length);
        for (let i = 0; i < n; i++) {
          const label = await page.evaluate((id, i) => { const b = [...document.querySelectorAll(`#${id} button:not([disabled])`)][i]; if (!b) return null; b.scrollIntoView({ block: "center", behavior: "instant" }); b.click(); return (b.getAttribute("aria-label") || b.innerText || "").trim().slice(0, 30); }, id, i);
          if (label === null) break;
          clicks++;
          await sleep(120); await check(label + " (during)");
          await sleep(650); await check(label);
        }
      }
      await sleep(1500); await check("settled");
      ok(worst <= 1, `stable ${w}: no click in #${id} changes its height, the next section's top or the document height (${clicks} clicks)`, `${worst} px at "${worstAt}"`);
      await page.keyboard.press("Escape");
    }
    // focus rings: no clipping ancestor cuts the 5 px a ring needs around a banner button
    const clipped = await page.evaluate(() => {
      const bad = [];
      for (const b of document.querySelectorAll("main .mb button, main .mb a, main .mb input")) {
        const r = b.getBoundingClientRect();
        if (!r.width || getComputedStyle(b).visibility === "hidden") continue;
        for (let p = b.parentElement; p && p.tagName !== "SECTION"; p = p.parentElement) {
          const cs = getComputedStyle(p);
          if (!/(hidden|clip|auto|scroll)/.test(cs.overflowY + cs.overflowX)) continue;
          const pr = p.getBoundingClientRect();
          if (r.bottom + 5 > pr.bottom + 0.5 || r.top - 5 < pr.top - 0.5 || r.left - 5 < pr.left - 0.5 || r.right + 5 > pr.right + 0.5) bad.push(`${(b.innerText || b.getAttribute("aria-label") || b.tagName).trim().slice(0, 18)} in #${b.closest("section")?.id} by .${String(p.className).slice(0, 30)}`);
          break;
        }
      }
      return bad;
    });
    ok(clipped.length === 0, `stable ${w}: every banner control has room for its focus ring inside any clipping box`, clipped.slice(0, 6).join(" | "));
  }
});

// ============ the hero is a small Designer ============
await section("editor", async () => {
  const S = () => page.evaluate(() => {
    const t = document.querySelector("#top"), h = t.querySelector("h1"), cv = t.querySelector(".hero-canvas").getBoundingClientRect();
    const box = (n) => { const r = t.querySelector(`.hero-live [data-slot="${n}"]`).getBoundingClientRect(); return { x: Math.round(r.left - cv.left), y: Math.round(r.top - cv.top), w: Math.round(r.width), h: Math.round(r.height) }; };
    const nums = (sel) => [...t.querySelectorAll(sel)].map((e) => Number(e.textContent));
    return { ed: t.dataset.edited, heroH: Math.round(t.getBoundingClientRect().height), next: Math.round(document.querySelector("#why").getBoundingClientRect().top + scrollY), title: box("title"), body: box("body"), icon: box("icon"), time: box("time"), cols: nums(".hero-ruler-track"), rows: nums(".hero-rows-track"), lines: h.querySelectorAll("span").length, fs: parseFloat(getComputedStyle(h).fontSize), cw: Math.round(cv.width), gap: parseFloat(getComputedStyle(t.querySelector(".hero-ghost")).columnGap) };
  });
  const centre = (sel) => page.$eval(sel, (e) => { const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  const dragBy = async (from, dx, dy, steps = 10) => { await page.mouse.move(from.x, from.y); await page.mouse.down(); for (let i = 1; i <= steps; i++) { await page.mouse.move(from.x + (dx * i) / steps, from.y + (dy * i) / steps); await sleep(15); } };
  /** Every line's ink (content area of the last line, widest line's right edge) is inside the title cell. */
  const ink = () => page.evaluate(() => {
    const h = document.querySelector("#top h1"), cell = h.closest(".cell"), cs = getComputedStyle(cell), cr = cell.getBoundingClientRect();
    const spans = [...h.querySelectorAll("span")];
    const rng = document.createRange(); rng.selectNodeContents(spans[spans.length - 1]);
    const last = rng.getBoundingClientRect();
    const tops = spans.map((s) => { const r = document.createRange(); r.selectNodeContents(s); return r.getBoundingClientRect(); });
    const fs = parseFloat(getComputedStyle(h).fontSize);
    // lines never touch: the next line's cap top (≈ 0.72 em above its baseline) stays under this line's descender (≈ 0.2 em below its baseline)
    const pitch = tops.length > 1 ? Math.min(...tops.slice(1).map((r, i) => r.top - tops[i].top)) / fs : 1;
    return { bottom: Math.round(last.bottom - (cr.bottom - parseFloat(cs.borderBottomWidth) - parseFloat(cs.paddingBottom))), right: Math.round(Math.max(...tops.map((r) => r.right)) - (cr.right - parseFloat(cs.paddingRight))), pitch: +pitch.toFixed(3), wd: h.style.fontVariationSettings };
  });
  for (const [w, hh] of [[1440, 900], [2560, 1440]]) {
    await load("/", w, hh);
    await page.mouse.move(2, 2);
    await page.keyboard.press("Shift"); // any key ends the tour
    await sleep(700);
    const s0 = await S();
    const T = `editor ${w}`;
    ok(s0.ed === "false" && s0.cols.length === 12 && s0.rows.length === 3, `${T}: rulers show 12 columns and 3 rows in points`, JSON.stringify({ cols: s0.cols, rows: s0.rows }));
    // 1. drag a field onto another cell: they swap, the headline re-fits
    await page.hover('#top .hero-live [data-slot="title"]');
    const grip = await centre('#top .hero-live [data-slot="title"] .hero-grip'), body = await centre('#top .hero-live [data-slot="body"]');
    await dragBy(grip, body.x - grip.x, body.y - grip.y);
    ok(await page.$eval('#top .hero-live [data-slot="body"]', (e) => e.dataset.over === "true"), `${T}: the cell under a dragged field lights up as the drop target`);
    await page.mouse.up(); await page.mouse.move(2, 2); await sleep(800);
    const s1 = await S();
    const near = (a, b) => Math.abs(a - b) <= 2;
    const same = (a, b) => near(a.x, b.x) && near(a.y, b.y) && near(a.w, b.w) && near(a.h, b.h);
    ok(s1.ed === "true" && same(s1.title, s0.body) && same(s1.body, s0.title), `${T}: dragging the title by its grip onto the body cell swaps the two fields`, JSON.stringify({ title: s1.title, body: s1.body }));
    ok(s1.fs < s0.fs && s1.lines < 3, `${T}: the headline re-fits its new cell (fewer lines, smaller, the axis condensed)`, JSON.stringify({ fs: s1.fs, lines: s1.lines }));
    let k = await ink();
    ok(k.bottom <= 0 && k.right <= 0, `${T}: the moved headline's ink stays inside its cell`, JSON.stringify(k));
    // 2. a column divider
    const d4 = await centre('#top .hero-divider-col[aria-label="Resize column 4"]');
    await dragBy(d4, 60, 0); await page.mouse.up(); await page.mouse.move(2, 2); await sleep(500);
    const s2 = await S();
    const sum = (a) => a.reduce((x, y) => x + y, 0);
    ok(s2.cols[3] > s1.cols[3] + 40 && s2.cols[4] < s1.cols[4] - 20 && s2.cols[4] >= 24 && s2.cols.every((c, i) => i === 3 || i === 4 || c === s1.cols[i]), `${T}: dragging a column divider gives the column the width its neighbour gives up (24 pt floor)`, JSON.stringify(s2.cols));
    ok(Math.abs(sum(s2.cols) + 11 * s2.gap - s2.cw) <= 6, `${T}: the ruler's columns plus gaps still sum to the canvas (${sum(s2.cols)} + 11 × ${s2.gap} vs ${s2.cw})`);
    // 3. a row divider
    const r1 = await centre('#top .hero-divider-row[aria-label="Resize row 1"]');
    await dragBy(r1, 0, -70); await page.mouse.up(); await page.mouse.move(2, 2); await sleep(700);
    const s3 = await S();
    ok(s3.rows[0] < s2.rows[0] - 50 && s3.rows[1] > s2.rows[1] + 50 && near(sum(s3.rows), sum(s2.rows)), `${T}: dragging a row divider moves height between two rows`, JSON.stringify(s3.rows));
    ok(s3.fs > s1.fs, `${T}: the headline grows with its row`, `${s1.fs} -> ${s3.fs}`);
    // 4. keyboard: move a field, resize a track
    await page.focus('#top .hero-live [data-slot="icon"] .hero-grip');
    await page.keyboard.press("ArrowRight"); await sleep(700);
    const s4 = await S();
    ok(s4.icon.x === s3.time.x && s4.time.x === s3.icon.x, `${T}: ArrowRight on a field's grip moves it to the next cell`, JSON.stringify({ icon: s4.icon.x, time: s4.time.x }));
    await page.focus('#top .hero-divider-col[aria-label="Resize column 9"]');
    await page.keyboard.press("ArrowRight"); await sleep(400);
    const s5 = await S();
    ok(s5.cols[8] > s4.cols[8] && s5.cols[9] < s4.cols[9], `${T}: ArrowRight on a divider resizes the track`, JSON.stringify(s5.cols));
    // 5. the right edge still resizes the whole grid; sample the headline's ink from full to the narrowest
    const hb = await centre(".hero-handle");
    await page.mouse.move(hb.x, hb.y); await page.mouse.down();
    let worst = { bottom: -99, right: -99, pitch: 9 };
    for (let i = 1; i <= 14; i++) { await page.mouse.move(hb.x - (i * s5.cw * 0.45) / 14, hb.y); await sleep(40); k = await ink(); worst = { bottom: Math.max(worst.bottom, k.bottom), right: Math.max(worst.right, k.right), pitch: Math.min(worst.pitch, k.pitch) }; }
    await page.mouse.up(); await page.mouse.move(2, 2); await sleep(400);
    ok(worst.bottom <= 0 && worst.right <= 0, `${T}: at every canvas width the headline's last line, descenders included, is inside the cell`, JSON.stringify(worst));
    // 6. Send describes the arrangement
    await clickBtn("#top .hero-live", "Send");
    ok(await waitFor(async () => /Your layout: .*title r\d.* Columns /.test(await overlayText()), 3000), `${T}: Send puts a banner under the bell that states the visitor's arrangement`, (await overlayText()).slice(0, 160));
    // 7. nothing moved the page
    const s6 = await S();
    ok(s6.heroH === s0.heroH && s6.next === s0.next, `${T}: the hero keeps its height through every edit (${s0.heroH} px) and the next section stays put`, JSON.stringify({ h: s6.heroH, next: s6.next }));
    // 8. Reset
    await clickBtn("#top .hero-pick", "Reset"); await sleep(900);
    const s7 = await S();
    ok(s7.ed === "false" && JSON.stringify(s7.cols) === JSON.stringify(s0.cols) && same(s7.title, s0.title) && s7.cw === s0.cw && s7.heroH === s0.heroH, `${T}: Reset restores the preset`, JSON.stringify({ cols: s7.cols, title: s7.title }));
    // 9. presets: ink inside the cell across the width range, lines never touch
    for (const l of ["hero", "imageLeft", "compact"]) {
      await clickBtn("#top .hero-pick", l); await sleep(800);
      const hb2 = await centre(".hero-handle");
      await page.mouse.move(hb2.x, hb2.y); await page.mouse.down();
      let wst = { bottom: -99, right: -99, pitch: 9 };
      for (let i = 0; i <= 12; i++) { await page.mouse.move(hb2.x - (i * s0.cw * 0.44) / 12, hb2.y); await sleep(40); k = await ink(); wst = { bottom: Math.max(wst.bottom, k.bottom), right: Math.max(wst.right, k.right), pitch: Math.min(wst.pitch, k.pitch) }; }
      await page.mouse.up(); await page.mouse.move(2, 2);
      ok(wst.bottom <= 0 && wst.right <= 0, `${T}: ${l}: from full width to the narrowest the headline's ink (g, y descenders) stays inside the title cell`, JSON.stringify(wst));
      ok(wst.pitch >= 0.9, `${T}: ${l}: lines keep at least 0.9 em between baselines, more when condensed (min ${wst.pitch})`);
      await clickBtn("#top .hero-pick", "Reset"); await sleep(500);
    }
    // icon fitted to its cell
    await clickBtn("#top .hero-pick", "imageLeft"); await sleep(800);
    for (const l of ["imageLeft", "hero"]) {
      await clickBtn("#top .hero-pick", l); await sleep(800);
      const cov = await page.evaluate(() => { const c = document.querySelector('#top .hero-live [data-slot="icon"]'), i = c.querySelector("img").getBoundingClientRect(), s = getComputedStyle(c); const cw = c.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight), ch = c.clientHeight - parseFloat(s.paddingTop) - parseFloat(s.paddingBottom); return { cover: +(i.width / Math.min(cw, ch)).toFixed(2), capped: i.width >= 299 }; });
      ok(cov.cover >= 0.7 || cov.capped, `${T}: ${l}: the icon is fitted to its cell (${Math.round(cov.cover * 100)} % of the shorter side)`);
    }
  }
  // phone: tap a field, then tap the cell it should go to; steppers for a track
  await load("/", 390, 844);
  await page.keyboard.press("Shift"); await sleep(600);
  const p0 = await S();
  await jsClick('#top .hero-live [data-slot="icon"]', "Move icon");
  ok(await waitFor(() => page.$eval("#top", (e) => e.dataset.picking === "true"), 1500), "editor 390: tapping a field's grip picks it up");
  await page.$eval('#top .hero-live [data-slot="time"]', (e) => e.click()); await sleep(700);
  const p1 = await S();
  ok(p1.icon.x === p0.time.x && p1.time.x === p0.icon.x, "editor 390: tapping another cell drops it there (the two swap)", JSON.stringify({ icon: p1.icon.x, time: p1.time.x }));
  await page.$eval("#top .hero-ruler-track", (e) => e.click()); await sleep(300);
  await jsClick("#top .hero-stepper", "Larger"); await sleep(400);
  const p2 = await S();
  ok(p2.cols[0] > p1.cols[0] && p2.cols[1] < p1.cols[1], "editor 390: tapping a column on the ruler gives a stepper that resizes it", JSON.stringify(p2.cols));
  ok(p2.heroH === p0.heroH && (await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)), "editor 390: the hero keeps its height and nothing overflows", JSON.stringify({ a: p0.heroH, b: p2.heroH }));
  // Download band: icon fitted to its cell
  for (const w of [1440, 834, 390]) {
    await load("/", w, 900);
    const cov = await page.evaluate(() => { const c = [...document.querySelectorAll("#download .cell")].find((e) => e.querySelector(".slot")?.textContent === "icon"); c.scrollIntoView(); const i = c.querySelector("img").getBoundingClientRect(), s = getComputedStyle(c); const cw = c.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight), ch = c.clientHeight - parseFloat(s.paddingTop) - parseFloat(s.paddingBottom); return +(Math.min(i.width, i.height) / Math.min(cw, ch)).toFixed(2); });
    ok(cov >= 0.7, `download ${w}: the icon covers ${Math.round(cov * 100)} % of its cell's shorter side`);
  }
});

// ============ header and anchors ============
await section("anchors", async () => {
  for (const path of ["/", "/changelog", "/docs"]) {
    await load(path, 1024, 768);
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok(over <= 0, `header 1024: no document overflow on ${path}`, String(over));
  }
  for (const [w, h] of [[1440, 900], [1865, 1030]]) {
    await page.setViewport({ width: w, height: h });
    for (const id of ["why", "designer", "actions", "agents", "integrate", "download"]) {
      await page.goto(BASE + "/#" + id, { waitUntil: "load" });
      await sleep(1600);
      const r = await page.evaluate((id) => { const s = document.getElementById(id); const hd = document.querySelector("header").getBoundingClientRect().bottom; const cell = s.querySelector("h2").closest(".cell") || s.querySelector("h2"); const q = (x) => { const e = s.querySelector(x); return e ? e.getBoundingClientRect().bottom : 0; }; return { top: Math.round(cell.getBoundingClientRect().top - hd), frame: Math.round(q(".dz-frame")), legend: Math.round(q(".dz-legend")), frameW: Math.round(s.querySelector(".dz-frame")?.getBoundingClientRect().width || 0), vh: innerHeight }; }, id);
      ok(r.top >= 0 && r.top <= 40, `anchor ${w}: #${id} lands with its title cell just under the header (${r.top} px)`);
      if (id === "designer") {
        ok(r.frame <= r.vh && r.legend <= r.vh, `anchor ${w}: #designer shows the whole capture and its six notes on one screen`, JSON.stringify(r));
        ok(r.frameW >= 840, `anchor ${w}: the Designer capture is large (${r.frameW} px wide)`);
      }
    }
  }
  // brand link: back to the very top, hash cleared
  await page.setViewport({ width: 1440, height: 900 });
  await page.goto(BASE + "/#actions", { waitUntil: "load" });
  await sleep(1200);
  await page.click('[data-testid="brand-home"]');
  ok(await waitFor(() => page.evaluate(() => scrollY === 0 && location.hash === ""), 3000), "header: the brand link returns to the very top and clears the hash");
});

// ============ round 2 ============
await section("round2", async () => {
  await load("/", 1440, 900);
  await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 700) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 30)); } window.scrollTo(0, 0); });
  // type: wide titles
  const titles = await page.$$eval("main section:not(#top):not(#download) .sec-head .display-l", (h) => h.map((e) => ({ t: e.innerText.slice(0, 24), v: getComputedStyle(e).fontVariationSettings })));
  ok(titles.length === 9 && titles.every((t) => /"wdth" 132/.test(t.v)), "round2: nine section titles, all set wide (wdth 132)", JSON.stringify(titles));
  const heads = await page.$$eval(".sec-head", (h) => h.map((e) => [...e.querySelectorAll(":scope > .cell > .slot")].map((s) => s.textContent)));
  ok(heads.length === 9 && heads.every((s) => s[0] === "title"), "round2: every section head is a title field in a cell", JSON.stringify(heads));
  // flow: three heads on one baseline
  const fh = await page.$$eval("#flow article > h3", (h) => h.map((e) => Math.round(e.getBoundingClientRect().top)));
  ok(fh.length === 3 && Math.max(...fh) - Math.min(...fh) <= 1, "round2 flow: manifest / template / banner heads share a baseline", fh.join(","));
  const tokens = await page.$$eval("#flow article:nth-of-type(2) .cell", (c) => c.map((e) => e.innerText.replace(/\s+/g, " ").trim()));
  ok(["{title}", "{status}", "{body}", "{log}", "{action}"].every((t) => tokens.some((x) => x.includes(t))), "round2 flow: template cells show the tokens they bind", tokens.join(" | "));
  // version
  const ver = await page.evaluate(() => ({ hero: document.querySelector("#top .hero-live .btn-primary")?.innerText || "", dl: document.querySelector("#download")?.innerText || "" }));
  const vnum = (/(\d+)\.(\d+)\.(\d+)/.exec(ver.hero) || []).slice(1).map(Number);
  ok(vnum.length === 3 && (vnum[0] * 1e6 + vnum[1] * 1e3 + vnum[2]) >= 1006005, "round2: the hero download button shows 1.6.5 or later", ver.hero);
  ok(new RegExp(vnum.join("\\.")).test(ver.dl) && /build \d+/i.test(ver.dl), "round2: Download shows the same version and its build", ver.dl.slice(0, 160).replace(/\n/g, " "));
  // download is the closing blueprint band
  const dl = await page.evaluate(() => { const d = document.querySelector("#download"); return { bp: d.classList.contains("blueprint"), last: d === document.querySelector("main").lastElementChild, slots: [...d.querySelectorAll(".cell > .slot")].map((s) => s.textContent) }; });
  ok(dl.bp && dl.last, "round2: Download is the closing blueprint band", JSON.stringify(dl));
  ok(["icon", "title", "version", "size", "sha", "requirements", "actions"].every((x) => dl.slots.includes(x)), "round2: Download is laid out as the template (seven named cells)", dl.slots.join(","));
  ok(await page.$eval("#changelog h2", (e) => e.innerText.trim().length > 0), "round2: the changelog preview has a title");
  // gutters at 1280
  await load("/", 1280, 800);
  const gut = await page.$eval("#why .sec-head", (e) => Math.round(e.getBoundingClientRect().left));
  ok(gut >= 32, `round2: the page keeps a gutter at 1280 (${gut} px)`);
  // not-found
  const res = await page.goto(BASE + "/docs/guides/nope", { waitUntil: "load" });
  await sleep(600);
  const nf = await page.evaluate(() => ({ h1: document.querySelector("h1")?.innerText || "", bg: getComputedStyle(document.body).backgroundColor, home: !!document.querySelector('header a[aria-label="Herald home"]') }));
  ok(res.status() === 404 && /Nothing at this address/.test(nf.h1) && nf.bg !== "rgb(0, 0, 0)" && nf.home, "round2: unknown URLs get the site's own 404 on the Day ground", JSON.stringify(nf));
  // docs index centred, no eyebrow
  await load("/docs", 1440, 900);
  const di = await page.evaluate(() => { const i = document.querySelector(".docs-index"), m = i.parentElement; const a = i.getBoundingClientRect(), b = m.getBoundingClientRect(); return { l: Math.round(a.left - b.left), r: Math.round(b.right - a.right), eyebrow: document.querySelectorAll(".eyebrow").length }; });
  ok(Math.abs(di.l - di.r) <= 2 && di.eyebrow === 0, "round2 docs: the index is centred in its column and has no eyebrow", JSON.stringify(di));
});

// ============ errors ============
ok(errors.length === 0, "no console errors or page errors across the run", errors.slice(0, 4).join(" | "));

await browser.close();
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) console.log("Failed:\n  - " + failed.join("\n  - "));
process.exit(fail ? 1 : 0);
