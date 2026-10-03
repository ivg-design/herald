"use client";
// A 4 x 3 grid that assembles into a Herald banner: the dashed cells draw in, title/body/action cells merge,
// the components drop into their cells, the grid fades and the banner remains. Source: web/rive/grid-banner
// (scripts/gen-grid-banner.mjs writes the scene) -> /rive/grid-banner.riv. State machine "Main", trigger `replay`.
// Plays once when scrolled into view; click or Enter replays. Reduced motion: shows the finished banner.
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Fit, Layout, useRive } from "@rive-app/react-canvas";
import { asset } from "@/lib/config";
import "./runtime";

const LAYOUT = new Layout({ fit: Fit.Contain });
const MOTION_QUERY = "(prefers-reduced-motion: reduce)";
const END_SECONDS = 2.5;

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

export default function GridBanner({ className = "" }: { className?: string }) {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLButtonElement>(null);
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  const [seen, setSeen] = useState(false);
  const [plays, setPlays] = useState(0);
  const { rive, RiveComponent } = useRive({
    src: asset("/rive/grid-banner.riv"),
    stateMachines: "Main",
    autoplay: false,
    layout: LAYOUT,
    onLoad: () => setLoaded(true),
    onLoadError: () => setFailed(true),
  });

  useEffect(() => {
    const el = ref.current;
    if (!el || seen) return;
    if (typeof IntersectionObserver === "undefined") {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setSeen(true);
      return;
    }
    const io = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting)) {
        setSeen(true);
        io.disconnect();
      }
    }, { threshold: 0.5 });
    io.observe(el);
    return () => io.disconnect();
  }, [seen]);

  useEffect(() => {
    if (!rive || !loaded || !seen) return;
    if (reduced) {
      // Land on the finished banner without the assembly.
      rive.play();
      const t = window.setTimeout(() => rive.pause(), END_SECONDS * 1000 + 200);
      return () => window.clearTimeout(t);
    }
    rive.play();
  }, [rive, loaded, seen, reduced]);

  const replay = () => {
    if (!rive || !loaded || reduced) return;
    const input = rive.stateMachineInputs("Main")?.find((i) => i.name === "replay");
    if (input) {
      rive.play();
      input.fire();
      setPlays((p) => p + 1);
    }
  };

  return (
    <button
      ref={ref}
      type="button"
      className={`gb ${className}`}
      onClick={replay}
      aria-label="A four by three grid assembles into a Herald banner. Replay"
      data-loaded={loaded}
      data-plays={plays}
      data-testid="grid-banner"
    >
      {!failed && <RiveComponent className="gb-canvas" style={{ opacity: loaded ? 1 : 0 }} />}
      {(failed || !loaded) && (
        <span aria-hidden className="gb-fallback mono">4 × 3 grid → banner</span>
      )}
    </button>
  );
}
