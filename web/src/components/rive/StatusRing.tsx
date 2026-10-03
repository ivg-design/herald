"use client";
// Rive status indicator used inside banners (a Rive component in a cell, as the Designer allows).
// Source: web/rive/status-ring -> /rive/status-ring.riv. State machine "Main", number input `state`
// (0 idle, 1 working, 2 done, 3 failed). Falls back to a CSS ring while loading, on error and without WebGL/canvas.
import { useEffect, useState, useSyncExternalStore } from "react";
import { Fit, Layout, useRive } from "@rive-app/react-canvas";
import { asset } from "@/lib/config";
import "./runtime";

export type RingState = "idle" | "working" | "done" | "failed";
export const RING_STATE_INPUT: Record<RingState, number> = { idle: 0, working: 1, done: 2, failed: 3 };

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

export default function StatusRing({ state, size = 20, className = "" }: { state: RingState; size?: number; className?: string }) {
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  const reduced = useReducedMotion();
  const { rive, RiveComponent } = useRive({
    src: asset("/rive/status-ring.riv"),
    stateMachines: "Main",
    autoplay: true,
    layout: LAYOUT,
    onLoad: () => setLoaded(true),
    onLoadError: () => setFailed(true),
  });

  useEffect(() => {
    if (!rive || !loaded) return;
    const input = rive.stateMachineInputs("Main")?.find((i) => i.name === "state");
    if (!input) return;
    input.value = RING_STATE_INPUT[state];
    if (!reduced) {
      rive.play();
      return;
    }
    // Reduced motion: let the change land, then hold the resulting frame (no spinning loop).
    rive.play();
    const t = window.setTimeout(() => rive.pause(), state === "working" ? 60 : 650);
    return () => window.clearTimeout(t);
  }, [rive, loaded, state, reduced]);

  const color = state === "failed" ? "var(--signal)" : "var(--accent)";
  const showFallback = failed || !loaded;
  return (
    <span aria-hidden className={`relative inline-block shrink-0 ${className}`} style={{ width: size, height: size }}>
      {showFallback && (
        <span
          className="absolute inset-0 rounded-full"
          style={{ border: `2px solid ${color}`, opacity: state === "idle" ? 0.4 : 1 }}
        />
      )}
      {!failed && (
        <RiveComponent
          style={{ position: "absolute", inset: 0, width: size, height: size, opacity: loaded ? 1 : 0 }}
        />
      )}
    </span>
  );
}
