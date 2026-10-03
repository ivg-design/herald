"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { asset } from "@/lib/config";
import { HOTSPOTS, type Hotspot } from "./designer-hotspots";

export interface ShotDims { w: number; h: number }

/**
 * The real Designer window with six numbered hotspots. Hover, focus or tap one: its region is outlined on the
 * screenshot and the card explains it. The numbered list under the image carries the same text for reading and for
 * small screens; it does nothing on hover because it is just text.
 */
export default function DesignerShowcase({ shots }: { shots: { light?: ShotDims; dark?: ShotDims } }) {
  const both = !!shots.light && !!shots.dark;
  const [mode, setMode] = useState<"dark" | "light">(shots.dark ? "dark" : "light");
  const [active, setActive] = useState<string | null>(null);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setActive(null);
    const onDown = (e: PointerEvent) => {
      if (root.current && !root.current.contains(e.target as Node)) setActive(null);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onDown);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onDown);
    };
  }, []);

  const dims = shots[mode] ?? shots.dark ?? shots.light;
  const activeSpot = HOTSPOTS.find((h) => h.id === active) ?? null;
  const on = (h: Hotspot) => ({
    onMouseEnter: () => setActive(h.id),
    onMouseLeave: () => setActive((a) => (a === h.id ? null : a)),
    onFocus: () => setActive(h.id),
    onBlur: () => setActive((a) => (a === h.id ? null : a)),
  });

  const cardPos = (h: Hotspot): React.CSSProperties => {
    const base: React.CSSProperties = { position: "absolute", width: 260 };
    switch (h.card) {
      case "right": return { ...base, left: `calc(${h.dot.x}% + 24px)`, top: `${h.dot.y}%`, marginTop: -28 };
      case "left": return { ...base, right: `calc(${100 - h.dot.x}% + 24px)`, top: `${h.dot.y}%`, marginTop: -28 };
      case "top": return { ...base, left: `clamp(0px, calc(${h.dot.x}% - 130px), calc(100% - 260px))`, bottom: `calc(${100 - h.dot.y}% + 24px)` };
      default: return { ...base, left: `clamp(0px, calc(${h.dot.x}% - 130px), calc(100% - 260px))`, top: `calc(${h.dot.y}% + 24px)` };
    }
  };

  return (
    <div ref={root} className="w-full">
      {both && (
        <div className="mb-3 flex" role="group" aria-label="Screenshot appearance">
          <div className="inline-flex rounded-lg p-0.5" style={{ background: "var(--paper-line)" }}>
            {(["dark", "light"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => setMode(m)}
                aria-pressed={mode === m}
                className="cursor-pointer rounded-md px-4 text-sm font-medium"
                style={{ minHeight: 40, background: mode === m ? "var(--paper-surface)" : "transparent", color: mode === m ? "var(--paper-ink)" : "var(--paper-muted)" }}
              >
                {m === "dark" ? "Dark" : "Light"}
              </button>
            ))}
          </div>
        </div>
      )}

      {dims && (
        <div className="relative w-full overflow-hidden" style={{ borderRadius: 14 }}>
          <Image
            src={asset(mode === "dark" && shots.dark ? "/designer-dark.png" : "/designer-light.png")}
            alt="The Herald Designer: issuer list, live preview, grid canvas, inspector, components and actions"
            width={dims.w}
            height={dims.h}
            sizes="(min-width: 1232px) 1200px, 100vw"
            unoptimized
            priority={false}
            style={{ width: "100%", height: "auto", display: "block" }}
          />

          {activeSpot && (
            <span
              aria-hidden
              className="pointer-events-none absolute"
              style={{
                left: `${activeSpot.region.x}%`, top: `${activeSpot.region.y}%`, width: `${activeSpot.region.w}%`, height: `${activeSpot.region.h}%`,
                border: "2px solid var(--accent)", borderRadius: 8, background: "color-mix(in srgb, var(--accent) 10%, transparent)",
              }}
            />
          )}

          {HOTSPOTS.map((h) => {
            const isOn = active === h.id;
            return (
              <div key={h.id}>
                <button
                  type="button"
                  aria-label={`${h.n} · ${h.title}`}
                  aria-expanded={isOn}
                  className="absolute grid cursor-pointer place-items-center font-mono text-xs font-semibold"
                  style={{
                    left: `${h.dot.x}%`, top: `${h.dot.y}%`, width: 28, height: 28, marginLeft: -14, marginTop: -14, borderRadius: 999,
                    background: "var(--accent)", color: "var(--accent-ink)", border: "2px solid #fff", boxShadow: "0 1px 6px rgb(0 0 0 / 0.35)", zIndex: isOn ? 3 : 2,
                  }}
                  {...on(h)}
                  onClick={() => setActive(isOn ? null : h.id)}
                >
                  {h.n}
                </button>
                {isOn && (
                  <div
                    aria-hidden
                    className="pointer-events-none hidden rounded-lg p-3 sm:block"
                    style={{ ...cardPos(h), zIndex: 4, background: "var(--surface-2)", border: "1px solid var(--line)", color: "var(--ink)", boxShadow: "0 8px 24px rgb(0 0 0 / 0.35)" }}
                  >
                    <p className="text-sm font-medium">{h.n} · {h.title}</p>
                    <p className="mt-1 text-[13px] leading-snug" style={{ color: "var(--muted)" }}>{h.body}</p>
                  </div>
                )}
              </div>
            );
          })}

          {activeSpot && (
            <div aria-hidden className="pointer-events-none absolute inset-x-0 bottom-0 p-3 sm:hidden" style={{ zIndex: 5, background: "var(--surface-2)", borderTop: "1px solid var(--line)", color: "var(--ink)" }}>
              <p className="text-[13px] font-medium">{activeSpot.n} · {activeSpot.title}</p>
              <p className="mt-0.5 text-xs leading-snug" style={{ color: "var(--muted)" }}>{activeSpot.body}</p>
            </div>
          )}
        </div>
      )}

      <ol className="mt-8 grid list-none grid-cols-1 gap-x-6 gap-y-5 p-0 min-[420px]:grid-cols-2 md:grid-cols-3 xl:grid-cols-6">
        {HOTSPOTS.map((h) => (
          <li key={h.id} className="flex gap-3">
            <span className="grid shrink-0 place-items-center font-mono text-xs font-semibold" style={{ width: 28, height: 28, borderRadius: 999, background: "var(--accent)", color: "var(--accent-ink)" }}>
              {h.n}
            </span>
            <div>
              <h3 className="text-sm font-medium" style={{ color: "var(--paper-ink)" }}>{h.title}</h3>
              <p className="mt-1 text-[13px] leading-snug" style={{ color: "var(--paper-muted)" }}>{h.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}
