import type { MetadataRoute } from "next";
import { absolute } from "@/lib/config";

export const dynamic = "force-static";

export default function robots(): MetadataRoute.Robots {
  return { rules: { userAgent: "*", allow: "/" }, sitemap: absolute("/sitemap.xml") };
}
