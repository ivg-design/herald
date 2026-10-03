import { absolute, asset } from "@/lib/config";
import { getRelease } from "@/lib/release";

export default async function StructuredData() {
  const rel = await getRelease();
  const graph = [
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: "Herald",
      description: "A notification service for macOS. Any app declares the data it can send; you design the banner on a grid of any size.",
      applicationCategory: "UtilitiesApplication",
      operatingSystem: "macOS 13.1+",
      softwareVersion: rel.version,
      downloadUrl: rel.dmgUrl,
      image: absolute(asset("/herald-icon.png")),
      license: "https://opensource.org/licenses/MIT",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      author: { "@type": "Organization", name: "IVG Design" },
    },
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      name: "Herald",
      url: absolute("/"),
    },
  ];
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(graph).replace(/</g, "\\u003c") }} />;
}
