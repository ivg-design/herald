import type { ComponentProps, ReactNode } from "react";
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
import { toJsxRuntime } from "hast-util-to-jsx-runtime";
import type { Root } from "hast";
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

export function renderHast(tree: Root): ReactNode {
  return toJsxRuntime(tree, { Fragment, jsx, jsxs, components, passNode: false });
}

/** Markdown to React with the docs component map (code blocks with copy, tables in scrollers, safe links). */
export function renderMarkdown(md: string, resolve?: LinkResolver, idPrefix?: string): ReactNode {
  return renderHast(renderTree(md, resolve, idPrefix));
}
