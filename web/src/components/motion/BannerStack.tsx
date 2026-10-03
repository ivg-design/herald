"use client";

import Image from "next/image";
import { motion, useReducedMotion } from "framer-motion";
import { EASE, asset } from "@/lib/config";

// Hero banners (wireframe crop c0). Everything inside is sized in container-query units
// so the 520 px composition scales down to 358 px without reflow or overflow.
const FS = (max: number, cq: number) => `clamp(9px, ${cq}cqw, ${max}px)`;
const IN_EASE = EASE.expo;
const GRID_EASE = EASE.quint;

function AppIcon({ size }: { size: string }) {
  return (
    <Image
      src={asset("/herald-icon.png")}
      alt=""
      width={64}
      height={64}
      unoptimized
      style={{ width: size, height: size, borderRadius: "22%" }}
      className="shrink-0"
    />
  );
}

function Head({ app, title, extra }: { app: string; title: string; extra?: React.ReactNode }) {
  return (
    <div className="flex items-start" style={{ gap: "2.4cqw" }}>
      <AppIcon size="7.2cqw" />
      <div className="min-w-0 flex-1">
        <div className="font-mono uppercase text-muted" style={{ fontSize: FS(10, 1.9), letterSpacing: "0.06em", lineHeight: 1.3 }}>{app}</div>
        <div className="truncate font-medium text-ink" style={{ fontSize: FS(15, 3), lineHeight: 1.3 }}>{title}</div>
      </div>
      {extra}
    </div>
  );
}

const bannerBase: React.CSSProperties = {
  position: "absolute",
  background: "var(--surface)",
  border: "1px solid var(--line)",
  borderRadius: 12,
  padding: "2.4cqw 2.8cqw",
  overflow: "hidden",
};

export default function BannerStack() {
  const reduce = useReducedMotion();
  const item = (i: number, finalOpacity: number) => ({
    initial: reduce ? false : { opacity: 0, x: 24 },
    animate: { opacity: finalOpacity, x: 0 },
    transition: reduce ? { duration: 0 } : { duration: 0.52, ease: IN_EASE, delay: i * 0.14 },
  });
  // grid starts after the front banner has landed (2 * 140 ms + 520 ms)
  const gridDelay = 0.8;
  const line = (delay: number) =>
    reduce ? { duration: 0 } : { duration: 0.4, ease: GRID_EASE, delay: gridDelay + delay };

  return (
    <div className="w-full" style={{ containerType: "inline-size", maxWidth: 520 }}>
      <div aria-hidden="true" className="relative w-full" style={{ aspectRatio: "520 / 400" }}>
        {/* back: WebWatcher email stack */}
        <motion.div style={{ ...bannerBase, left: "20%", top: 0, width: "80%", height: "21%" }} {...item(0, 0.45)}>
          <Head
            app="WebWatcher · Email"
            title="3 new from @rive.app"
            extra={
              <span
                className="grid shrink-0 place-items-center font-mono font-medium"
                style={{ background: "var(--signal)", color: "#fff5f2", width: "4cqw", height: "4cqw", borderRadius: 999, fontSize: FS(11, 2.1) }}
              >
                3
              </span>
            }
          />
          <div className="truncate text-muted" style={{ fontSize: FS(12, 2.35), marginTop: "1.6cqw" }}>Release notes · Scripting update · Office hours</div>
        </motion.div>

        {/* middle: After Effects */}
        <motion.div style={{ ...bannerBase, left: "10%", top: "27%", width: "80%", height: "21%" }} {...item(1, 1)}>
          <Head app="After Effects" title="Render finished" />
          <div className="truncate text-muted" style={{ fontSize: FS(12, 2.35), marginTop: "1.6cqw" }}>final_v3.mp4 · 02:14 · 1.2 GB</div>
        </motion.div>

        {/* front: CI Bot with the self-drawing grid */}
        <motion.div style={{ ...bannerBase, left: 0, top: "55%", width: "80%", height: "35%" }} {...item(2, 1)}>
          <Head app="CI Bot" title="Build passed" />
          <div className="truncate text-muted" style={{ fontSize: FS(12, 2.35), marginTop: "1.6cqw" }}>142 tests, 0 failures · main · 3m 12s</div>
          <div className="flex" style={{ gap: "1.6cqw", marginTop: "2.4cqw" }}>
            {[
              ["Open log", true],
              ["Deploy", false],
              ["Snooze 1h", false],
            ].map(([label, primary]) => (
              <span
                key={label as string}
                className="font-medium"
                style={{
                  fontSize: FS(12, 2.3),
                  padding: "1.2cqw 2.4cqw",
                  borderRadius: 6,
                  whiteSpace: "nowrap",
                  background: primary ? "var(--accent)" : "var(--surface-2)",
                  color: primary ? "var(--accent-ink)" : "var(--ink)",
                }}
              >
                {label as string}
              </span>
            ))}
          </div>
          {/* 4 columns x 3 rows: 3 inner verticals, 2 inner horizontals, drawn from the top-left */}
          {[25, 50, 75].map((p, i) => (
            <motion.span
              key={`v${p}`}
              className="absolute top-0 bottom-0"
              style={{ left: `${p}%`, width: 1, background: "var(--accent)", opacity: 0.55, transformOrigin: "top left" }}
              initial={reduce ? false : { scaleY: 0 }}
              animate={{ scaleY: 1 }}
              transition={line(i * 0.1)}
            />
          ))}
          {[33.333, 66.667].map((p, i) => (
            <motion.span
              key={`h${p}`}
              className="absolute left-0 right-0"
              style={{ top: `${p}%`, height: 1, background: "var(--accent)", opacity: 0.55, transformOrigin: "top left" }}
              initial={reduce ? false : { scaleX: 0 }}
              animate={{ scaleX: 1 }}
              transition={line(0.1 + i * 0.1)}
            />
          ))}
        </motion.div>
        {/* frame in accent, draws with the grid (opacity only) */}
        <motion.span
          className="pointer-events-none absolute"
          style={{ left: 0, top: "55%", width: "80%", height: "35%", border: "1px solid var(--accent)", borderRadius: 12 }}
          initial={reduce ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={reduce ? { duration: 0 } : { duration: 0.3, ease: GRID_EASE, delay: gridDelay }}
        />

        {/* tag */}
        <motion.span
          className="absolute font-mono font-medium"
          style={{
            right: 0,
            top: "47.5%",
            background: "var(--signal)",
            color: "#fff5f2",
            fontSize: FS(11, 2.1),
            padding: "0.5cqw 1.8cqw",
            borderRadius: 999,
            whiteSpace: "nowrap",
            transformOrigin: "bottom left",
          }}
          initial={reduce ? false : { opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={reduce ? { duration: 0 } : { duration: 0.3, ease: EASE.quart, delay: gridDelay + 0.6 }}
        >
          your grid · any rows × columns
        </motion.span>
      </div>
      <p className="sr-only">
        Example Herald banner from CI Bot: Build passed, 142 tests, 0 failures, main, 3m 12s, with the buttons Open log, Deploy and Snooze 1h,
        laid out on a grid of any number of rows and columns. Behind it, stacked banners from After Effects and WebWatcher.
      </p>
    </div>
  );
}
