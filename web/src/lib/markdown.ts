import { decodeEntities } from "./entities";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkRehype from "remark-rehype";
import rehypeSlug from "rehype-slug";
import rehypeAutolinkHeadings from "rehype-autolink-headings";
import rehypeHighlight from "rehype-highlight";
import { visit } from "unist-util-visit";
import { toString } from "hast-util-to-string";
import type { Root, Element } from "hast";

export interface Heading {
  depth: number;
  text: string;
  id: string;
}

interface MdHeading {
  line: number;
  level: number;
  text: string;
}

function scan(lines: string[]): MdHeading[] {
  const out: MdHeading[] = [];
  let fence: string | null = null;
  lines.forEach((l, i) => {
    const f = l.match(/^\s*(```+|~~~+)/);
    if (f) {
      if (!fence) fence = f[1][0];
      else if (f[1][0] === fence) fence = null;
      return;
    }
    if (fence) return;
    const h = l.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/);
    if (h) out.push({ line: i, level: h[1].length, text: h[2].trim() });
  });
  return out;
}

/** Whole file minus its H1, or only the named headings (with their sub-sections). */
export function sliceMarkdown(src: string, names?: string[]): string {
  const lines = src.split("\n");
  const heads = scan(lines);
  const h1 = heads.find((h) => h.level === 1);
  if (!names) {
    if (h1) lines.splice(h1.line, 1);
    return lines.join("\n").trim();
  }
  const chunks: string[] = [];
  for (const name of names) {
    if (name === "intro") {
      const start = h1 ? h1.line + 1 : 0;
      const next = heads.find((h) => h.line >= start && h !== h1);
      chunks.push(lines.slice(start, next ? next.line : lines.length).join("\n").trim());
      continue;
    }
    const idx = heads.findIndex((h) => h.level >= 2 && h.text === name);
    if (idx < 0) throw new Error(`docs: heading "${name}" not found`);
    const h = heads[idx];
    const end = heads.slice(idx + 1).find((x) => x.level <= h.level);
    let chunk = lines.slice(h.line, end ? end.line : lines.length);
    const rel = scan(chunk);
    if (names.length === 1) {
      // A page cut from one section: the page title replaces its heading, sub-sections move up a level.
      chunk = chunk.slice(1);
      for (const x of rel.filter((r) => r.line > 0)) {
        const level = Math.max(2, x.level - h.level + 1);
        chunk[x.line - 1] = chunk[x.line - 1].replace(/^#{1,6}/, "#".repeat(level));
      }
    } else if (h.level > 2) {
      // Several sections on one page: each cut starts at h2.
      for (const x of rel) {
        const level = Math.max(2, x.level - h.level + 2);
        chunk[x.line] = chunk[x.line].replace(/^#{1,6}/, "#".repeat(level));
      }
    }
    chunks.push(chunk.join("\n").trim());
  }
  return chunks.filter(Boolean).join("\n\n");
}

export function firstParagraph(md: string): string {
  const para: string[] = [];
  let fence = false;
  let block = false;
  for (const l of md.split("\n")) {
    if (/^\s*```/.test(l)) fence = !fence;
    if (fence || /^\s*```/.test(l)) continue;
    if (!l.trim()) {
      if (para.length) break;
      block = false;
      continue;
    }
    if (/^(#|\||>|-|\*|\d+\.|<)/.test(l.trim())) {
      if (para.length) break;
      block = true;
      continue;
    }
    if (block && !para.length) continue; // continuation of a list item or table row
    para.push(l.trim());
  }
  const text = para
    .join(" ")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[`*_]/g, "")
    .replace(/\s+/g, " ");
  return text.length > 200 ? text.slice(0, 197).replace(/\s+\S*$/, "") + "…" : text;
}

function rehypeHeadings() {
  return (tree: Root, file: { data: Record<string, unknown> }) => {
    const heads: Heading[] = [];
    visit(tree, "element", (el: Element) => {
      if (/^h[2-3]$/.test(el.tagName) && el.properties?.id) {
        heads.push({ depth: Number(el.tagName[1]), text: decodeEntities(toString(el).replace(/#$/, "").trim()), id: String(el.properties.id) });
      }
    });
    file.data.headings = heads;
  };
}

function rehypeCodeMeta() {
  return (tree: Root) => {
    visit(tree, "element", (el: Element) => {
      if (el.tagName !== "pre") return;
      const code = el.children.find((c): c is Element => c.type === "element" && c.tagName === "code");
      el.properties = el.properties || {};
      el.properties["dataRaw"] = toString(el).replace(/\n$/, "");
      const cls = (code?.properties?.className as string[] | undefined) || [];
      const lang = cls.find((c) => c.startsWith("language-"));
      if (lang) el.properties["dataLang"] = lang.slice(9);
    });
  };
}

export type LinkResolver = (href: string) => string | null;

function rehypeLinks(resolve?: LinkResolver) {
  return (tree: Root) => {
    if (!resolve) return;
    visit(tree, "element", (el: Element) => {
      if (el.tagName !== "a" || typeof el.properties?.href !== "string") return;
      const next = resolve(el.properties.href);
      if (next) el.properties.href = next;
    });
  };
}

/** Pass 1: slug + collect headings (no highlighting). Pass 2: full render tree. */
export function headingsOf(md: string): Heading[] {
  const proc = unified().use(remarkParse).use(remarkGfm).use(remarkRehype).use(rehypeSlug).use(rehypeHeadings);
  const file = { data: {} as Record<string, unknown> };
  const tree = proc.parse(md);
  proc.runSync(tree, file as never);
  return (file.data.headings as Heading[]) ?? [];
}

/** Prefixes heading ids (and their anchors) so several documents can share one page. */
function rehypeIdPrefix(prefix?: string) {
  return (tree: Root) => {
    if (!prefix) return;
    visit(tree, "element", (el: Element) => {
      if (!/^h[1-6]$/.test(el.tagName) || !el.properties?.id) return;
      const id = `${prefix}${el.properties.id}`;
      el.properties.id = id;
      for (const c of el.children) {
        if (c.type === "element" && c.tagName === "a" && Array.isArray(c.properties?.className) && c.properties.className.includes("anchor")) {
          c.properties.href = `#${id}`;
        }
      }
    });
  };
}

export function renderTree(md: string, resolve?: LinkResolver, idPrefix?: string): Root {
  const proc = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkRehype)
    .use(rehypeSlug)
    .use(rehypeAutolinkHeadings, {
      behavior: "append",
      properties: { className: ["anchor"], ariaLabel: "Link to this section" },
      content: { type: "text", value: "#" },
    })
    .use(rehypeIdPrefix, idPrefix)
    .use(rehypeCodeMeta)
    .use(rehypeHighlight, { detect: false, ignoreMissing: true })
    .use(rehypeLinks, resolve);
  const tree = proc.parse(md);
  return proc.runSync(tree) as Root;
}
