// Docs must never scroll horizontally. Crawls every docs URL (docs index, every page in the sitemap, changelog)
// at five widths and fails listing each element that overflows its box or is an overflow-x scroller with overflow.
// Also checks the rendering rules: short tokens stay whole, long tokens break only at separators, the wrapped
// code block copies its original text, narrow tables restack.
// Usage: BASE=http://localhost:3297 node scripts/test-docs-hscroll.mjs   (serve a built site first; never port 3102)
import puppeteer from "puppeteer-core";

const BASE = process.env.BASE || "http://localhost:3297";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const WIDTHS = [1440, 1280, 1024, 834, 390];
const SHOTS = process.env.SHOTS; // directory for screenshots, optional

const xml = await (await fetch(`${BASE}/sitemap.xml`)).text();
const paths = [...new Set([...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname.replace(/\/$/, "") || "/"))]
  .filter((p) => p === "/changelog" || p.startsWith("/docs"));
if (!paths.includes("/docs")) paths.push("/docs");

const probe = () => {
  const out = [];
  const de = document.documentElement;
  if (de.scrollWidth > de.clientWidth + 1) out.push(`document: scrollWidth ${de.scrollWidth} > clientWidth ${de.clientWidth}`);
  if (document.body.scrollWidth > de.clientWidth + 1) out.push(`body: scrollWidth ${document.body.scrollWidth}`);
  for (const el of document.querySelectorAll("*")) {
    if (el.closest("dialog:not([open]), .docs-sidebar:not(.is-open)") && !el.matches(".docs-sidebar")) continue;
    const cs = getComputedStyle(el);
    if (cs.display === "none" || cs.visibility === "hidden" || el.tagName === "SCRIPT" || el.tagName === "STYLE") continue;
    if (el.closest("svg") && el.tagName !== "svg") continue;
    const over = el.scrollWidth - el.clientWidth;
    const ox = cs.overflowX;
    const desc = `${el.tagName.toLowerCase()}${el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\s+/).join(".") : ""} "${(el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 50)}"`;
    if (el.clientWidth > 0 && over > 1 && (ox === "auto" || ox === "scroll" || ox === "visible" || ox === "hidden")) {
      // A visible-overflow box only counts when it spills out of the viewport or a clipping ancestor; hidden/auto/scroll count always.
      if (ox !== "visible") out.push(`${desc}: overflow-x ${ox}, scrollWidth ${el.scrollWidth} > clientWidth ${el.clientWidth}`);
      else {
        const r = el.getBoundingClientRect();
        const right = Math.max(r.right, el.scrollWidth + r.left);
        if (right > de.clientWidth + 1 && ["TABLE", "PRE", "CODE", "DIV", "P", "LI", "TD", "TH", "FIGURE", "IMG"].includes(el.tagName)) out.push(`${desc}: spills to ${Math.round(right)} past viewport ${de.clientWidth}`);
      }
    }
    if (el.tagName === "IMG" || el.tagName === "TABLE" || el.tagName === "PRE") {
      const r = el.getBoundingClientRect();
      if (r.right > de.clientWidth + 1) out.push(`${desc}: right edge ${Math.round(r.right)} past viewport ${de.clientWidth}`);
    }
  }
  return out;
};

