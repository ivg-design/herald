// Structure lint for the docs Markdown (docs/STYLE.md). Runs without a server, on the repository's own files.
// Usage: node scripts/test-docs-structure.mjs [file.md ...]     (no arguments: README, clients/README, docs/**)
//
// Fails on:
//   - a paragraph or list item with more than one `METHOD /path` code span
//   - a code span that is a pseudo-JSON or pseudo-query signature ({"a"|"b"}, key?, {"app","id"}, ?app=&name=)
//   - an endpoint heading with no fenced example before the next heading of the same or a higher level
//   - a fenced block without a language; a `json` block that is not valid JSON
//   - a skipped heading level; more than one H1
//   - a table row with an unescaped pipe inside inline code
//   - a relative link whose file or anchor does not exist
//   - an image without alt text, or whose file does not exist
//   - a page about something the user sees (Designer, Settings, History, banners) with no figure
//   - version-history wording (new in 1.2, previously, no longer ...) and version numbers
//   - an em dash; the name of an individual dot or a private project
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import GithubSlugger from "github-slugger";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "..", "..");

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) {
      if (!["__pycache__", "assets", "screenshots", "node_modules"].includes(name)) walk(p, out);
    } else if (name.endsWith(".md")) out.push(p);
  }
  return out;
}

const args = process.argv.slice(2).map((a) => resolve(a));
const all = [join(repo, "README.md"), join(repo, "clients", "README.md"), ...walk(join(repo, "docs"))];
const files = args.length ? args : all;

/** Pages that must show what they describe. Others qualify by their title (see needsFigure). */
const MUST_HAVE_FIGURE = new Set(["docs/AUTHORING.md", "docs/APP.md", "docs/CLOUD.md", "docs/reference/banners.md"]);
const FIGURE_TITLE = /\b(designer|settings|history|banners?)\b/i;
/** Reference pages whose title names the topic but which document an API, not a screen. */
const FIGURE_EXEMPT = /^docs\/reference\/(api|mcp)\//;

const METHOD_SPAN = /^(GET|POST|PUT|DELETE|PATCH)(\s*[,|/]\s*(GET|POST|PUT|DELETE|PATCH))*\s+\/\S*/;
const VERSION_HISTORY = [
  [/\b(new|added|changed|introduced|since|as of)\s+(in\s+)?(herald\s+)?v?\d+\.\d+/i, "version-history wording"],
  [/\bherald\s+\d+\.\d+(\.\d+)?\s+(additions|changes|adds|added|introduced)\b/i, "version-history wording"],
  [/\bwhat'?s new\b/i, "version-history wording"],
  [/\b(previously|used to|no longer|formerly|deprecated|legacy)\b/i, "history wording (describe the product as it is)"],
  [/\b(herald|version|v)\s?\d+\.\d+(\.\d+)?\b/i, "a version number"],
  [/\(\d+\.\d+(\.\d+)?\)/, "a version number"],
];
/** Lines where a version or one of the words above is the data itself. */
const VERSION_ALLOW = [
  /macOS \d+/i,
  /layoutVersion/,
  /protocol/i,
  /MCP-Protocol-Version|protocolVersion/,
  /"version"\s*:/,
  /RFC \d+/,
  /OAuth 2\.\d/i,
  /User-Agent|Herald-Agent\/|Python-urllib/,
  /TLS \d|HTTP\/\d/,
  /Accepted older forms/i,
];

const problems = [];
const report = (file, line, msg) => problems.push(`${relative(repo, file)}:${line}: ${msg}`);

/** Lines with their kind: "code" (inside a fence), "fence", or "text". */
function classify(lines) {
  const kinds = [];
  let fence = null;
  lines.forEach((l, i) => {
    const m = l.match(/^(\s*)(`{3,}|~{3,})(.*)$/);
    if (m && !fence) {
      fence = { mark: m[2][0], len: m[2].length, line: i, info: m[3].trim() };
      kinds.push("fence");
    } else if (m && fence && m[2][0] === fence.mark && m[2].length >= fence.len && !m[3].trim()) {
      fence = null;
      kinds.push("fence");
    } else kinds.push(fence ? "code" : "text");
  });
  return kinds;
}

function codeSpans(text) {
  const out = [];
  const re = /(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g;
  let m;
  while ((m = re.exec(text))) out.push(m[2]);
  return out;
}

function stripCode(text) {
  return text.replace(/(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g, "`x`");
}

const anchorCache = new Map();
function anchorsOf(file) {
  if (anchorCache.has(file)) return anchorCache.get(file);
  const set = new Set();
  if (existsSync(file)) {
    const lines = readFileSync(file, "utf8").split("\n");
    const kinds = classify(lines);
    const slugger = new GithubSlugger();
    lines.forEach((l, i) => {
      if (kinds[i] !== "text") return;
      const h = l.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/);
      if (h) set.add(slugger.slug(h[2].replace(/\[([^\]]+)\]\([^)]*\)/g, "$1").replace(/[`*]/g, "")));
    });
  }
  anchorCache.set(file, set);
  return set;
}

