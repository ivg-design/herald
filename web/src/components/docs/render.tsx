import type { ComponentProps, ReactNode } from "react";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
import { toJsxRuntime } from "hast-util-to-jsx-runtime";
import { toString } from "hast-util-to-string";
import type { Root, Element, Text, ElementContent } from "hast";
import SiteLink from "@/components/SiteLink";
import { renderTree, type LinkResolver } from "@/lib/markdown";
import CodeBlock from "./CodeBlock";
import Figure from "./Figure";
import { asset } from "@/lib/config";
import { HOTSPOTS, shotName, shots } from "@/lib/figures";

function DocLink({ href, children, ...rest }: ComponentProps<"a">) {
  const h = href ?? "";
  // Unresolved relative links stay plain anchors; routes, anchors and absolute URLs go through SiteLink.
  if (!/^(https?:|mailto:|#|\/)/.test(h)) return <a href={h} {...rest}>{children}</a>;
  return (
    <SiteLink href={h} {...(rest as object)}>
      {children}
    </SiteLink>
  );
}

/** Tables fit their container (never a scroller). Wide ones restack into labelled rows on phones, see docs.css. */
function DocTable({ children, ...rest }: ComponentProps<"table">) {
  return (
    <div className="docs-table">
      <table {...rest}>{children}</table>
    </div>
  );
}

function DocImage({ src, alt }: { src?: string | Blob; alt?: string }) {
  if (typeof src !== "string" || !/^https?:\/\//.test(src)) return alt ? <span className="docs-img-alt">{alt}</span> : null;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt={alt ?? ""} loading="lazy" decoding="async" />;
}

const components = {
  "doc-figure": Figure,
  pre: CodeBlock,
  a: DocLink,
  table: DocTable,
  img: DocImage,
} as never;

const NOWRAP = new RegExp(
  [
    "IVG Design", "Claude Code", "Claude Desktop", "Codex CLI", "Apple Silicon", "SF Symbols", "Notification Center",
    "Apple Shortcuts?", "Developer ID",
    String.raw`\b\d+\.\d+\.\d+(?: \(Build \d+\))?`,
    String.raw`\bBuild \d+`,
    String.raw`[\u2318\u21e7\u2325\u2303]+[A-Z0-9]`,
    String.raw`macOS \d+(?:\.\d+)?\+?`,
  ].join("|"),
  "g",
);

/** Wrap proper nouns, versions and key combos in <span class="nowrap"> (never inside code/pre). */
function nowrapNode(parent: Root | Element) {
  const out: ElementContent[] = [];
  for (const c of parent.children as ElementContent[]) {
    if (c.type === "element") {
      if (c.tagName !== "code" && c.tagName !== "pre") nowrapNode(c);
      out.push(c);
    } else if (c.type === "text") {
      let last = 0;
      for (const m of c.value.matchAll(NOWRAP)) {
        if (m.index > last) out.push({ type: "text", value: c.value.slice(last, m.index) } as Text);
        out.push({ type: "element", tagName: "span", properties: { className: ["nowrap"] }, children: [{ type: "text", value: m[0] }] });
        last = m.index + m[0].length;
      }
      out.push(last ? ({ type: "text", value: c.value.slice(last) } as Text) : c);
    } else out.push(c);
  }
  parent.children = out as never;
}

const SEP = /([/._\-:=?&,|]+)/;
const LONG_TOKEN = 18;

/** Inline code in a table cell: tokens up to LONG_TOKEN characters stay whole (nowrap); longer ones get <wbr> after separators. */
function breakCode(code: Element) {
  const text = toString(code);
  if (text.length <= LONG_TOKEN) {
    code.properties = { ...code.properties, className: ["tok"] };
    return;
  }
  code.properties = { ...code.properties, className: ["tok", "tok-long"] };
  const out: ElementContent[] = [];
  const walk = (nodes: ElementContent[]) => {
    for (const n of nodes) {
      if (n.type === "text") {
        n.value.split(SEP).forEach((part, i) => {
          if (!part) return;
          out.push({ type: "text", value: part } as Text);
          if (i % 2 === 1) out.push({ type: "element", tagName: "wbr", properties: {}, children: [] });
        });
      } else out.push(n);
    }
  };
  walk(code.children as ElementContent[]);
  code.children = out as never;
}

function cellsOf(row: Element): Element[] {
  return row.children.filter((c): c is Element => c.type === "element" && (c.tagName === "td" || c.tagName === "th"));
}

function tableNode(table: Element) {
  const rows: Element[] = [];
  const collect = (n: Element) => {
    for (const c of n.children) {
      if (c.type !== "element") continue;
      if (c.tagName === "tr") rows.push(c);
      else collect(c);
    }
  };
  collect(table);
  const head = rows[0] ? cellsOf(rows[0]).map((c) => toString(c).trim()) : [];
  let longest = 0;
  for (const r of rows.slice(1)) {
    cellsOf(r).forEach((cell, i) => {
      if (head[i]) cell.properties = { ...cell.properties, dataLabel: head[i] };
      longest = Math.max(longest, toString(cell).length);
    });
  }
  const lower = head.map((h) => h.toLowerCase());
  const kind = ["status"].includes(lower[0]) ? "errors"
    : ["key", "setting"].includes(lower[0]) ? "keys"
    : ["name", "field", "argument", "property", "option", "parameter"].includes(lower[0]) ? "params"
    : "";
  const typeCol = lower.indexOf("type"), reqCol = lower.indexOf("required");
  for (const r of rows.slice(1)) {
    const cells = cellsOf(r);
    if (typeCol >= 0 && cells[typeCol]) cells[typeCol].properties = { ...cells[typeCol].properties, className: ["cell-type"] };
    const rc = reqCol >= 0 ? cells[reqCol] : undefined;
    if (rc) {
      const v = toString(rc).trim().toLowerCase();
      if (v === "yes" || v === "required") {
        rc.children = [{ type: "element", tagName: "span", properties: { className: ["req"] }, children: [{ type: "text", value: "required" }] }] as never;
      } else if (v === "no" || v === "optional" || v === "") {
        rc.children = [{ type: "element", tagName: "span", properties: { className: ["opt"] }, children: [{ type: "text", value: "optional" }] }] as never;
      }
      rc.properties = { ...rc.properties, className: ["cell-req"] };
    }
  }
  // 3+ columns, or 2 columns with long cells, restack on phones; 5+ columns restack up to laptop widths (see docs.css).
  const stack = head.length >= 5 ? "wide" : head.length >= 3 || longest > 60 ? "phone" : "";
  table.properties = { ...table.properties, dataCols: head.length, ...(kind ? { dataKind: kind } : {}), ...(stack ? { dataStack: stack } : {}) };
  const codes = (n: Element) => {
    for (const c of n.children) {
      if (c.type !== "element") continue;
      if (c.tagName === "code") breakCode(c);
      else if (c.tagName !== "pre") codes(c);
    }
  };
  codes(table);
}

/** Splits highlighted code into one block span per source line, so a wrapped line hangs under its own start. */
function lineSplit(nodes: ElementContent[]): ElementContent[][] {
  const lines: ElementContent[][] = [[]];
  for (const n of nodes) {
    if (n.type === "text") {
      const parts = n.value.split("\n");
      parts.forEach((part, i) => {
        if (i > 0) lines.push([]);
        if (part) lines[lines.length - 1].push({ type: "text", value: part } as Text);
      });
    } else if (n.type === "element") {
      const sub = lineSplit(n.children as ElementContent[]);
      sub.forEach((kids, i) => {
        if (i > 0) lines.push([]);
        if (kids.length) lines[lines.length - 1].push({ ...n, children: kids } as Element);
      });
    }
  }
  return lines;
}

function codeNode(pre: Element) {
  const code = pre.children.find((c): c is Element => c.type === "element" && c.tagName === "code");
  if (!code) return;
  const lines = lineSplit(code.children as ElementContent[]);
  if (lines.length && !lines[lines.length - 1].length) lines.pop(); // trailing newline
  code.children = lines.map((kids) => ({
    type: "element",
    tagName: "span",
    properties: { className: ["cl"] },
    children: [...kids, { type: "text", value: "\n" }],
  })) as never;
}

const METHOD_PATH = /^(GET|POST|PUT|DELETE|PATCH)\s+(\/\S*)$/;
/** Bold one-line paragraphs that label a part of a reference block (docs/STYLE.md). */
const LABELS = new Set([
  "Request", "Example request", "Example response", "Response fields", "Errors", "Notes", "Arguments", "Example call",
  "Example result", "HTTP route", "Side effects", "Options", "Example", "Output", "Exit status", "Minimal example",
  "Realistic example", "Properties", "Example event", "Headers", "Result fields",
]);
const CALLOUT = /^\s*\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION)\]\s*/i;
const CALLOUT_KIND: Record<string, string> = { note: "note", tip: "tip", warning: "warning", important: "note", caution: "warning" };

function els(parent: Root | Element): Element[] {
  return (parent.children as ElementContent[]).filter((c): c is Element => c.type === "element");
}

/** `### \`GET /v1/health\`` becomes a method badge and a mono path; a heading that is only code is set in mono. */
function headingNode(h: Element) {
  const kids = (h.children as ElementContent[]).filter((c) => !(c.type === "element" && c.tagName === "a" && (c.properties?.className as string[] | undefined)?.includes("anchor")));
  const solid = kids.filter((c) => !(c.type === "text" && !c.value.trim()));
  if (solid.length !== 1 || solid[0].type !== "element" || solid[0].tagName !== "code") return;
  const text = toString(solid[0]).trim();
  const m = text.match(METHOD_PATH);
  const cls = ((h.properties?.className as string[] | undefined) ?? []).slice();
  if (!m) {
    h.properties = { ...h.properties, className: [...cls, "code-heading"] };
    return;
  }
  const anchor = (h.children as ElementContent[]).filter((c) => !kids.includes(c));
  const path: ElementContent[] = [];
  m[2].split(/([/?&{}]+)/).forEach((part, i) => {
    if (!part) return;
    if (i % 2 === 1 && path.length) path.push({ type: "element", tagName: "wbr", properties: {}, children: [] });
    path.push({ type: "text", value: part } as Text);
  });
  h.properties = { ...h.properties, className: [...cls, "ep"], dataMethod: m[1] };
  h.children = [
    { type: "element", tagName: "span", properties: { className: ["ep-method"], dataMethod: m[1] }, children: [{ type: "text", value: m[1] }] },
    { type: "text", value: " " },
    { type: "element", tagName: "span", properties: { className: ["ep-path"] }, children: path },
    ...anchor,
  ] as never;
}

function labelOf(p: Element): string | null {
  if (p.tagName !== "p") return null;
  const solid = (p.children as ElementContent[]).filter((c) => !(c.type === "text" && !c.value.trim()));
  if (solid.length !== 1 || solid[0].type !== "element" || solid[0].tagName !== "strong") return null;
  const t = toString(solid[0]).trim();
  return LABELS.has(t) ? t : null;
}

/** `> [!NOTE]` (GitHub alert syntax) becomes a callout; a plain blockquote stays a quotation. */
function calloutNode(bq: Element) {
  const first = els(bq)[0];
  if (!first || first.tagName !== "p") return;
  const lead = first.children[0];
  if (!lead || lead.type !== "text") return;
  const m = lead.value.match(CALLOUT);
  if (!m) return;
  const kind = CALLOUT_KIND[m[1].toLowerCase()] ?? "note";
  lead.value = lead.value.slice(m[0].length);
  if (!lead.value && first.children[1]?.type === "element" && (first.children[1] as Element).tagName === "br") first.children.splice(0, 2);
  if (!first.children.length) bq.children = bq.children.filter((c) => c !== first);
  bq.tagName = "aside";
  bq.properties = { className: ["callout"], dataKind: kind, role: "note", ariaLabel: kind };
  bq.children = [
    { type: "element", tagName: "p", properties: { className: ["callout-label"], ariaHidden: "true" }, children: [{ type: "text", value: kind }] },
    { type: "element", tagName: "div", properties: { className: ["callout-body"] }, children: bq.children },
  ] as never;
}

/** Labels: a label followed by a code block becomes that block's title; two titled examples in a row are paired. */
function labels(parent: Root | Element) {
  const out: ElementContent[] = [];
  const kids = parent.children as ElementContent[];
  const nextEl = (from: number) => {
    for (let j = from; j < kids.length; j++) {
      const k = kids[j];
      if (k.type === "element") return j;
      if (k.type === "text" && k.value.trim()) return -1;
    }
    return -1;
  };
  for (let i = 0; i < kids.length; i++) {
    const c = kids[i];
    if (c.type !== "element") { out.push(c); continue; }
    const label = labelOf(c);
    if (!label) { out.push(c); continue; }
    const j = nextEl(i + 1);
    const next = j >= 0 ? (kids[j] as Element) : null;
    if (next && next.tagName === "pre") {
      next.properties = { ...next.properties, dataTitle: label };
      const prev = out[out.length - 1];
      if (label === "Example response" || label === "Example result" || label === "Output") {
        if (prev && prev.type === "element" && prev.tagName === "div" && (prev.properties?.className as string[] | undefined)?.includes("example-pair") && prev.children.length === 1) {
          prev.children.push(next);
          i = j;
          continue;
        }
      }
      if (label === "Example request" || label === "Example call" || label === "Example") {
        out.push({ type: "element", tagName: "div", properties: { className: ["example-pair"] }, children: [next] });
        i = j;
        continue;
      }
      out.push(next);
      i = j;
      continue;
    }
    c.properties = { ...c.properties, className: ["docs-label"] };
    c.children = [{ type: "text", value: label }] as never;
    out.push(c);
  }
  parent.children = out as never;
}

/** A paragraph that holds one docs screenshot becomes a figure: sized from the manifest, captioned by the image title. */
function figures(parent: Root | Element) {
  const kids = parent.children as ElementContent[];
  kids.forEach((c, i) => {
    if (c.type !== "element" || c.tagName !== "p") return;
    const solid = (c.children as ElementContent[]).filter((x) => !(x.type === "text" && !x.value.trim()));
    if (solid.length !== 1 || solid[0].type !== "element" || solid[0].tagName !== "img") return;
    const img = solid[0];
    const name = shotName(String(img.properties?.src ?? ""));
    if (!name) return;
    const all = shots();
    const shot = all.get(name);
    const darkName = name.replace(/(\.[a-z0-9]+)$/i, "-dark$1");
    const spots = HOTSPOTS[name];
    if (spots) {
      const next = kids.slice(i + 1).find((x) => x.type === "element") as Element | undefined;
      if (next && next.tagName === "ol") next.properties = { ...next.properties, className: ["figure-legend"] };
    }
    kids[i] = {
      type: "element",
      tagName: "doc-figure",
      properties: {
        dataFigure: JSON.stringify({
          src: asset(`/shots/docs/${name}`),
          src2x: shot?.file2x ? asset(`/shots/docs/${shot.file2x.replace(/^.*\//, "")}`) : undefined,
          darkSrc2x: all.get(darkName)?.file2x ? asset(`/shots/docs/${all.get(darkName)!.file2x!.replace(/^.*\//, "")}`) : undefined,
          darkSrc: all.has(darkName) ? asset(`/shots/docs/${darkName}`) : undefined,
          alt: String(img.properties?.alt ?? ""),
          caption: img.properties?.title ? String(img.properties.title) : undefined,
          width: shot?.width,
          height: shot?.height,
          hotspots: spots,
        }),
      },
      children: [],
    } as never;
  });
}

function structure(parent: Root | Element) {
  labels(parent);
  figures(parent);
  for (const c of parent.children as ElementContent[]) {
    if (c.type !== "element") continue;
    if (c.tagName === "table") tableNode(c);
    else if (c.tagName === "pre") codeNode(c);
    else if (/^h[2-6]$/.test(c.tagName)) headingNode(c);
    else if (c.tagName === "blockquote") { calloutNode(c); structure(c); }
    else structure(c);
  }
}

export function renderHast(tree: Root): ReactNode {
  structure(tree);
  nowrapNode(tree);
  return toJsxRuntime(tree, { Fragment, jsx, jsxs, components, passNode: false });
}

/** Markdown to React with the docs component map (code blocks with copy, tables that fit and restack, safe links). */
export function renderMarkdown(md: string, resolve?: LinkResolver, idPrefix?: string): ReactNode {
  return renderHast(renderTree(md, resolve, idPrefix));
}
