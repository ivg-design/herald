import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { parseChangelog } from "@/lib/changelog";

export default async function ChangelogPreview() {
  const entries = parseChangelog().slice(0, 3);
  return (
    <section id="changelog" className="section">
      <div className="shell">
        <ul className="m-0 list-none p-0">
          {entries.map((e) => (
            <li key={e.version} className="g border-t border-line py-5 last:border-b">
              <span className="mono col-span-2 text-ink">{nowrapText(e.version)}</span>
              <span className="mono col-span-2 text-muted">{e.date}</span>
              <span className="col-span-full text-[15px] text-muted md:col-span-8 md:col-start-5">{nowrapText(e.summary)}</span>
            </li>
          ))}
        </ul>
        <SiteLink href="/changelog" className="mt-6 inline-flex min-h-10 items-center text-[15px] font-medium text-accent-text underline-offset-4 hover:underline">
          Full changelog
        </SiteLink>
      </div>
    </section>
  );
}