function lintFile(file) {
  const rel = relative(repo, file);
  const src = readFileSync(file, "utf8");
  const lines = src.split("\n");
  const kinds = classify(lines);
  const isStyle = rel === "docs/STYLE.md";

  // ---- fences: language, valid JSON
  let open = null;
  lines.forEach((l, i) => {
    if (kinds[i] !== "fence") return;
    if (!open) {
      const info = l.replace(/^\s*(`{3,}|~{3,})/, "").trim();
      open = { line: i, lang: info.split(/\s+/)[0] };
      if (!info) report(file, i + 1, "fenced block without a language");
    } else {
      if (open.lang === "json" && !isStyle) {
        const body = lines.slice(open.line + 1, i).join("\n");
        try { JSON.parse(body); } catch (e) { report(file, open.line + 1, `json block is not valid JSON (${String(e.message).slice(0, 70)})`); }
      }
      open = null;
    }
  });
  if (isStyle) { links(file, lines, kinds); return; }

  // ---- headings: order, single H1, endpoint headings need an example
  const heads = [];
  lines.forEach((l, i) => {
    if (kinds[i] !== "text") return;
    const h = l.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/);
    if (h) heads.push({ line: i, level: h[1].length, text: h[2] });
  });
  let prev = 0;
  let h1 = 0;
  for (const h of heads) {
    if (h.level === 1) h1++;
    if (prev && h.level > prev + 1) report(file, h.line + 1, `heading level skipped (h${prev} to h${h.level}): ${h.text}`);
    prev = h.level;
  }
  if (h1 > 1) report(file, 1, "more than one H1");
  if (h1 === 0) report(file, 1, "no H1 title");
  heads.forEach((h, n) => {
    const t = h.text.replace(/^`|`$/g, "");
    if (!/^(GET|POST|PUT|DELETE|PATCH)\s+\//.test(t)) return;
    if (/[,|]| and /.test(t.replace(/\{[^}]*\}/g, ""))) report(file, h.line + 1, `one endpoint per heading: ${h.text}`);
    const next = heads.slice(n + 1).find((x) => x.level <= h.level);
    const end = next ? next.line : lines.length;
    let has = false;
    for (let i = h.line + 1; i < end; i++) if (kinds[i] === "fence") { has = true; break; }
    if (!has) report(file, h.line + 1, `endpoint heading without a fenced example: ${h.text}`);
  });

  // ---- blocks: paragraphs and list items
  let block = [];
  let start = 0;
  const flush = () => {
    if (!block.length) return;
    const text = block.join("\n");
    const isTable = block.every((b) => /^\s*\|/.test(b));
    if (!isTable) {
      const eps = codeSpans(text).filter((c) => METHOD_SPAN.test(c.trim()));
      if (eps.length > 1) report(file, start + 1, `${eps.length} endpoints in one paragraph (${eps.slice(0, 3).join("; ")}): one block per endpoint`);
    }
    block = [];
  };
  lines.forEach((l, i) => {
    if (kinds[i] !== "text") { flush(); return; }
    if (!l.trim() || /^#{1,6}\s/.test(l)) { flush(); return; }
    if (/^\s*([-*+]|\d+\.)\s/.test(l)) flush();
    if (!block.length) start = i;
    block.push(l);
  });
  flush();

  // ---- per line: pseudo signatures, table pipes, em dashes, version history
  lines.forEach((l, i) => {
    if (kinds[i] !== "text") return;
    for (const c of codeSpans(l)) {
      const pseudo =
        /\{[^}]*\w\?\s*[,}:]/.test(c) || // {"name?", ...}  {key?: ...}
        /"\s*\|\s*"/.test(c) || // "a"|"b"
        /\{\s*"[^"]+"\s*[,}]/.test(c) || // {"app","id"}
        /\{\s*[A-Za-z_]+\s*,\s*[A-Za-z_]+/.test(c) || // {key, group, type}
        /\?[A-Za-z_]+=(&|\[|\]|$)/.test(c) || // ?app=&name=
        /\[[&?][A-Za-z_]+=?\]/.test(c) || // [&path=]
        /(^|[\s{,(\["])[A-Za-z_]+\?(:|,|\}|\)|$)/.test(c); // key? outside an object
      if (pseudo) report(file, i + 1, `pseudo-signature in a code span: \`${c.slice(0, 60)}\` (use a table and a real example)`);
    }
    if (/^\s*\|/.test(l)) {
      let inCode = false;
      for (let k = 0; k < l.length; k++) {
        if (l[k] === "`") inCode = !inCode;
        else if (l[k] === "|" && inCode && l[k - 1] !== "\\") { report(file, i + 1, "unescaped | inside inline code in a table row (write \\|)"); break; }
      }
    }
    if (/dotcliff/i.test(l)) report(file, i + 1, "names an individual dot (write \"a dot\", \"your dot\")");
    if (/bidbot[ -]relay/i.test(l)) report(file, i + 1, "names a private project");
    const prose = stripCode(l);
    if (prose.includes("—")) report(file, i + 1, "em dash (use a colon, a comma or a new sentence)");
    if (!VERSION_ALLOW.some((re) => re.test(l))) {
      const bare = prose.replace(/\]\([^)]*\)/g, "]").replace(/https?:\/\/\S+/g, "");
      for (const [re, why] of VERSION_HISTORY) {
        const m = bare.match(re);
        if (m) { report(file, i + 1, `${why}: "${m[0]}"`); break; }
      }
    }
  });

  links(file, lines, kinds);

  // ---- figures
  const title = heads.find((h) => h.level === 1)?.text ?? "";
  const needsFigure = MUST_HAVE_FIGURE.has(rel) || (FIGURE_TITLE.test(title) && !FIGURE_EXEMPT.test(rel));
  if (needsFigure && !/!\[[^\]]*\]\([^)]+\)/.test(lines.filter((_, i) => kinds[i] === "text").join("\n"))) {
    report(file, 1, "this page describes something the user sees and has no figure");
  }
}

