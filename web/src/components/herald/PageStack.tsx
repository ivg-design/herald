"use client";

import { useState } from "react";
import { HeraldCards, StackHeader } from "./HeraldHost";
import { useHeraldInternal } from "./internal";

const SHOWN = 3;

/**
 * The page's Herald when the hero dock is off screen: a fixed overlay under the header. There is no floating
 * pill; the header bell (Herald's menu-bar bell) is the compact state. Cards stay mounted while collapsed.
 */
export default function PageStack() {
  const h = useHeraldInternal();
  const [all, setAll] = useState(false);
  if (h.docked || (h.cards.length === 0 && h.held === 0)) return null;

  const open = h.expanded;
  const shown = all ? h.cards : h.cards.slice(0, SHOWN);
  const more = h.cards.length - SHOWN;

  return (
    <div
      id="herald-overlay"
      className="hb-overlay"
      onPointerEnter={() => h.setHold("hover", true)}
      onPointerLeave={() => h.setHold("hover", false)}
      onFocus={() => h.setHold("focus", true)}
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget as Node | null)) h.setHold("focus", false);
      }}
    >
      <div className="hb-stack" data-open={open}>
        <StackHeader full />
        <div className="hb-cards">
          <HeraldCards cards={shown} />
        </div>
        {more > 0 && (
          <button type="button" className="hb-more" aria-expanded={all} onClick={() => setAll((v) => !v)}>
            {all ? "Show fewer" : `+${more} more`}
          </button>
        )}
      </div>
    </div>
  );
}
