import fs from "node:fs";
import path from "node:path";
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
  const hasShots = {
    light: fs.existsSync(path.join(pub, "designer-light.png")),
    dark: fs.existsSync(path.join(pub, "designer-dark.png")),
  };
  return (
    <>
      <Header downloadUrl={release.dmgUrl} />
      <main>
        <Hero release={release} />
        <Why />
        <Flow />
        <Designer hasShots={hasShots} />
        <Actions />
        <Living />
        <CloudRelay />
        <Agents />
        <Integrate />
        <Download release={release} />
        <ChangelogPreview />
      </main>
      <Footer />
    </>
  );
}
