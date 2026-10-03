import Header from "@/components/Header";
import Footer from "@/components/Footer";
import SiteLink from "@/components/SiteLink";
import { getRelease } from "@/lib/release";

export const metadata = { title: "Not found" };

export default async function NotFound() {
  const release = await getRelease();
  return (
    <>
      <Header downloadUrl={release.dmgUrl} />
      <main id="main" className="section">
        <div className="shell g">
          <div className="cell col-span-full min-w-0 lg:col-span-8" data-filled="false" style={{ padding: "30px 16px 16px" }}>
            <span className="slot" aria-hidden>title</span>
            <h1 className="display display-l">Nothing at this address.</h1>
          </div>
          <div className="cell col-span-full min-w-0 lg:col-span-6" data-filled="false" style={{ padding: "30px 16px 16px" }}>
            <span className="slot" aria-hidden>body</span>
            <p className="body m-0">The page you asked for does not exist, or it moved.</p>
            <p className="m-0 mt-5 flex flex-wrap gap-x-6 gap-y-2 text-[17px] font-medium">
              <SiteLink href="/" className="inline-flex min-h-10 items-center text-accent-text underline underline-offset-4">Home</SiteLink>
              <SiteLink href="/docs" className="inline-flex min-h-10 items-center text-accent-text underline underline-offset-4">Docs</SiteLink>
            </p>
          </div>
        </div>
      </main>
      <Footer />
    </>
  );
}
