import type { Metadata, Viewport } from "next";
import { Instrument_Serif, DM_Sans, JetBrains_Mono } from "next/font/google";
import StructuredData from "@/components/StructuredData";
import { SITE_URL, asset } from "@/lib/config";
import "./globals.css";

const instrument = Instrument_Serif({ variable: "--font-instrument", weight: "400", style: ["normal", "italic"], subsets: ["latin"], display: "swap" });
const dmSans = DM_Sans({ variable: "--font-dm-sans", subsets: ["latin"], display: "swap" });
const jetbrains = JetBrains_Mono({ variable: "--font-jetbrains", subsets: ["latin"], display: "swap" });

const TITLE = "Herald: notifications you'd actually design";
const DESC =
  "A notification service for macOS. Any app declares the data it can send; you design the banner on a grid of any size, with history, sound and two-way actions. Free and open source.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: TITLE, template: "%s | Herald" },
  description: DESC,
  applicationName: "Herald",
  keywords: ["macOS notifications", "notification service", "Growl alternative", "custom notification banners", "macOS menu bar app", "agent notifications", "MCP", "open source"],
  robots: { index: true, follow: true },
  authors: [{ name: "IVG Design" }],
  icons: { icon: asset("/icon.png"), apple: asset("/herald-icon.png") },
  openGraph: { title: TITLE, description: DESC, type: "website", siteName: "Herald", images: [{ url: asset("/og.png"), width: 1200, height: 630, alt: "Herald: notifications you'd actually design" }] },
  twitter: { card: "summary_large_image", title: TITLE, description: DESC, images: [asset("/og.png")] },
  alternates: { canonical: "/" },
};

export const viewport: Viewport = { themeColor: "#0f1317", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${instrument.variable} ${dmSans.variable} ${jetbrains.variable}`}>
      <body>
        {children}
        <StructuredData />
      </body>
    </html>
  );
}
