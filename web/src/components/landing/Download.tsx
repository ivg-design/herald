import Image from "next/image";
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

const CELL = { padding: "30px 16px 16px" } as const;

function Slot({ name }: { name: string }) {
  return <span className="slot" aria-hidden>{name}</span>;
}

export default function Download({ release }: { release: ReleaseInfo }) {
  return (
    <section id="download" className="section blueprint">
      <div className="shell g">
        <div className="cell col-span-full sm:col-span-2 lg:col-span-2" data-filled="false" style={CELL}>
          <Slot name="icon" />
          <span className="grid size-[88px] place-items-center rounded-[22px] bg-white">
            <Image src={asset("/herald-logo.svg")} alt="" width={60} height={60} unoptimized />
          </span>
        </div>
        <div className="cell col-span-full min-w-0 sm:col-span-4 lg:col-span-10" data-filled="false" style={CELL}>
          <Slot name="title" />
          <h2 className="display display-l">Ready when you are.</h2>
          <p className="body m-0 mt-5">
            {nowrapText("Free and open source. Signed with a Developer ID and notarized by Apple.")} Menu-bar app, no account, nothing leaves your Mac.
          </p>
        </div>

        <div className="cell col-span-full min-w-0 sm:col-span-3 lg:col-span-5" data-filled="false" style={CELL}>
          <Slot name="version" />
          <p className="display m-0 text-[clamp(52px,7vw,104px)]" style={{ fontVariationSettings: '"wdth" 132', letterSpacing: "-0.04em" }}>{release.version}</p>
          <p className="mono m-0 mt-3 text-muted">
            <span className="nowrap">build {release.build} · {isoDate(release.date)}</span>
          </p>
        </div>
        <div className="cell col-span-full min-w-0 sm:col-span-3 lg:col-span-3" data-filled="false" style={CELL}>
          <Slot name="size" />
          <p className="display display-m m-0">≈ {release.sizeMB} MB</p>
          <p className="mono m-0 mt-3 text-muted">DMG</p>
        </div>
        <div className="cell col-span-full min-w-0 lg:col-span-4" data-filled="false" style={CELL}>
          <Slot name="sha" />
          {release.sha256 ? <ShaCopy sha={release.sha256} href={release.shaUrl} /> : <span className="mono text-muted">SHA-256 is listed with the release.</span>}
        </div>

        <div className="cell col-span-full min-w-0 lg:col-span-7" data-filled="false" style={CELL}>
          <Slot name="requirements" />
          <ul className="m-0 list-none border-t border-line p-0 text-[15px]">
            {REQS.map((r) => (
              <li key={r} className="border-b border-line py-3">{nowrapText(r)}</li>
            ))}
          </ul>
        </div>
        <div className="cell col-span-full min-w-0 lg:col-span-5" data-filled="false" style={CELL}>
          <Slot name="actions" />
          <SiteLink href={release.dmgUrl} className="btn btn-primary !h-[52px] max-w-full !px-5 !text-[16px]">
            <DownloadIcon aria-hidden className="size-[18px] shrink-0" />
            Download for Mac · DMG · ≈ {release.sizeMB} MB
          </SiteLink>
          <div className="mt-4">
            <SiteLink href={RELEASES_URL} className="btn btn-ghost">All releases on GitHub</SiteLink>
          </div>
        </div>
      </div>
    </section>
  );
}
