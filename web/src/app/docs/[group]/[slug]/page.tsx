import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { ArrowLeft, ArrowRight, Pencil } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import Toc from "@/components/docs/Toc";
import { renderHast } from "@/components/docs/render";
import { getPage, getPages, renderPageTree } from "@/lib/docs";
import { absolute, asset } from "@/lib/config";

export const dynamicParams = false;

export function generateStaticParams() {
  return getPages().map((p) => ({ group: p.groupId, slug: p.slug }));
}

type Params = { group: string; slug: string };

export async function generateMetadata({ params }: { params: Promise<Params> }): Promise<Metadata> {
  const { group, slug } = await params;
  const page = getPage(group, slug);
  if (!page) return {};
  const title = `${page.title} | Herald docs`;
  return {
    title: { absolute: title },
    description: page.description,
    alternates: { canonical: page.href },
    openGraph: {
      title,
      description: page.description,
      type: "article",
      url: absolute(page.href),
      siteName: "Herald",
      images: [{ url: asset("/og.png"), width: 1200, height: 630, alt: "Herald" }],
    },
    twitter: { card: "summary_large_image", title, description: page.description, images: [asset("/og.png")] },
  };
}

export default async function DocPageRoute({ params }: { params: Promise<Params> }) {
  const { group, slug } = await params;
  const page = getPage(group, slug);
  if (!page) notFound();
  const pages = getPages();
  const i = pages.findIndex((p) => p === page);
  const prev = pages[i - 1];
  const next = pages[i + 1];
  const body = renderHast(renderPageTree(page));

  return (
    <div className={`docs-grid${page.headings.length ? "" : " docs-grid--solo"}`}>
      <article className="docs-article">
        <nav aria-label="Breadcrumb" className="docs-crumbs">
          <span>{page.group}</span>
          <span aria-hidden>&rsaquo;</span>
          <span aria-current="page">{page.title}</span>
        </nav>
        <h1 className="display docs-h1">{page.title}</h1>
        {page.note && <p className="docs-note">{page.note}</p>}
        <div className="docs-prose">{body}</div>

        {page.editUrl && (
          <p className="docs-edit">
            <a href={page.editUrl} target="_blank" rel="noopener noreferrer">
              <Pencil size={14} aria-hidden /> Edit this page on GitHub
            </a>
          </p>
        )}

        <nav aria-label="Previous and next page" className="docs-pager">
          {prev ? (
            <SiteLink href={prev.href} rel="prev" className="docs-pager-prev">
              <span className="docs-pager-label"><ArrowLeft size={14} aria-hidden /> Previous</span>
              <span className="docs-pager-title">{prev.title}</span>
            </SiteLink>
          ) : <span />}
          {next ? (
            <SiteLink href={next.href} rel="next" className="docs-pager-next">
              <span className="docs-pager-label">Next <ArrowRight size={14} aria-hidden /></span>
              <span className="docs-pager-title">{next.title}</span>
            </SiteLink>
          ) : <span />}
        </nav>
      </article>
      {page.headings.length > 0 && (
        <aside className="docs-rail" aria-label="Page outline">
          <Toc headings={page.headings} />
        </aside>
      )}
    </div>
  );
}
