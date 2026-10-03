"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import { useReducedMotion } from "framer-motion";
import { asset } from "@/lib/config";
import { HOTSPOTS, type Hotspot } from "./designer-hotspots";

const IN_MS = 220;
const OUT_MS = 165;

function Placeholder({ dark }: { dark: boolean }) {
  const bg = dark ? "#10151a" : "#e9eef3";
  const panel = dark ? "#171d24" : "#ffffff";
  const ln = dark ? "#2a323b" : "#cfd8e1";
  const bar = (w: string) => <span className="block" style={{ height: 6, width: w, background: ln, borderRadius: 3 }} />;
  return (
    <div className="absolute inset-0 flex flex-col" style={{ background: bg }} aria-hidden="true">
      <div className="flex items-center gap-1.5 px-3" style={{ height: "7%", borderBottom: `1px solid ${ln}`, background: panel }}>
        {["#d9371e", "#d9a21e", "#2f9e5a"].map((c) => <span key={c} className="rounded-full" style={{ width: 8, height: 8, background: c, opacity: 0.7 }} />)}
        <span className="ml-3">{bar("90px")}</span>
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="flex flex-col gap-2 p-3" style={{ width: "18%", borderRight: `1px solid ${ln}`, background: panel }}>{bar("70%")}{bar("50%")}{bar("80%")}{bar("60%")}</div>
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="grid place-items-center" style={{ height: "30%", borderBottom: `1px solid ${ln}` }}>
            <span style={{ width: "50%", height: "55%", border: `1px solid ${ln}`, borderRadius: 8, background: panel }} />
          </div>
          <div className="grid flex-1 place-items-center p-4">
            <div className="grid h-full w-full" style={{ gridTemplate: "repeat(3,1fr)/repeat(4,1fr)", border: `1px solid ${ln}`, background: panel }}>
              {Array.from({ length: 12 }).map((_, k) => <span key={k} style={{ border: `1px dashed ${ln}` }} />)}
            </div>
          </div>
        </div>
        <div className="flex flex-col gap-2 p-3" style={{ width: "26%", borderLeft: `1px solid ${ln}`, background: panel }}>{bar("60%")}{bar("85%")}{bar("45%")}{bar("75%")}{bar("55%")}</div>
      </div>
      <div className="flex" style={{ height: "30%", borderTop: `1px solid ${ln}`, background: panel }}>
        <div className="flex flex-1 flex-wrap content-start gap-2 p-3" style={{ borderRight: `1px solid ${ln}` }}>
          {Array.from({ length: 8 }).map((_, k) => <span key={k} style={{ width: 44, height: 24, border: `1px solid ${ln}`, borderRadius: 5 }} />)}
        </div>
        <div className="flex flex-1 flex-col gap-2 p-3">{bar("70%")}{bar("50%")}{bar("62%")}</div>
      </div>
    </div>
  );
}

