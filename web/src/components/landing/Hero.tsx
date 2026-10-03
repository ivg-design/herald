import Image from "next/image";
import { Download } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import BannerStack from "@/components/motion/BannerStack";
import { asset } from "@/lib/config";
import type { ReleaseInfo } from "@/lib/release";

const GHOST = { background: "var(--line)", opacity: 0.45 } as const;

/** Decorative hairlines: 3 vertical + 3 horizontal, pure CSS. */
function GhostGrid() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden">
      {[25, 50, 75].map((x) => (
        <span key={`v${x}`} className="absolute inset-y-0 w-px" style={{ left: `${x}%`, ...GHOST }} />
      ))}
      {[28, 52, 78].map((y) => (
        <span key={`h${y}`} className="absolute inset-x-0 h-px" style={{ top: `${y}%`, ...GHOST }} />
      ))}
    </div>
  );
}

export default function Hero({ release }: { release: ReleaseInfo }) {
  return (
    <section
      id="top"
      className="section section-dark relative overflow-hidden"
      style={{ paddingTop: "clamp(56px, 7vh, 88px)", paddingBottom: "clamp(56px, 8vh, 96px)" }}
    >
      <GhostGrid />
      <div className="shell relative grid items-center gap-12 lg:grid-cols-[minmax(0,1fr)_520px] lg:gap-8">
        <div className="min-w-0">
          <Image
            src={asset("/herald-logo.png")}
            alt="Herald"
            width={104}
            height={104}
            unoptimized
            priority
            className="mb-8 h-[72px] w-[72px] rounded-md sm:h-[104px] sm:w-[104px]"
          />
          <p className="mb-6 inline-flex items-center rounded-full border border-accent px-3 py-1 text-[12px] font-medium text-accent">
            A notification service for macOS · the Growl idea, rebuilt
          </p>
          <h1 className="display" style={{ lineHeight: 0.95 }}>
            <span className="block" style={{ fontSize: "clamp(52px, min(9vw, 13.5vh), 128px)" }}>
              Notifications
            </span>
            <em className="block" style={{ fontSize: "clamp(46px, min(7.9vw, 11.8vh), 112px)" }}>
              you&rsquo;d actually design.
            </em>
          </h1>
          <p className="mt-8 max-w-[56ch] text-[16px] leading-[1.6] text-muted sm:text-[18px]">
            Any app declares the data it can send. You design — on a grid of any size, with merged cells and
            nine-point alignment — exactly how it shows up: persistent, interactive, animated banners with
            history, sound and actions. They stay until you deal with them, sit above everything, and never
            steal focus.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <SiteLink href={release.dmgUrl} className="btn btn-primary">
              <Download size={18} aria-hidden />
              Download Herald · {release.version}
            </SiteLink>
            <SiteLink href="/docs/reference/http-api" className="btn btn-ghost">
              Read the API docs
            </SiteLink>
          </div>
          <pre
            className="mono mt-8 max-w-[600px] overflow-x-auto rounded-md border border-line bg-surface px-4 py-3 text-[12px] leading-[1.5] text-muted"
            tabIndex={0}
            aria-label="Example command"
          >
            <code>
              <span aria-hidden>$ </span>herald send --app ci.bot --title &quot;Build passed&quot; --body &quot;142 tests&quot;
            </code>
          </pre>
        </div>
        <div className="relative mx-auto w-full max-w-[520px] lg:mx-0">
          <BannerStack />
        </div>
      </div>
    </section>
  );
}
