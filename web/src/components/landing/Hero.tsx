"use client";

import { useEffect, useRef, useState } from "react";
import { Download } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import HeroDock from "@/components/herald/HeroDock";
import { useHeraldInternal } from "@/components/herald/internal";
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

const CI = {
  app: "ci.bot",
  appName: "CI Bot",
  icon: "ci",
  title: "Build passed",
  body: "142 tests, 0 failures · main",
  buttons: [
    { label: "Open log", role: "open", primary: true, url: "ci.example.com/142" },
    { label: "Deploy", role: "deploy" },
    { label: "Snooze", role: "snooze" },
  ],
  confirm: "Deploy build 4f2a to production?",
  speak: true,
} as const;

/** The Herald mark; its red dot pings once whenever a banner is sent (same signal as the header bell). */
function LogoMark({ ring }: { ring: number }) {
  return (
    <span className="hb-logo">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={asset("/herald-logo.svg")} alt="Herald" className="hb-logo-img" />
      {ring > 0 && <span key={ring} aria-hidden className="hb-logo-ping" />}
    </span>
  );
}

export default function Hero({ release }: { release: ReleaseInfo }) {
  const h = useHeraldInternal();
  const { seed, ring } = h;
  const [sent, setSent] = useState("");
  const seeded = useRef(false);

  useEffect(() => {
    if (seeded.current) return;
    seeded.current = true;
    seed({
      app: "webwatcher.email",
      appName: "WebWatcher · Email",
      icon: "mail",
      title: "Release notes",
      body: "Rive <hello@rive.app>",
      buttons: [{ label: "Open", role: "open", primary: true, url: "mail.google.com" }, { label: "Archive", role: "dismiss" }],
    });
    seed({ app: "webwatcher.email", appName: "WebWatcher · Email", icon: "mail", title: "Scripting update", body: "Rive <hello@rive.app>" });
    seed({ app: "webwatcher.email", appName: "WebWatcher · Email", icon: "mail", title: "Office hours moved to Thursday", body: "Rive <hello@rive.app>" });
    seed({ app: "ae", appName: "After Effects", icon: "ae", title: "Render finished", body: "final_v3.mp4 · 02:14 · 1.2 GB", buttons: [{ label: "Show in Finder", role: "open", primary: true, url: "final_v3.mp4" }, { label: "Snooze", role: "snooze" }] });
    seed({ ...CI, buttons: [...CI.buttons] });
  }, [seed]);
  const run = () => {
    const stack = h.cards.find((c) => c.app === CI.app);
    const held = h.quiet.hold && h.isQuiet();
    h.send({ ...CI, buttons: [...CI.buttons] });
    setSent(held ? `Sent · held until ${h.heldUntil}` : stack ? `Sent · stacked with ${CI.appName} (${stack.items.length + 1})` : "Sent");
  };

  return (
    <section
      id="top"
      className="section section-dark relative overflow-hidden"
      style={{ paddingTop: "clamp(56px, 7vh, 88px)", paddingBottom: "clamp(56px, 8vh, 96px)" }}
    >
      <GhostGrid />
      <div className="shell relative grid grid-cols-[minmax(0,1fr)] gap-y-8 lg:grid-cols-[minmax(0,1fr)_412px] lg:gap-x-10 lg:gap-y-0">
        <div className="min-w-0 lg:col-start-1 lg:row-start-1 lg:self-end">
          <div className="mb-6 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:gap-5">
            <LogoMark ring={ring} />
            <p className="eyebrow m-0 min-w-0">A notification service for macOS · the Growl idea, rebuilt</p>
          </div>
          <h1 className="display min-w-0" style={{ lineHeight: 0.95, overflowWrap: "normal" }}>
            <span className="block" style={{ fontSize: "clamp(56px, min(9vw, 13.5vh), 128px)" }}>
              Notifications
            </span>
            <em className="block text-accent" style={{ fontSize: "clamp(44px, min(7.9vw, 11.8vh), 112px)" }}>
              you&rsquo;d actually design.
            </em>
          </h1>
        </div>
        <div className="relative mx-auto w-full max-w-[412px] lg:col-start-2 lg:row-span-2 lg:row-start-1 lg:mx-0 lg:self-center">
          <HeroDock />
        </div>
        <div className="min-w-0 lg:col-start-1 lg:row-start-2 lg:self-start">
          <p className="mt-0 lg:mt-8 max-w-[56ch] text-[16px] leading-[1.6] text-muted sm:text-[18px]">
            Any app declares the data it can send. You design — on a grid of any size, with merged cells and
            nine-point alignment — exactly how it shows up: persistent, interactive, animated banners with
            history, sound and actions. They stay until you deal with them, sit above everything, and never
            steal focus.
          </p>
          <div className="mt-6 flex flex-wrap gap-3 sm:mt-8">
            <SiteLink href={release.dmgUrl} className="btn btn-primary">
              <Download size={18} aria-hidden />
              Download Herald · {release.version}
            </SiteLink>
            <SiteLink href="/docs/reference/http-api" className="btn btn-ghost">
              Read the API docs
            </SiteLink>
          </div>
          <div className="mt-8 flex max-w-[640px] flex-wrap items-center gap-x-4 gap-y-2">
            <code className="mono min-w-0 text-[12px] leading-[1.6] text-muted break-words">
              <span aria-hidden>$ </span>herald send --app ci.bot --title &quot;Build passed&quot; --body &quot;142 tests&quot;
            </code>
            <button type="button" className="btn btn-ghost btn-sm" onClick={run}>Run it</button>
          </div>
          <p className="mono m-0 mt-2 min-h-[18px] text-[11px] text-accent" role="status" aria-live="polite">{sent}</p>
        </div>
      </div>
    </section>
  );
}
