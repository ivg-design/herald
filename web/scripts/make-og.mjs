// Renders public/og.png (1200x630) via headless Chrome. Usage: node scripts/make-og.mjs
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const tmp = process.env.OG_TMP || join(process.env.TMPDIR || "/tmp", "herald-og");
mkdirSync(tmp, { recursive: true });
const uri = (f) => `data:${f.endsWith(".svg") ? "image/svg+xml" : "image/png"};base64,${readFileSync(join(root, "public", f)).toString("base64")}`;
const html = `<!doctype html><html><head><meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=DM+Sans:wght@400;500&display=swap" rel="stylesheet">
<style>
*{box-sizing:border-box;margin:0}
body{width:1200px;height:630px;background:#0F1317;position:relative;overflow:hidden;font-family:'DM Sans',sans-serif;color:#F4F1EA}
.grid{position:absolute;inset:0}
.grid i{position:absolute;background:#2A323B;opacity:.6}
.logo{position:absolute;left:72px;top:56px;height:150px;width:auto}
.icon{position:absolute;right:72px;top:72px;width:88px;height:88px;border-radius:20px}
h1{position:absolute;left:72px;top:230px;font-family:'Instrument Serif',serif;font-weight:400;font-size:112px;line-height:1.02;letter-spacing:-0.01em}
h1 em{color:#3B9BE8}
.tag{position:absolute;left:72px;bottom:56px;font-size:26px;color:#9AA6B2}
</style></head><body>
<div class="grid"><i style="left:300px;top:0;width:1px;height:630px"></i><i style="left:600px;top:0;width:1px;height:630px"></i><i style="left:900px;top:0;width:1px;height:630px"></i><i style="top:210px;left:0;height:1px;width:1200px"></i><i style="top:420px;left:0;height:1px;width:1200px"></i></div>
<img class="logo" src="${uri("herald-logo.svg")}"><img class="icon" src="${uri("herald-icon.png")}">
<h1>Notifications<br><em>you'd actually design.</em></h1>
<div class="tag">Herald · a notification service for macOS</div>
</body></html>`;
const file = join(tmp, "og.html");
writeFileSync(file, html);
const out = join(root, "public", "og.png");
execFileSync("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
  "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=8000",
  `--screenshot=${out}`, "--window-size=1200,630", `file://${file}`,
], { stdio: "ignore" });
console.log("wrote", out);
