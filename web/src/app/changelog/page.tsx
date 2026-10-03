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
      <main id="main" className="shell changelog">
        <header className="changelog-head">
          <p className="eyebrow">Releases</p>
          <h1 className="display">Changelog</h1>
          <p className="lede">What changed in each version, newest first.</p>
        </header>
        <ol className="changelog-list">
          {entries.map((e) => {
            const id = `v${e.version.replace(/\./g, "-")}`;
            return (
              <li key={e.version} id={id} className="changelog-entry">
                <div className="changelog-rail">
                  <h2>
                    <a href={`#${id}`}>{e.version}</a>
                  </h2>
                  <p>
                    {e.build && <span>Build {e.build}</span>}
                    {e.date && <time dateTime={e.date}>{fmt(e.date)}</time>}
                  </p>
                </div>
                <div className="docs-prose changelog-body">{renderMarkdown(e.body, resolve, `${id}-`)}</div>
              </li>
            );
          })}
        </ol>
      </main>
      <Footer />
    </>
  );
}
