import { Download as DownloadIcon } from "lucide-react";
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

function Slot({ name }: { name: string }) {
  return <span className="slot" aria-hidden>{name}</span>;
}

export default function Download({ release }: { release: ReleaseInfo }) {
  return (
    <section id="download" className="section blueprint">
      <div className="shell g">
        <div className="cell dl-cell dl-icon" data-filled="false">
          <Slot name="icon" />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={asset("/herald-icon.png")} srcSet={`${asset("/herald-icon.png")} 512w, ${asset("/herald-icon-1024.webp")} 1024w`} sizes="(min-width: 1024px) 340px, (min-width: 640px) 26vw, 42vw" alt="" width={512} height={512} loading="lazy" />
        </div>
        <div className="cell dl-cell dl-title" data-filled="false">
          <Slot name="title" />
          <h2 className="display display-l">Ready when you are.</h2>
          <p className="body m-0 mt-5">
            {nowrapText("Free and open source. Signed with a Developer ID and notarized by Apple.")} Menu-bar app, no account, nothing leaves your Mac.
          </p>
        </div>

        <div className="cell dl-cell dl-fill dl-version" data-filled="false">
          <Slot name="version" />
          <p className="display dl-num">{release.version}</p>
          <p className="mono dl-cap">
            <span className="nowrap">build {release.build} · {isoDate(release.date)}</span>
          </p>
        </div>
        <div className="cell dl-cell dl-fill dl-size" data-filled="false">
          <Slot name="size" />
          <p className="display dl-num dl-num-size">≈ {release.sizeMB} MB</p>
          <p className="mono dl-cap">DMG</p>
        </div>
        <div className="cell dl-cell dl-fill dl-sha" data-filled="false">
          <Slot name="sha" />
          {release.sha256 ? <ShaCopy sha={release.sha256} href={release.shaUrl} /> : <span className="mono text-muted">SHA-256 is listed with the release.</span>}
        </div>

        <div className="cell dl-cell dl-reqs" data-filled="false">
          <Slot name="requirements" />
          <ul className="m-0 list-none border-t border-line p-0 text-[15px]">
            {REQS.map((r) => (
              <li key={r} className="border-b border-line py-3">{nowrapText(r)}</li>
            ))}
          </ul>
        </div>
        <div className="cell dl-cell dl-actions" data-filled="false">
          <Slot name="actions" />
          <SiteLink href={release.dmgUrl} className="btn btn-primary dl-dl">
            <DownloadIcon aria-hidden className="size-[18px] shrink-0" />
            Download for Mac · DMG · ≈ {release.sizeMB} MB
          </SiteLink>
          <SiteLink href={RELEASES_URL} className="btn btn-ghost">All releases on GitHub</SiteLink>
        </div>
      </div>
    </section>
  );
}
