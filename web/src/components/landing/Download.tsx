import Image from "next/image";
import { ArrowUpRight, Check, Download as DownloadIcon } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { asset, RELEASES_URL } from "@/lib/config";
import { monthYear, type ReleaseInfo } from "@/lib/release";

const REQS = [
  "macOS 13.1 Ventura or later · Apple Silicon",
  "Optional: Kokoro voice (≈ 340 MB download, local, resumable)",
  "Optional: Shortcuts, Reminders access when you use those actions",
];

export default function Download({ release }: { release: ReleaseInfo }) {
  const link = "inline-flex min-h-10 items-center gap-1 text-[14px] text-muted hover:text-ink transition-colors duration-200";
  return (
    <section id="download" className="section section-accent">
      <div className="shell grid items-center gap-12 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,420px)] lg:gap-16">
        <div>
          <h2 className="display text-[clamp(52px,8vw,96px)] !text-accent-ink">Ready when you are.</h2>
          <p className="mt-6 mb-0 max-w-[56ch] text-[clamp(16px,1.4vw,18px)] leading-relaxed">
            {nowrapText("Free and open source. Signed with a Developer ID and notarized by Apple.")} Menu-bar app, no account, nothing leaves your Mac.
          </p>
          <ul className="m-0 mt-6 flex list-none flex-col gap-2 p-0 text-[14px]">
            {REQS.map((r) => (
              <li key={r} className="flex items-start gap-2.5">
                <Check aria-hidden className="mt-0.5 size-4 shrink-0" />
                {nowrapText(r)}
              </li>
            ))}
          </ul>
        </div>
        <div className="rounded-2xl bg-surface p-6 text-ink">
          <Image src={asset("/herald-icon.png")} alt="" width={64} height={64} unoptimized className="rounded-[14px]" />
          <p className="mono mt-4 mb-0 text-[12px] font-semibold tracking-wide text-muted">
            <span className="nowrap">Herald {release.version} · Build {release.build} · {monthYear(release.date)}</span>
          </p>
          <SiteLink href={release.dmgUrl} className="btn btn-primary mt-5 !h-[52px] w-full !text-[16px]">
            <DownloadIcon aria-hidden className="size-[18px]" />
            Download for Mac · DMG · ≈ {release.sizeMB} MB
          </SiteLink>
          <div className="mt-4 flex flex-col">
            <span className="flex flex-wrap items-center gap-x-3">
              {release.shaUrl ? <SiteLink href={release.shaUrl} className={link}>SHA-256 checksum</SiteLink> : <span className={link}>SHA-256 checksum</span>}
              {release.sha256 && <span className="mono text-[12px] text-muted" title={release.sha256}>{release.sha256.slice(0, 12)}…</span>}
            </span>
            <SiteLink href={RELEASES_URL} className={link}>All releases on GitHub <ArrowUpRight aria-hidden className="size-3.5" /></SiteLink>
          </div>
        </div>
      </div>
    </section>
  );
}