export default function DesignerShowcase({ hasShots }: { hasShots: { light: boolean; dark: boolean } }) {
  const reduce = useReducedMotion();
  const both = hasShots.light && hasShots.dark;
  const none = !hasShots.light && !hasShots.dark;
  const [mode, setMode] = useState<"dark" | "light">(hasShots.dark || none ? "dark" : "light");
  const [active, setActive] = useState<string | null>(null);
  const [region, setRegion] = useState<Hotspot["region"]>(HOTSPOTS[0].region);
  const root = useRef<HTMLDivElement>(null);
  const dur = (on: boolean) => (on ? IN_MS : OUT_MS);

  const activate = (h: Hotspot) => {
    setRegion(h.region);
    setActive(h.id);
  };
  const release = (id: string) => setActive((a) => (a === id ? null : a));

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

  const src = mode === "dark" ? "/designer-dark.png" : "/designer-light.png";
  const activeSpot = HOTSPOTS.find((h) => h.id === active) ?? null;
  const r = region;
  const clip = `polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, ${r.x}% ${r.y}%, ${r.x}% ${r.y + r.h}%, ${r.x + r.w}% ${r.y + r.h}%, ${r.x + r.w}% ${r.y}%, ${r.x}% ${r.y}%)`;

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
        <div className="mb-3 flex" role="group" aria-label="Screenshot theme">
          <div className="inline-flex rounded-lg p-0.5" style={{ background: "var(--paper-line)" }}>
            {(["dark", "light"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => setMode(m)}
                aria-pressed={mode === m}
                className="rounded-md px-4 text-sm font-medium"
                style={{
                  minHeight: 40,
                  background: mode === m ? "var(--paper-surface)" : "transparent",
                  color: mode === m ? "var(--paper-ink)" : "var(--paper-muted)",
                  transition: reduce ? "none" : "background-color 165ms var(--ease-quart)",
                }}
              >
                {m === "dark" ? "Dark" : "Light"}
              </button>
            ))}
          </div>
        </div>
      )}

      <div
        className="relative w-full overflow-hidden"
        style={{ aspectRatio: "16 / 10", borderRadius: 14, border: "1px solid var(--line)", background: "var(--bg)" }}
      >
        {none ? (
          <>
            <Placeholder dark={mode === "dark"} />
            <p className="absolute bottom-[4%] left-1/2 w-max max-w-[88%] -translate-x-1/2 rounded-md px-3 py-1.5 text-center font-mono text-[10px] tracking-wide sm:text-xs" style={{ color: "var(--ink)", background: "var(--surface-2)", border: "1px solid var(--line)" }}>
              PLACEHOLDER: real Designer screenshot goes here (public/designer-light.png, designer-dark.png)
            </p>
          </>
        ) : (
          <Image src={asset(src)} alt="The Herald Designer: issuer list, live preview, grid canvas, inspector, components and actions" fill sizes="(min-width: 1232px) 1200px, 100vw" unoptimized style={{ objectFit: "cover" }} />
        )}

        {/* dims everything outside the active region; the cutout is set when the region changes, only opacity animates */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0"
          style={{ background: "#0f1317", opacity: active ? 0.62 : 0, clipPath: clip, transition: reduce ? "none" : `opacity ${dur(!!active)}ms var(--ease-quart)` }}
        />

        {HOTSPOTS.map((h) => {
          const on = active === h.id;
          return (
            <div key={h.id}>
              <button
                type="button"
                aria-label={`${h.n} · ${h.title}`}
                aria-expanded={on}
                className="absolute grid place-items-center font-mono text-xs font-medium"
                style={{
                  left: `${h.dot.x}%`,
                  top: `${h.dot.y}%`,
                  width: 28,
                  height: 28,
                  marginLeft: -14,
                  marginTop: -14,
                  borderRadius: 999,
                  background: "var(--accent)",
                  color: "var(--accent-ink)",
                  transform: on && !reduce ? "scale(1.12)" : "none",
                  transition: reduce ? "none" : `transform ${IN_MS}ms var(--ease-quart)`,
                  zIndex: on ? 3 : 2,
                }}
                onMouseEnter={() => activate(h)}
                onMouseLeave={() => release(h.id)}
                onFocus={() => activate(h)}
                onBlur={() => release(h.id)}
                onClick={() => (on ? setActive(null) : activate(h))}
              >
                {h.n}
              </button>
              <div
                aria-hidden="true"
                className="pointer-events-none hidden rounded-lg p-3 sm:block"
                style={{
                  ...cardPos(h),
                  zIndex: 4,
                  background: "var(--surface-2)",
                  border: "1px solid var(--line)",
                  color: "var(--ink)",
                  opacity: on ? 1 : 0,
                  translate: on || reduce ? "0 0" : "0 6px",
                  transition: reduce ? "none" : `opacity ${dur(on)}ms var(--ease-quart), translate ${dur(on)}ms var(--ease-quart)`,
                  visibility: on ? "visible" : "hidden",
                }}
              >
                <p className="text-sm font-medium">{h.n} · {h.title}</p>
                <p className="mt-1 text-[13px] leading-snug" style={{ color: "var(--muted)" }}>{h.body}</p>
              </div>
            </div>
          );
        })}

        {/* docked caption bar (narrow screens) */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-x-0 bottom-0 p-3 sm:hidden"
          style={{
            zIndex: 5,
            background: "var(--surface-2)",
            borderTop: "1px solid var(--line)",
            color: "var(--ink)",
            opacity: activeSpot ? 1 : 0,
            transition: reduce ? "none" : `opacity ${dur(!!activeSpot)}ms var(--ease-quart)`,
          }}
        >
          {activeSpot && (
            <>
              <p className="text-[13px] font-medium">{activeSpot.n} · {activeSpot.title}</p>
              <p className="mt-0.5 text-xs leading-snug" style={{ color: "var(--muted)" }}>{activeSpot.body}</p>
            </>
          )}
        </div>
      </div>

      <ol className="mt-8 grid list-none grid-cols-1 gap-x-6 gap-y-4 p-0 min-[420px]:grid-cols-2 md:grid-cols-3 xl:grid-cols-6">
        {HOTSPOTS.map((h) => {
          const on = active === h.id;
          return (
            <li key={h.id}>
              <div
                tabIndex={0}
                className="-m-2 flex h-full gap-3 rounded-lg p-2"
                style={{ background: on ? "var(--paper-line)" : "transparent", transition: reduce ? "none" : "background-color 165ms var(--ease-quart)", minHeight: 40 }}
                onMouseEnter={() => activate(h)}
                onMouseLeave={() => release(h.id)}
                onFocus={() => activate(h)}
                onBlur={() => release(h.id)}
                onClick={() => (on ? setActive(null) : activate(h))}
              >
                <span
                  className="grid shrink-0 place-items-center font-mono text-xs font-medium"
                  style={{ width: 28, height: 28, borderRadius: 999, background: "var(--accent)", color: "var(--accent-ink)" }}
                >
                  {h.n}
                </span>
                <div>
                  <h3 className="text-sm font-medium" style={{ color: "var(--paper-ink)" }}>{h.title}</h3>
                  <p className="mt-1 text-[13px] leading-snug" style={{ color: "var(--paper-muted)" }}>{h.body}</p>
                </div>
              </div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