function links(file, lines, kinds) {
  const dir = dirname(file);
  lines.forEach((l, i) => {
    if (kinds[i] !== "text") return;
    const text = stripCode(l);
    const re = /(!?)\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g;
    let m;
    while ((m = re.exec(text))) {
      const [, bang, label, href] = m;
      if (/^(https?:|mailto:|tel:)/.test(href)) continue;
      const [pathPart, hash] = href.split("#");
      const target = pathPart ? resolve(dir, decodeURIComponent(pathPart)) : file;
      if (bang) {
        if (!label.trim()) report(file, i + 1, `image without alt text: ${href}`);
        if (!existsSync(target)) report(file, i + 1, `image file does not exist: ${href}`);
        continue;
      }
      if (!existsSync(target)) { report(file, i + 1, `link target does not exist: ${href}`); continue; }
      if (hash && target.endsWith(".md") && !anchorsOf(target).has(hash)) report(file, i + 1, `no heading for anchor #${hash} in ${relative(repo, target)}`);
    }
  });
}

for (const f of files) {
  if (!existsSync(f)) { problems.push(`${f}: no such file`); continue; }
  lintFile(f);
}

// The name of an individual dot must not appear in site copy or client code either (docs/STYLE.md, Language).
if (!args.length) {
  const walkAll = (dir, out = []) => {
    if (!existsSync(dir)) return out;
    for (const name of readdirSync(dir)) {
      const p = join(dir, name);
      if (statSync(p).isDirectory()) { if (!["node_modules", "__pycache__"].includes(name)) walkAll(p, out); }
      else if (/\.(tsx?|css|mjs|js|py|md|json)$/.test(name)) out.push(p);
    }
    return out;
  };
  for (const f of [...walkAll(join(repo, "web", "src")), ...walkAll(join(repo, "clients")), ...walkAll(join(repo, "web", "content"))]) {
    readFileSync(f, "utf8").split("\n").forEach((l, i) => {
      if (/dotcliff/i.test(l)) report(f, i + 1, "names an individual dot");
      if (/bidbot[ -]relay/i.test(l)) report(f, i + 1, "names a private project");
    });
  }
}

if (problems.length) {
  for (const p of problems) console.log(p);
  console.log(`\n${problems.length} problem${problems.length === 1 ? "" : "s"} in ${new Set(problems.map((p) => p.split(":")[0])).size} file(s); ${files.length} checked`);
  process.exit(1);
}
console.log(`docs structure: ${files.length} files, no problems`);
