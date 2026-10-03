import type { ComponentProps, ReactNode } from "react";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
import { toJsxRuntime } from "hast-util-to-jsx-runtime";
import { toString } from "hast-util-to-string";
import type { Root, Element, Text, ElementContent } from "hast";
import SiteLink from "@/components/SiteLink";
import { renderTree, type LinkResolver } from "@/lib/markdown";
import CodeBlock from "./CodeBlock";

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
  // 3+ columns, or 2 columns with long cells, restack on phones; 5+ columns restack up to laptop widths (see docs.css).
  const stack = head.length >= 5 ? "wide" : head.length >= 3 || longest > 60 ? "phone" : "";
  table.properties = { ...table.properties, dataCols: head.length, ...(stack ? { dataStack: stack } : {}) };
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

function structure(parent: Root | Element) {
  for (const c of parent.children as ElementContent[]) {
    if (c.type !== "element") continue;
    if (c.tagName === "table") tableNode(c);
    else if (c.tagName === "pre") codeNode(c);
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
