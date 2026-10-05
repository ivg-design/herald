import type { ReactNode } from "react";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import "@/components/docs/docs.css";
import { getRelease } from "@/lib/release";

/** The shell of the two legal pages (Privacy Policy, Terms of Use): site header, a title, prose, site footer. */
export default async function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
  const release = await getRelease();
  return (
    <>
      <Header downloadUrl={release.dmgUrl} />
      <main id="main" className="shell">
        <header className="pt-[clamp(48px,8vw,96px)] pb-[clamp(24px,4vw,40px)]">
          <h1 className="display display-l">{title}</h1>
          <p className="mono m-0 mt-5 text-muted">Last updated {updated}</p>
        </header>
        <div className="docs-prose body min-w-0 max-w-[760px] pb-[clamp(64px,9vw,112px)] !text-ink">{children}</div>
      </main>
      <Footer />
    </>
  );
}
