"use client";
// Rive menu-bar bell (Herald's real menu-bar icon shows an unread count). Rings when `ring` changes.
// Source: web/rive/bell -> /rive/bell.riv. Artboard "bell" (ink #F4F1EA, for dark surfaces) or "bell-dark" (#0F1317, for paper).
// State machine "Main": trigger `ring`, number `count`. The count number itself is drawn here, over the canvas.
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Bell as BellIcon } from "lucide-react";
import { Fit, Layout, useRive } from "@rive-app/react-canvas";
import { asset } from "@/lib/config";
import "./runtime";

const LAYOUT = new Layout({ fit: Fit.Contain });
const MOTION_QUERY = "(prefers-reduced-motion: reduce)";

function useReducedMotion(): boolean {
  return useSyncExternalStore(
    (cb) => {
      const mq = window.matchMedia(MOTION_QUERY);
      mq.addEventListener("change", cb);
      return () => mq.removeEventListener("change", cb);
    },
    () => window.matchMedia(MOTION_QUERY).matches,
    () => false,
  );
}

/** `tone="paper"` picks the dark-ink artboard for light (paper) sections; default is the light ink for dark surfaces. */
export default function Bell({
  count,
  ring,
  size = 22,
  className = "",
  tone = "ink",
}: {
  count: number;
  ring: number;
  size?: number;
  className?: string;
  tone?: "ink" | "paper";
}) {
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  const reduced = useReducedMotion();
  const { rive, RiveComponent } = useRive({
    src: asset("/rive/bell.riv"),
    artboard: tone === "paper" ? "bell-dark" : "bell",
    stateMachines: "Main",
    autoplay: true,
    layout: LAYOUT,
    onLoad: () => setLoaded(true),
    onLoadError: () => setFailed(true),
  });

  useEffect(() => {
    if (!rive || !loaded) return;
    const countInput = rive.stateMachineInputs("Main")?.find((i) => i.name === "count");
    if (!countInput) return;
    countInput.value = count;
    rive.play();
    if (!reduced) return;
    const t = window.setTimeout(() => rive.pause(), 650);
    return () => window.clearTimeout(t);
  }, [rive, loaded, count, reduced]);

  // Fire the trigger when `ring` changes; the first render's value is the baseline and never rings.
  const lastRing = useRef(ring);
  useEffect(() => {
    if (lastRing.current === ring) return;
    lastRing.current = ring;
    if (reduced || !rive || !loaded) return;
    const ringInput = rive.stateMachineInputs("Main")?.find((i) => i.name === "ring");
    if (!ringInput) return;
    rive.play();
    ringInput.fire();
  }, [rive, loaded, ring, reduced]);

  const showFallback = failed || !loaded;
  const ink = tone === "paper" ? "var(--paper-ink, #0f1317)" : "var(--ink)";
  return (
    <span className={`relative inline-grid place-items-center ${className}`} style={{ width: size, height: size }} aria-hidden>
      {showFallback && <BellIcon size={size - 2} style={{ color: ink }} />}
      {!failed && (
        <RiveComponent style={{ position: "absolute", inset: 0, width: size, height: size, opacity: loaded ? 1 : 0 }} />
      )}
      {count > 0 && (
        <span
          className="absolute -right-1.5 -top-1.5 grid h-4 min-w-4 place-items-center rounded-full px-1 font-mono text-[10px] font-bold"
          style={{ background: "var(--signal)", color: "#fff5f2" }}
        >
          {count}
        </span>
      )}
    </span>
  );
}
