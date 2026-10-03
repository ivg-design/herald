import Image from "next/image";
import { Check, Download as DownloadIcon } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { asset, RELEASES_URL } from "@/lib/config";
import { type ReleaseInfo } from "@/lib/release";
import { ShaCopy } from "./b-code-tabs";

const REQS = [
  "macOS 13.1 Ventura or later · Apple Silicon",
  "Optional: Kokoro voice (≈ 340 MB download, local, resumable)",
  "Optional: Shortcuts, Reminders access when you use those actions",
];

function isoDate(d: string): string {
  return /^\d{4}-\d{2}-\d{2}/.test(d) ? d.slice(0, 10) : d;
}

export default function Download({ release }: { release: ReleaseInfo }) {
  return (
    <section id="download" className="section">
      <div className="shell g">
        <h2 className="display display-l col-span-full lg:col-span-7">Ready when you are.</h2>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-6">
          <p className="body m-0">
            {nowrapText("Free and open source. Signed with a Developer ID and notarized by Apple.")} Menu-bar app, no account, nothing leaves your Mac.
          </p>
          <ul className="m-0 mt-6 flex list-none flex-col gap-3 p-0 text-[15px]">
            {REQS.map((r) => (
              <li key={r} className="flex items-start gap-3">
                <Check aria-hidden className="mt-[3px] size-4 shrink-0 text-accent" />
                <span>{nowrapText(r)}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-5 lg:col-start-8">
          <Image src={asset("/herald-icon.png")} alt="" width={64} height={64} unoptimized className="rounded-[14px]" />
          <p className="mono m-0 mt-4">
            <span className="nowrap">Herald {release.version} · Build {release.build} · {isoDate(release.date)}</span>
          </p>
          <SiteLink href={release.dmgUrl} className="btn btn-primary mt-5 !h-[52px] max-w-full !px-5 !text-[16px]">
            <DownloadIcon aria-hidden className="size-[18px] shrink-0" />
            Download for Mac · DMG · ≈ {release.sizeMB} MB
          </SiteLink>
          <div className="mt-5 flex flex-col gap-1">
            {release.sha256 && <ShaCopy sha={release.sha256} href={release.shaUrl} />}
            <SiteLink href={RELEASES_URL} className="inline-flex min-h-10 items-center text-[15px] text-accent-text underline-offset-4 hover:underline">
              All releases on GitHub
            </SiteLink>
          </div>
        </div>
      </div>
    </section>
  );
}
