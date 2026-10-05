"use client";
import { useEffect, useRef } from "react";
import { asset } from "@/lib/config";

/**
 * A screen recording of a real Herald banner whose left cell plays a Rive character (it blinks and looks around from
 * the file's own scripts). Muted, looping, and played only while it is on screen; with Reduce Motion it stays on
 * its first frame and shows the browser's controls instead.
 */
export default function RiveBannerVideo() {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const v = ref.current;
    if (!v) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { v.controls = true; return; }
    const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) v.play().catch(() => {}); else v.pause(); }, { threshold: 0.35 });
    io.observe(v);
    return () => io.disconnect();
  }, []);
  return (
    <figure className="m-0">
      <video
        ref={ref}
        className="block w-full h-auto rounded-[14px] border border-white/10"
        width={820}
        height={288}
        muted
        loop
        playsInline
        preload="metadata"
        poster={asset("/video/rive-banner.jpg")}
        aria-label="A Herald banner whose avatar, a Rive animation, blinks and looks around"
      >
        <source src={asset("/video/rive-banner.mp4")} type="video/mp4" />
      </video>
      <figcaption className="body mt-3 text-[13px] opacity-70">A real banner, recorded on a Mac. The avatar is a Rive file playing in a grid cell.</figcaption>
    </figure>
  );
}
