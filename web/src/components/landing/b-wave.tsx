"use client";
import { useEffect, useRef, useState } from "react";
import { getPlayback, loadWaveform } from "@/components/herald/voice";

const BARS = 96;
const H = 56;
/** Static fallback silhouette (also the first paint), shaped like a spoken sentence. */
const SEED = [0.3, 0.55, 0.4, 0.8, 1, 0.6, 0.35, 0.7, 0.9, 0.5, 0.65, 0.95, 0.45, 0.3, 0.75, 0.55, 0.85, 0.4, 0.6, 0.3, 0.5];
export const WAVE = Array.from({ length: BARS }, (_, i) => SEED[i % SEED.length] * (0.6 + 0.4 * Math.abs(Math.sin(i * 0.37))));

/**
 * The real waveform of a Kokoro sample: 96 RMS bars decoded from /audio/<sample>.mp3 (decoding is silent), blue,
 * with a red playhead that follows the shared Audio element while it plays. Falls back to static bars.
 */
export default function Wave({ sample, playing, className = "" }: { sample: string; playing: boolean; className?: string }) {
  const host = useRef<HTMLDivElement>(null);
  const [bars, setBars] = useState<number[]>(WAVE);
  const [pRaw, setP] = useState(0);
  const p = playing ? pRaw : 0;

  useEffect(() => {
    const el = host.current;
    if (!el) return;
    let alive = true;
    const go = () => void loadWaveform(sample, BARS).then((b) => alive && setBars(b), () => {});
    if (typeof IntersectionObserver === "undefined") {
      go();
      return () => void (alive = false);
    }
    const io = new IntersectionObserver((e) => {
      if (e.some((x) => x.isIntersecting)) {
        io.disconnect();
        go();
      }
    }, { rootMargin: "200px" });
    io.observe(el);
    return () => {
      alive = false;
      io.disconnect();
    };
  }, [sample]);

  useEffect(() => {
    if (!playing) return;
    let raf = 0;
    const tick = () => {
      const { currentTime, duration } = getPlayback();
      setP(duration > 0 ? Math.min(1, currentTime / duration) : 0);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing]);

  return (
    <div ref={host} className={className} aria-hidden>
      <svg viewBox={`0 0 ${BARS * 10} ${H}`} preserveAspectRatio="none" width="100%" height={H} className="block">
        {bars.map((v, i) => {
          const h = Math.max(4, v * (H - 4));
          return <rect key={i} x={i * 10 + 2} y={(H - h) / 2} width={6} height={h} rx={3} fill="var(--blue)" opacity={playing && i / BARS < p ? 1 : playing ? 0.35 : 0.8} />;
        })}
        {playing && <line x1={p * BARS * 10} x2={p * BARS * 10} y1={0} y2={H} stroke="var(--red)" strokeWidth={2} vectorEffect="non-scaling-stroke" />}
      </svg>
    </div>
  );
}
