import { ArrowUpRight } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { parseChangelog } from "@/lib/changelog";

export default async function ChangelogPreview() {
  const entries = parseChangelog().slice(0, 3);
  return (
    <section id="changelog" className="section section-dark">
      <div className="shell">
        <p className="eyebrow">Recent updates</p>
        <ul className="m-0 mt-6 list-none p-0">
          {entries.map((e) => (
            <li key={e.version} className="grid gap-1 border-b border-line py-5 md:grid-cols-[96px_120px_1fr] md:items-baseline md:gap-6 first:border-t">
              <span className="mono text-[15px] font-bold">{e.version}</span>
              <span className="mono text-[12.5px] text-muted">{e.date}</span>
              <span className="text-[15px] text-muted">{e.summary}</span>
            </li>
          ))}
        </ul>
        <SiteLink href="/changelog" className="mt-6 inline-flex min-h-10 items-center gap-1 text-[15px] font-medium text-accent hover:underline underline-offset-4">
          Full changelog <ArrowUpRight aria-hidden className="size-4" />
        </SiteLink>
      </div>
    </section>
  );
}
