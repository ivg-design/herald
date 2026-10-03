import type { Metadata, Viewport } from "next";
import { Archivo, Fragment_Mono } from "next/font/google";
import StructuredData from "@/components/StructuredData";
import { SITE_URL, asset } from "@/lib/config";
import "./globals.css";

const archivo = Archivo({ variable: "--font-archivo", subsets: ["latin"], axes: ["wdth"], display: "swap" });
const fragment = Fragment_Mono({ variable: "--font-fragment", weight: "400", subsets: ["latin"], display: "swap" });

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

export const viewport: Viewport = { themeColor: "#f4f6fa", width: "device-width", initialScale: 1 };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${archivo.variable} ${fragment.variable}`}>
      <body>
        {children}
        <StructuredData />
      </body>
    </html>
  );
}
