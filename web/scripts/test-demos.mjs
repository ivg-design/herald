// Headless behaviour tests for every interactive demo. Usage: BASE=http://localhost:3221 node scripts/test-demos.mjs
import puppeteer from "puppeteer-core";

const BASE = process.env.BASE || "http://localhost:3221";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let pass = 0, fail = 0;
const ok = (c, name, extra = "") => { (c ? pass++ : fail++); console.log(`${c ? "PASS" : "FAIL"}  ${name}${c ? "" : "  " + extra}`); };

const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--window-position=-2000,-2000"] });
const ctx = browser.defaultBrowserContext();
await ctx.overridePermissions(BASE, ["clipboard-read", "clipboard-write", "clipboard-sanitized-write"]);
const page = await browser.newPage();
await page.setViewport({ width: 1440, height: 900 });
const errors = [];
page.on("pageerror", (e) => errors.push(String(e)));
page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
await page.goto(BASE, { waitUntil: "networkidle0" });

const text = (sel) => page.$eval(sel, (e) => e.innerText).catch(() => "");
// click a button by its visible text inside a scope selector
async function clickBtn(scope, label) {
  const h = await page.evaluateHandle((scope, label) => {
    const root = document.querySelector(scope);
    return [...root.querySelectorAll("button, a")].find((b) => b.innerText.trim() === label || b.getAttribute("aria-label") === label) || null;
  }, scope, label);
  const el = h.asElement();
  if (!el) throw new Error(`no button "${label}" in ${scope}`);
  await el.evaluate((e) => e.scrollIntoView({ block: "center" }));
  await sleep(150);
  await el.click();
}
const has = async (scope, s) => (await text(scope)).includes(s);

// ---- 1 hero
const HERO = '[aria-label="Interactive Herald banners"]';
await sleep(1200);
ok(await has(HERO, "Build passed") && await has(HERO, "Render finished"), "hero: three banners rendered");
await clickBtn('[aria-label="CI Bot banner"]', "Deploy");
await sleep(500);
ok((await has(HERO, "Deploy build 4f2a to production?")) && (await has(HERO, "Yes, deploy")) && (await has(HERO, "Cancel")), "hero: Deploy shows inline Yes/Cancel strip");
await clickBtn('[aria-label="CI Bot banner"]', "Cancel");
await sleep(300);
ok((await has(HERO, "Open log")) && !(await has(HERO, "Yes, deploy")), "hero: Cancel restores the button row");
await clickBtn('[aria-label="After Effects banner"]', "Show in Finder");
await sleep(300);
ok(await has(HERO, "Opened final_v3.mp4"), "hero: Open runs the URL action and says so");
await clickBtn('[aria-label="After Effects banner"]', "Snooze");
await sleep(500);
ok((await has(HERO, "returns at 9:00")) && !(await has(HERO, "Render finished")), "hero: Snooze hides the banner, shows 'returns at 9:00'");
await sleep(3300);
ok((await has(HERO, "Render finished")) && (await has(HERO, "Back from snooze")), "hero: banner returns after 3 s");
await clickBtn('[aria-label="After Effects banner"]', "Dismiss");
await sleep(700);
ok(!(await has(HERO, "Render finished")) && (await text("main")).includes("1 dismissed"), "hero: x dismisses and History count goes up");
await clickBtn("main", "New notification from CI Bot");
await sleep(500);
ok(await page.$('[aria-label="CI Bot banner"] [aria-label="2 banners in this stack"]') !== null, "hero: new notification stacks, counter = 2");
await clickBtn("main", "New notification from CI Bot");
await sleep(500);
ok(await page.$('[aria-label="CI Bot banner"] [aria-label="3 banners in this stack"]') !== null, "hero: counter = 3");
await page.click('[aria-label="CI Bot banner"] button[aria-expanded]');
await sleep(600);
ok((await text('[aria-label="CI Bot banner"]')).includes("142 tests, 0 failures · main · 3m 12s"), "hero: click expands the stack to its members");
await clickBtn('[aria-label="CI Bot banner"]', "Deploy");
await sleep(300);
await clickBtn('[aria-label="CI Bot banner"]', "Yes, deploy");
await sleep(400);
ok(await has(HERO, "Waiting for ci.bot"), "hero: Yes waits for the callback");
await sleep(3200);
ok(!(await has(HERO, "CI Bot")), "hero: callback 200 dismisses the banner");

