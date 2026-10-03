import type { ComponentProps, ReactNode } from "react";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
import { toJsxRuntime } from "hast-util-to-jsx-runtime";
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

function DocTable({ children }: { children?: ReactNode }) {
  return (
    <div className="docs-table" tabIndex={0} role="region" aria-label="Table, scrolls horizontally">
      <table>{children}</table>
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

export function renderHast(tree: Root): ReactNode {
  nowrapNode(tree);
  return toJsxRuntime(tree, { Fragment, jsx, jsxs, components, passNode: false });
}

/** Markdown to React with the docs component map (code blocks with copy, tables in scrollers, safe links). */
export function renderMarkdown(md: string, resolve?: LinkResolver, idPrefix?: string): ReactNode {
  return renderHast(renderTree(md, resolve, idPrefix));
}
