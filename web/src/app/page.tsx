import fs from "node:fs";
import path from "node:path";
import { HeraldHost } from "@/components/herald/HeraldHost";
import PageStack from "@/components/herald/PageStack";
import EasterEgg from "@/components/motion/EasterEgg";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import Hero from "@/components/landing/Hero";
import Why from "@/components/landing/Why";
import Flow from "@/components/landing/Flow";
import Designer from "@/components/landing/Designer";
import Actions from "@/components/landing/Actions";
import Living from "@/components/landing/Living";
import CloudRelay from "@/components/landing/CloudRelay";
import Agents from "@/components/landing/Agents";
import Integrate from "@/components/landing/Integrate";
import Download from "@/components/landing/Download";
import ChangelogPreview from "@/components/landing/ChangelogPreview";
import { getRelease } from "@/lib/release";

export default async function Home() {
  const release = await getRelease();
  const pub = path.join(process.cwd(), "public");
  const manifest = path.join(pub, "shots", "manifest.json");
  const dims: Record<string, { w: number; h: number }> = fs.existsSync(manifest) ? JSON.parse(fs.readFileSync(manifest, "utf8")) : {};
  const shots = { light: dims["designer-light"], dark: dims["designer-dark"] };
  return (
    <>
      <HeraldHost>
      <Header downloadUrl={release.dmgUrl} />
      <main>
        <Hero release={release} />
        <Why />
        <Flow />
        <Designer shots={shots} />
        <Actions />
        <Living />
        <CloudRelay />
        <Agents />
        <Integrate />
        <Download release={release} />
        <ChangelogPreview />
      </main>
      <PageStack />
      <EasterEgg />
      </HeraldHost>
      <Footer />
    </>
  );
}
