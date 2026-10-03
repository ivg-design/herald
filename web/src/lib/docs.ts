import { readFileSync } from "node:fs";
import { join, posix } from "node:path";
import { DOC_TREE, ISSUE_URL } from "./docs-tree";
import { firstParagraph, headingsOf, renderTree, sliceMarkdown, type Heading, type LinkResolver } from "./markdown";
import type { Root } from "hast";
import { REPO_URL } from "./config";

export interface DocPage {
  group: string;
  groupId: string;
  slug: string;
  title: string;
  href: string; // /docs/<group>/<slug>
  file: string; // repo-relative source file ("" for hand-written pages)
  source: string; // sourced Markdown, ready to render
  description: string;
  headings: Heading[];
  note?: string;
  editUrl: string | null;
}

let cache: DocPage[] | null = null;

const REPORT_ISSUE_MD = `Found a bug, a gap in these docs, or a banner that does not look the way you designed it?

Open an issue and include:

- the Herald version (Settings > About) and your macOS version,
- the request you sent (\`herald send ...\` or the JSON), with the token removed,
- what you expected and what you saw; a screenshot of the banner helps.

The docs on this site are the repository's own Markdown, so a fix to a page is a pull request against \`docs/\`.

[Open an issue](${ISSUE_URL}) · [Browse open issues](${REPO_URL}/issues) · [Discussions](${REPO_URL}/discussions)
`;

export function getPages(): DocPage[] {
  if (cache) return cache;
  const root = join(process.cwd(), "content");
  const files = new Map<string, string>();
  const read = (f: string) => {
    if (!files.has(f)) files.set(f, readFileSync(join(root, f), "utf8"));
    return files.get(f)!;
  };
  const pages: DocPage[] = [];
  for (const g of DOC_TREE) {
    for (const e of g.items) {
      const source = e.file ? sliceMarkdown(read(e.file), e.slice) : REPORT_ISSUE_MD;
      pages.push({
        group: g.title,
        groupId: g.id,
        slug: e.slug,
        title: e.title,
        href: `/docs/${g.id}/${e.slug}`,
        file: e.file,
        source,
        description: e.description || firstParagraph(source) || e.title,
        headings: headingsOf(source),
        note: e.note,
        editUrl: e.file ? `${REPO_URL}/blob/main/${e.file}` : null,
      });
    }
  }
  cache = pages;
  return pages;
}

export function getPage(groupId: string, slug: string): DocPage | undefined {
  return getPages().find((p) => p.groupId === groupId && p.slug === slug);
}

/** Resolves a Markdown link found in `fromFile` to a docs route, a GitHub blob URL, or leaves it alone. */
export function makeResolver(fromFile: string): LinkResolver {
  const pages = getPages();
  return (href) => {
    if (/^(https?:|mailto:|tel:)/.test(href)) return null;
    const [pathPart, hash = ""] = href.split("#");
    const frag = hash ? `#${hash}` : "";
    if (!pathPart) {
      // In-page anchor: if the heading lives in another page cut from the same file, point there.
      const here = pages.find((p) => p.file === fromFile && p.headings.some((h) => h.id === hash));
      return here ? `${here.href}${frag}` : null;
    }
    const target = posix.normalize(posix.join(posix.dirname(fromFile), pathPart)).replace(/^\.\//, "");
    if (target.endsWith(".md")) {
      const same = pages.filter((p) => p.file === target);
      const byHeading = hash ? same.find((p) => p.headings.some((h) => h.id === hash)) : undefined;
      const hit = byHeading ?? same[0];
      if (hit) return `${hit.href}${byHeading ? frag : ""}`;
    }
    if (target.startsWith("..")) return null;
    return `${REPO_URL}/blob/main/${target.replace(/\/$/, "")}`;
  };
}

export function renderPageTree(page: DocPage): Root {
  return renderTree(page.source, makeResolver(page.file));
}

/** Flat search index: titles and headings only. */
export interface SearchItem {
  title: string;
  group: string;
  href: string;
  heading?: string;
}
export function searchIndex(): SearchItem[] {
  const out: SearchItem[] = [];
  for (const p of getPages()) {
    out.push({ title: p.title, group: p.group, href: p.href });
    for (const h of p.headings) out.push({ title: p.title, group: p.group, href: `${p.href}#${h.id}`, heading: h.text });
  }
  return out;
}
