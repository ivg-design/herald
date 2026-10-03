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

// ============ 1 hero dock ============
await section("hero", async () => {
  await load("/");
  const DOCK = '[aria-label="Herald banners"]';
  const MAIL = '[aria-label="WebWatcher · Email banner"]';
  const CI = '[aria-label="CI Bot banner"]';
  const AE = '[aria-label="After Effects banner"]';
  await waitText(DOCK, "Build passed", 5000);
  ok((await has(DOCK, "Office hours moved")) && (await has(DOCK, "Render finished")) && (await has(DOCK, "Build passed")), "hero: three starting banners (mail, After Effects, CI Bot)");
  ok(await exists(`${MAIL} [aria-label="3 banners in this stack"]`), "hero: WebWatcher Email stacked x3");
  ok((await page.$eval(`${MAIL} [aria-label="3 banners in this stack"]`, (e) => e.innerText.trim()).catch(() => "")) === "3", "hero: red counter reads 3");
  ok(await bellCount() === 5, "hero: header bell count equals pending (5)", await bellLabel());

  await clickBtn(CI, "Deploy");
  ok(await waitText(CI, "Deploy build 4f2a to production?", 2000) && (await has(CI, "Yes, deploy")) && (await has(CI, "Cancel")), "hero: Deploy shows inline question with Yes, deploy / Cancel");
  await clickBtn(CI, "Cancel");
  ok(await waitFor(async () => (await has(CI, "Open log")) && (await has(CI, "Deploy")) && !(await has(CI, "Yes, deploy")), 2000), "hero: Cancel restores the button row");

  await clickBtn(AE, "Show in Finder");
  ok(await waitText(AE, "Opened final_v3.mp4", 2000), "hero: Show in Finder gives an Opened outcome");

  await clickBtn(AE, "Snooze");
  ok(await waitText(DOCK, "returns at 9:00", 2000) && !(await has(DOCK, "Render finished")), "hero: Snooze shows 'returns at 9:00' line");
  ok(await bellCount() === 4, "hero: bell count drops while a card is snoozed", await bellLabel());
  ok(await waitText(DOCK, "Back from snooze", 5000) && (await has(DOCK, "Render finished")), "hero: card returns after about 3 s with 'Back from snooze'");

  const h0 = await historyN();
  await clickBtn(AE, "Dismiss");
  ok(await waitGone(DOCK, "Render finished", 3000), "hero: x removes the After Effects banner");
  ok(await waitFor(async () => (await historyN()) === h0 + 1, 2000) && (await text("main")).includes("1 dismissed · kept in History"), "hero: history line '1 dismissed · kept in History' appears");

  await clickBtn("#top", "Run it");
  ok(await waitFor(() => exists(`${CI} [aria-label="2 banners in this stack"]`), 2500), "hero: Run it stacks CI Bot, counter 2");
  ok(await has("#top", "Sent · stacked with CI Bot (2)"), "hero: outcome line under the command", await text("#top [role=status]"));
  ok(await waitFor(async () => (await bellCount()) === 5, 1500), "hero: bell count equals pending after stacking (5)", await bellLabel());

  const h1 = await historyN();
  await clickBtn(CI, "Deploy");
  await clickBtn(CI, "Yes, deploy");
  ok(await waitText(CI, "Waiting for", 2000), "hero: Yes, deploy shows 'Waiting for ...'");
  ok(await waitGone(DOCK, "Build passed", 6000), "hero: callback answers and the CI Bot banner is dismissed");
  ok(await waitFor(async () => (await historyN()) === h1 + 2, 2000), "hero: history grows by the 2 stacked items", `${h1} -> ${await historyN()}`);
  ok(await waitFor(async () => (await bellCount()) === 3, 1500), "hero: bell count equals remaining pending (3)", await bellLabel());
});

// ============ 2 why ============
await section("why", async () => {
  await scrollToSel("#why .fs-btn");
  const t0 = Date.now();
  await page.click('button[aria-label="Send the same alert to both"]');
  await page.mouse.move(2, 2);
  ok(await waitFor(() => exists('[data-testid="system-banner"]'), 1500), "why: system banner appears");
  await sleep(Math.max(0, 1200 - (Date.now() - t0)));
  const g = (await page.$eval(".fs-glyph", (e) => e.innerText.replace(/\s/g, " ")).catch(() => "")).trim();
  ok(g === "4 s" || g === "3 s", "why: countdown shows 4 s or 3 s at ~1.2 s", g);
  const ov = await waitFor(async () => (await overlayText()).includes("Build passed"), 2500);
  ok(ov, "why: page Herald got a CI Bot item (overlay contains 'Build passed')", await overlayText());
  ok(await page.$eval("#herald-overlay .hb-stack", (e) => e.dataset.open === "true").catch(() => false), "why: overlay is visible (open) after the send");
  ok((await text('[data-testid="herald-line"]')).trim().length > 0, "why: Herald line is non-empty");
  await sleep(Math.max(0, 5800 - (Date.now() - t0)));
  ok(!(await exists('[data-testid="system-banner"]')), "why: system banner is gone after about 5.6 s");
  ok((await text('[data-testid="gone-line"]')).trim() === "Gone. It is not in any history.", "why: gone line reads 'Gone. It is not in any history.'", await text('[data-testid="gone-line"]'));
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
  await clickBtn(FLOW, "1 · Manifest");
  ok(await page.$eval("#flow [role=tab][aria-selected=true]", (e) => e.innerText.includes("Manifest")), "flow: step tab selects a step");
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
  ok(Math.abs(l.ih - (l.hh - 5)) <= 1.5, `landing: .site-brand-icon height = header height - 5 (${l.ih} vs ${l.hh})`);

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

// ============ errors ============
ok(errors.length === 0, "no console errors or page errors across the run", errors.slice(0, 4).join(" | "));

await browser.close();
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) console.log("Failed:\n  - " + failed.join("\n  - "));
process.exit(fail ? 1 : 0);