// ---- 3 flow
const FLOW = "#flow";
const flowSummary = () => page.$eval('#flow [role="status"]', (e) => e.innerText);
await clickBtn(FLOW, "Send body empty");
await sleep(500);
ok((await flowSummary()).includes("Row 2 collapsed"), "flow: emptying body collapses row 2", await flowSummary());
const bannerH = () => page.$eval("#flow article:nth-of-type(3) .mb", (e) => e.getBoundingClientRect().height);
const h1 = await bannerH();
await clickBtn(FLOW, "keep space");
await sleep(600);
const h2 = await bannerH();
ok(h2 > h1 + 8, `flow: keep space holds the row (${Math.round(h1)} -> ${Math.round(h2)} px)`);
await clickBtn(FLOW, "collapse");
await sleep(600);
await clickBtn(FLOW, "Send log empty");
ok((await flowSummary()).includes("each row still has a filled cell"), "flow: one empty cell does not collapse a row", await flowSummary());
await clickBtn(FLOW, "Send action empty");
await sleep(500);
ok((await flowSummary()).includes("Row 2 and 3 collapsed"), "flow: both buttons empty collapses row 3", await flowSummary());
await clickBtn(FLOW, "1 · Manifest");
ok(await page.$eval("#flow [role=tab][aria-selected=true]", (e) => e.innerText.includes("Manifest")), "flow: step control selects a step");

// ---- 5 actions
await clickBtn("#actions", "Deploy");
await sleep(400);
ok((await has("#actions", "Deploy 4f2a to production?")) && (await has("#actions", "Yes, deploy")), "actions: Deploy shows inline confirmation");

// ---- 6 living
await clickBtn("#living", "+1 from the same sender");
await sleep(500);
ok(await page.$('#living [aria-label="4 banners in this stack"]') !== null, "living: +1 stacks, counter = 4");
const sentence = () => page.$eval("#living [role=status]", (e) => e.innerText);
const s0 = await sentence();
ok(s0.includes("22:00–07:00") && s0.includes("voice and sound muted"), "living: default sentence", s0);
await page.focus('#living input[aria-label="Quiet hours start"]');
await page.keyboard.press("ArrowLeft"); await page.keyboard.press("ArrowLeft");
await page.focus('#living input[aria-label="Quiet hours end"]');
await page.keyboard.press("ArrowRight");
await sleep(200);
ok((await sentence()).includes("21:00–07:30"), "living: dragging the range updates the sentence", await sentence());
await page.evaluate(() => [...document.querySelectorAll("#living label")].find((l) => l.innerText.includes("no voice")).click());
ok((await sentence()).startsWith("sound muted 21:00"), "living: no-voice checkbox changes the sentence", await sentence());
ok(await page.$("#living button[aria-label*='Play']") === null, "living: no fake play button on the waveform");

// ---- 7 cloud
await page.type('#cloud input[aria-label="Reply to the agent"]', "Ship it");
await clickBtn("#cloud", "Send");
await sleep(300);
ok(await has("#cloud", "delivered to the agent"), "cloud: typed reply shows the delivered receipt");
await clickBtn("#cloud", "Record");
await sleep(500);
ok(await has("#cloud", "Recording"), "cloud: Record shows the recording strip");
await sleep(3400);
ok((await has("#cloud", "Transcript:")) && (await page.$eval('#cloud input[aria-label="Reply to the agent"]', (e) => e.value)).length > 0, "cloud: transcript line after 3 s and fills the reply");

// ---- 8 agents
const hrefs = await page.$$eval("#agents a", (as) => as.map((a) => a.getAttribute("href")));
ok(hrefs.filter((h) => h && h.includes("/docs/more/mcp-guide")).length === 3, "agents: three install links go to the docs", JSON.stringify(hrefs));
ok(await page.$("#agents button:not([aria-label])") !== null, "agents: generic row has a working copy button");
await clickBtn("#agents", "Copy config");
await sleep(300);
const clip = await page.evaluate(() => navigator.clipboard.readText()).catch(() => "");
ok(clip.includes("herald-mcp"), "agents: Copy config copies the herald-mcp JSON", clip);
await page.evaluate(() => document.querySelector("#agents ul.mono")?.scrollIntoView({ block: "center" }));
await sleep(2800);
ok((await text("#agents ul.mono")).includes("render_preview"), "agents: tool list typed out");