const browser = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--window-position=-2000,-2000"] });
let offenders = 0, pass = 0, fail = 0;
const ok = (c, name, extra = "") => { c ? pass++ : fail++; console.log(`${c ? "PASS" : "FAIL"}  ${name}${c ? "" : extra ? "  [" + String(extra).slice(0, 300) + "]" : ""}`); };
try {
  const page = await browser.newPage();
  const perWidth = Object.fromEntries(WIDTHS.map((w) => [w, 0]));
  for (const w of WIDTHS) {
    await page.setViewport({ width: w, height: 900 });
    for (const p of paths) {
      await page.goto(BASE + p, { waitUntil: "load", timeout: 30000 });
      await new Promise((r) => setTimeout(r, 150));
      const found = await page.evaluate(probe);
      if (found.length) {
        perWidth[w] += found.length; offenders += found.length;
        console.log(`  OFFENDERS ${w} ${p}`);
        for (const f of found.slice(0, 12)) console.log(`    - ${f}`);
        if (found.length > 12) console.log(`    ... ${found.length - 12} more`);
      }
    }
  }
  console.log(`crawled ${paths.length} URLs x ${WIDTHS.length} widths; offenders per width: ${JSON.stringify(perWidth)}`);
  ok(offenders === 0, "docs: no element scrolls or spills horizontally on any docs URL at 1440/1280/1024/834/390", `${offenders} offenders`);

  // ---- rendering rules ----
  const cloud = "/docs/reference/cloud-relay-api";
  await page.setViewport({ width: 1440, height: 900 });
  await page.goto(BASE + cloud, { waitUntil: "load" });
  const r = await page.evaluate(() => {
    const tds = [...document.querySelectorAll(".docs-table td")];
    const text = tds.map((t) => t.textContent).join(" ");
    const lone = /(^|[^\\])`/.test(tds.map((t) => t.textContent).join("\n")) ;
    const short = [...document.querySelectorAll(".docs-table td code")].filter((c) => c.textContent.length <= 14 && !/\s/.test(c.textContent) && c.getClientRects().length);
    const split = short.filter((c) => new Set([...c.getClientRects()].map((x) => Math.round(x.top))).size > 1).map((c) => c.textContent);
    return { lone, split, hasDecision: text.includes('decision: "approve"|"deny"'), wbr: document.querySelectorAll(".docs-table td code wbr").length, scrollers: document.querySelectorAll(".docs-table[tabindex], .docs-table[role=region]").length };
  });
  ok(!r.lone, "docs: no literal backtick leaks into a table cell (code spans with a pipe parse)");
  ok(r.hasDecision, "docs: the consent row renders its pipe inside code");
  ok(r.split.length === 0, "docs: short code tokens in tables are never split", r.split.join(" "));
  ok(r.wbr > 0, "docs: long inline code in tables carries break points (<wbr>)", String(r.wbr));
  ok(r.scrollers === 0, "docs: tables have no scroll region wrapper");

  // long tokens break only at separators: no text node of a code token wraps mid-word unless it had no break point
  for (const w of [1440, 390]) {
    await page.setViewport({ width: w, height: 900 });
    await page.goto(BASE + cloud, { waitUntil: "load" });
    const bad = await page.evaluate(() => {
      const out = [];
      for (const c of document.querySelectorAll(".docs-table td code")) {
        const rects = [...c.getClientRects()];
        if (new Set(rects.map((x) => Math.round(x.top))).size < 2) continue;
        // find every line break inside the code by walking characters
        const walker = document.createTreeWalker(c, NodeFilter.SHOW_TEXT); let n, prevTop = null, prev = "";
        while ((n = walker.nextNode())) for (let i = 0; i < n.length; i++) {
          const rg = document.createRange(); rg.setStart(n, i); rg.setEnd(n, i + 1);
          const rr = rg.getClientRects()[0]; if (!rr) continue;
          const top = Math.round(rr.top);
          if (prevTop !== null && top > prevTop + 4 && !/[\/._\-:=?&,|\s]/.test(prev)) out.push(`${c.textContent.slice(0, 40)} breaks after "${prev}"`);
          prevTop = top; prev = n.data[i];
        }
      }
      return out;
    });
    ok(bad.length === 0, `docs ${w}: long tokens in tables break only after separator characters`, bad.slice(0, 4).join(" | "));
  }

  // restack on phones
  await page.setViewport({ width: 390, height: 900 });
  await page.goto(BASE + "/docs/concepts/manifests", { waitUntil: "load" });
  const st = await page.evaluate(() => [...document.querySelectorAll(".docs-table table")].map((t) => ({ cols: t.rows[0]?.cells.length, tdDisplay: getComputedStyle(t.querySelector("td")).display, label: getComputedStyle(t.querySelector("td"), "::before").content })));
  ok(st.length > 0 && st.filter((t) => t.cols >= 3).every((t) => t.tdDisplay === "block" && t.label !== "none"), "docs 390: tables with 3+ columns restack into labelled rows", JSON.stringify(st.slice(0, 3)));

  // code block: wrapped, and copy gives the original text
  await page.goto(BASE + "/docs/more/testing", { waitUntil: "load" });
  const cb = await page.evaluate(() => {
    const pres = [...document.querySelectorAll(".code-block pre")];
    return pres.map((p) => ({ ws: getComputedStyle(p.querySelector("code") || p).whiteSpace, sw: p.scrollWidth, cw: p.clientWidth,  }));
  });
  ok(cb.length > 0 && cb.every((b) => b.ws === "pre-wrap" && b.sw <= b.cw + 1), "docs 390: code blocks wrap (pre-wrap) and never scroll", JSON.stringify(cb.filter((b) => b.sw > b.cw + 1 || b.ws !== "pre-wrap").slice(0, 2)).slice(0, 200));
  const copied = await page.evaluate(async () => {
    const sent = [];
    Object.defineProperty(navigator, "clipboard", { value: { writeText: async (t) => { sent.push(t); } }, configurable: true });
    const blocks = [...document.querySelectorAll(".code-block")];
    const exp = blocks.map((b) => b.querySelector("pre").textContent.replace(/\n$/, ""));
    for (const b of blocks) { b.querySelector(".code-copy").click(); await new Promise((r) => setTimeout(r, 30)); }
    return { sent, exp };
  });
  ok(copied.sent.length > 0 && copied.sent.every((t, i) => t === copied.exp[i]), "docs: Copy puts the original unwrapped text on the clipboard (one line per source line)", JSON.stringify(copied.sent.find((t, i) => t !== copied.exp[i])));

  if (SHOTS) {
    const { mkdirSync } = await import("node:fs"); mkdirSync(SHOTS, { recursive: true });
    for (const w of [1440, 390]) {
      await page.setViewport({ width: w, height: 1000 });
      await page.goto(BASE + cloud, { waitUntil: "load" });
      const tbl = await page.evaluateHandle(() => { let n = document.getElementById("endpoints-all-on-the-relays-origin"); while (n && !n.matches(".docs-table")) n = n.nextElementSibling; return n; });
      const el = tbl.asElement();
      if (el) { await el.screenshot({ path: `${SHOTS}/endpoints-${w}.png` }); }
      const cbEl = await page.$(".code-block");
      if (cbEl) await cbEl.screenshot({ path: `${SHOTS}/code-${w}.png` });
    }
  }
} finally {
  await browser.close();
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
