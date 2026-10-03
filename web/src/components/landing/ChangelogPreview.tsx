import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { parseChangelog } from "@/lib/changelog";
import SectionHead from "./SectionHead";

export default async function ChangelogPreview() {
  const entries = parseChangelog().slice(0, 3);
  return (
    <section id="changelog" className="section">
      <div className="shell g">
        <SectionHead
          title="What changed."
          titleCols="lg:col-span-8"
          asideSlot="link"
          asideCols="lg:col-span-4"
          aside={
            <SiteLink href="/changelog" className="inline-flex min-h-10 items-center text-[16px] font-medium text-accent-text underline underline-offset-4">
              Full changelog
            </SiteLink>
          }
        />
        <ul className="col-span-full m-0 list-none border-t border-line p-0">
          {entries.map((e) => (
            <li key={e.version} className="g items-baseline border-b border-line py-6">
              <span
                className="display col-span-full min-w-0 text-[clamp(22px,2.4vw,34px)] lg:col-span-3"
                style={{ fontVariationSettings: '"wdth" 132', letterSpacing: "-0.035em" }}
              >
                {nowrapText(e.version)}
              </span>
              <span className="mono col-span-full text-muted lg:col-span-2">{e.date}</span>
              <span className="col-span-full min-w-0 text-[16px] text-muted lg:col-span-7">{nowrapText(e.summary)}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
