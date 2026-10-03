"use client";

import { useEffect, useRef } from "react";
import { HeraldCards, StackHeader } from "./HeraldHost";
import { useHeraldInternal } from "./internal";

/** In-flow slot in the hero. While it is on screen the page's Herald draws its banners here. */
export default function HeroDock() {
  const h = useHeraldInternal();
  const { setDocked } = h;
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      (es) => {
        const e = es[es.length - 1];
        // Docked until the dock has been scrolled PAST (bottom edge above the viewport top).
        setDocked(e.isIntersecting || e.boundingClientRect.bottom >= 0);
      },
      { threshold: [0, 0.01, 0.2] },
    );
    io.observe(el);
    return () => {
      io.disconnect();
      setDocked(false);
    };
  }, [setDocked]);

  return (
    <div className="w-full">
      <div ref={ref} className="hd" data-docked={h.docked}>
        <span aria-hidden className="hd-tag mono">your grid · any rows × columns</span>
        <StackHeader />
        <div className="hb-cards" aria-label="Herald banners" role="region">
          <HeraldCards cards={h.cards} stagger />
          {h.cards.length === 0 && h.held === 0 && (
            <p className="m-0 rounded-xl border border-dashed border-line p-4 text-[13.5px] text-muted" role="status">
              All clear. Everything you dismissed is in History; send one with Run it below.
            </p>
          )}
        </div>
        {h.held > 0 && (
          <p className="hb-heldline" role="status">
            {h.held} held until {h.heldUntil}
            <button type="button" className="hb-pill-btn" onClick={h.showHeld}>Show anyway</button>
          </p>
        )}
      </div>
      <p className="mt-3 max-w-[408px] text-[12.5px] leading-snug text-muted">
        Try Deploy, Snooze or ×. They stay until you do.
        <span role="status" aria-live="polite">
          {h.history > 0 ? ` ${h.history} dismissed · kept in History.` : ""}
        </span>
      </p>
    </div>
  );
}
