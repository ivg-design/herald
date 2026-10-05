import type { MetadataRoute } from "next";
import { absolute } from "@/lib/config";
import { getPages } from "@/lib/docs";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  const fixed = ["/", "/changelog", "/docs", "/privacy", "/terms"];
  return [
    ...fixed.map((p) => ({ url: absolute(p), lastModified: now, priority: p === "/" ? 1 : 0.8 })),
    ...getPages().map((d) => ({ url: absolute(d.href), lastModified: now, priority: 0.6 })),
  ];
}
