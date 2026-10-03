"use client";

import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import Image from "next/image";
import { asset } from "@/lib/config";
import { HOTSPOTS, type Hotspot } from "./designer-hotspots";

export interface ShotDims { w: number; h: number }

/**
 * The real Designer window with six numbered regions. Hover or focus a region (or its legend entry): everything else
 * dims, the region keeps an accent outline, and a card explains it. Below 900 px the regions give way to a details list.
 */
export default function DesignerShowcase({ shots, intro }: { shots: { light?: ShotDims; dark?: ShotDims }; intro?: ReactNode }) {
  const both = !!shots.light && !!shots.dark;
  const [mode, setMode] = useState<"dark" | "light">(shots.dark ? "dark" : "light");
  const [active, setActive] = useState<string | null>(null);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setActive(null);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  const dims = shots[mode] ?? shots.dark ?? shots.light;
  const activeSpot = HOTSPOTS.find((h) => h.id === active) ?? null;
  const on = (h: Hotspot) => ({
    onMouseEnter: () => setActive(h.id),
    onMouseLeave: () => setActive((a) => (a === h.id ? null : a)),
    onFocus: () => setActive(h.id),
    onBlur: () => setActive((a) => (a === h.id ? null : a)),
  });

  // Card sits beside the region on the chosen side, hugging its start or end, so it never leaves the frame.
  const cardPos = (h: Hotspot): CSSProperties => {
    const { x, y, w, h: rh } = h.region;
    const gap = 1.2;
    const start = h.card.at === "start";
    switch (h.card.side) {
      case "right": return { left: `${x + w + gap}%`, ...(start ? { top: `${y + gap}%` } : { bottom: `${100 - (y + rh) + gap}%` }) };
      case "left": return { right: `${100 - x + gap}%`, ...(start ? { top: `${y + gap}%` } : { bottom: `${100 - (y + rh) + gap}%` }) };
      case "above": return { left: `${x + gap}%`, bottom: `${100 - y + gap}%` };
      default: return { left: `${x + gap}%`, top: `${y + rh + gap}%` };
    }
  };

  return (
    <div ref={root} className="w-full">
      <div className="dz-head">
        <div>{intro}</div>
        {both && (
          <div className="dz-toggle" role="group" aria-label="Screenshot appearance">
            {(["dark", "light"] as const).map((m) => (
              <button key={m} type="button" onClick={() => setMode(m)} aria-pressed={mode === m}>
                {m === "dark" ? "Dark" : "Light"}
              </button>
            ))}
          </div>
        )}
      </div>

      {dims && (
        <div className="dz-frame">
          <div className="dz-clip">
            <Image
              src={asset(mode === "dark" && shots.dark ? "/designer-dark.png" : "/designer-light.png")}
              alt="The Herald Designer: issuer and templates, components, assets and fields on the left; live preview and grid canvas in the centre; inspector on the right"
              width={dims.w}
              height={dims.h}
              sizes="(min-width: 1232px) 1200px, 100vw"
              unoptimized
              priority={false}
            />
            {activeSpot && (
              <span
                key={activeSpot.id}
                aria-hidden
                className="dz-lit"
                style={{ left: `${activeSpot.region.x}%`, top: `${activeSpot.region.y}%`, width: `${activeSpot.region.w}%`, height: `${activeSpot.region.h}%` }}
              />
            )}
          </div>

          {HOTSPOTS.map((h) => (
            <div key={h.id}>
              <button
                type="button"
                className="dz-hot"
                aria-label={`${h.n}. ${h.title}: ${h.body}`}
                aria-expanded={active === h.id}
                style={{ left: `${h.region.x}%`, top: `${h.region.y}%`, width: `${h.region.w}%`, height: `${h.region.h}%` }}
                {...on(h)}
                onClick={() => setActive(active === h.id ? null : h.id)}
              />
              <span aria-hidden className="dz-dot" data-on={active === h.id} style={{ left: `${h.dot.x}%`, top: `${h.dot.y}%` }}>{h.n}</span>
            </div>
          ))}

          {activeSpot && (
            <div key={`card-${activeSpot.id}`} aria-hidden className="dz-card" style={cardPos(activeSpot)}>
              <h3>{activeSpot.n} &middot; {activeSpot.title}</h3>
              <p>{activeSpot.body}</p>
            </div>
          )}
        </div>
      )}

      <p className="dz-hint">Hover or focus a region of the Designer</p>

      <ol className="dz-legend">
        {HOTSPOTS.map((h) => (
          <li key={h.id} data-on={active === h.id} onMouseEnter={() => setActive(h.id)} onMouseLeave={() => setActive((a) => (a === h.id ? null : a))}>
            <span className="dz-num">{h.n}</span>
            <div>
              <h3>{h.title}</h3>
              <p>{h.body}</p>
            </div>
          </li>
        ))}
      </ol>

      <div className="dz-list" role="group" aria-label="Explore the Designer">
        {HOTSPOTS.map((h) => (
          <details key={h.id}>
            <summary><span className="dz-num">{h.n}</span>{h.title}</summary>
            <p>{h.body}</p>
          </details>
        ))}
      </div>
    </div>
  );
}
