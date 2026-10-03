import type { Metadata } from "next";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import { renderMarkdown } from "@/components/docs/render";
import "@/components/docs/docs.css";
import { parseChangelog } from "@/lib/changelog";
import { makeResolver } from "@/lib/docs";
import { getRelease } from "@/lib/release";
import { absolute } from "@/lib/config";

export const metadata: Metadata = {
  title: "Changelog",
  description: "Every Herald release, newest first: what was added, changed and fixed.",
  alternates: { canonical: "/changelog" },
  openGraph: { title: "Herald changelog", description: "Every Herald release, newest first.", url: absolute("/changelog"), type: "website", siteName: "Herald" },
};

function fmt(date: string): string {
  const d = new Date(`${date}T12:00:00Z`);
  return Number.isNaN(d.getTime()) ? date : d.toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });
}

export default async function ChangelogPage() {
  const release = await getRelease();
  const entries = parseChangelog();
  const resolve = makeResolver("CHANGELOG.md");
  return (
    <>
      <Header downloadUrl={release.dmgUrl} />
      <main id="main" className="shell">
        <header className="pt-[clamp(48px,8vw,96px)] pb-[clamp(32px,5vw,56px)]">
          <h1 className="display display-l">Changelog</h1>
          <p className="body m-0 mt-5">What changed in each version, newest first.</p>
        </header>
        <ol className="m-0 list-none p-0 pb-[clamp(64px,9vw,112px)]">
          {entries.map((e) => {
            const id = `v${e.version.replace(/\./g, "-")}`;
            return (
              <li key={e.version} id={id} className="scroll-mt-[88px] border-t border-line py-9 md:grid md:grid-cols-[220px_minmax(0,1fr)] md:gap-x-12 md:py-12">
                <div className="md:sticky md:top-24 md:self-start">
                  <h2 className="display display-m">
                    <a href={`#${id}`}>{e.version}</a>
                  </h2>
                  <p className="mono m-0 mt-2.5 mb-6 flex flex-wrap gap-x-4 gap-y-1 text-muted md:mb-0 md:flex-col">
                    {e.build && <span className="nowrap">Build {e.build}</span>}
                    {e.date && <time dateTime={e.date}>{fmt(e.date)}</time>}
                  </p>
                </div>
                <div className="docs-prose body min-w-0 max-w-[760px] !text-ink">{renderMarkdown(e.body, resolve, `${id}-`)}</div>
              </li>
            );
          })}
        </ol>
      </main>
      <Footer />
    </>
  );
}