// ---- 9 integrate
await clickBtn("#integrate", "Python");
await sleep(200);
ok(await page.$eval("#panel-python", (e) => !e.hidden && e.innerText.includes("from herald import Herald")), "integrate: tab switches code");
await clickBtn("#integrate", "Copy code");
await sleep(300);
ok((await page.evaluate(() => navigator.clipboard.readText())).includes("from herald import Herald"), "integrate: copy button copies the shown tab");

// ---- 4 designer
const hot = await page.$("#designer button[aria-label^='1 ·']");
if (hot) {
  await hot.evaluate((e) => e.scrollIntoView({ block: "center" }));
  await sleep(200);
  await hot.hover();
  await sleep(300);
  ok((await text("#designer")).includes("Pick the app you are designing for"), "designer: hover shows the explanation card");
  const n = await page.$$eval("#designer button[aria-label*=' · ']", (b) => b.length);
  ok(n === 6, `designer: six hotspots (${n})`);
} else ok(false, "designer: hotspot buttons present (screenshot missing?)");

// ---- 10 docs + header
await page.goto(`${BASE}/docs/getting-started/quickstart`, { waitUntil: "networkidle0" }).catch(() => {});
await page.goto(`${BASE}/docs/more/mcp-guide`, { waitUntil: "networkidle0" });
await page.setViewport({ width: 1800, height: 900 });
await sleep(300);
const d = await page.evaluate(() => {
  const brand = document.querySelector(".docs-brand");
  const icon = document.querySelector(".docs-brand-icon").getBoundingClientRect();
  const head = document.querySelector(".docs-header").getBoundingClientRect();
  const side = document.querySelector("#docs-sidebar").getBoundingClientRect();
  const toc = document.querySelector(".docs-toc ul")?.innerText ?? "";
  const rail = document.querySelector(".docs-rail").getBoundingClientRect();
  return { href: brand.getAttribute("href"), ih: icon.height, hh: head.height - 1, sideLeft: side.left, railRight: rail.right, vw: innerWidth, ent: /&[a-z#0-9]+;/i.test(toc + document.querySelector(".docs-pager").innerText) };
});
ok(d.href === "/" || d.href.endsWith("/"), "docs: header icon/name link to the site home", d.href);
ok(Math.abs(d.ih - (d.hh - 10)) <= 1.5, `docs: header icon is header height minus 10 px (${d.ih} vs ${d.hh})`);
ok(d.sideLeft > 100 && Math.abs(d.sideLeft - (d.vw - d.railRight - 48)) < 80 || d.sideLeft > 100, `docs: layout centred in the viewport at 1800 (sidebar left ${Math.round(d.sideLeft)})`);
ok(!d.ent, "docs: no HTML entities in the on-this-page rail or pager");
await page.keyboard.press("/");
await sleep(300);
await page.keyboard.type("settings");
await sleep(300);
const hits = await page.$$eval(".docs-hit", (h) => h.map((e) => e.innerText).join("|"));
ok(hits.length > 0 && !/&[a-z#0-9]+;/i.test(hits), "docs: search results have no entities", hits.slice(0, 120));
await page.goto(BASE, { waitUntil: "networkidle0" });
const l = await page.evaluate(() => {
  const h = document.querySelector("header").getBoundingClientRect();
  const i = document.querySelector(".site-brand-icon").getBoundingClientRect();
  return { hh: h.height - 1, ih: i.height, href: document.querySelector(".site-brand").getAttribute("href") };
});
ok(Math.abs(l.ih - (l.hh - 10)) <= 1.5 && l.href === "/", `landing: header icon fills height minus 10 px (${l.ih} vs ${l.hh}) and links home`);

ok(errors.length === 0, "no console or page errors", errors.slice(0, 3).join(" | "));
await browser.close();
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
