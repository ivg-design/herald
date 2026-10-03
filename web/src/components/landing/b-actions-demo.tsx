"use client";
import { useState } from "react";
import { AnimatePresence } from "framer-motion";
import { History } from "lucide-react";
import LiveBanner from "@/components/mock/LiveBanner";

/** The Deploy action of a real banner: press it and the button row becomes an inline Yes/Cancel strip. */
export default function ActionsDemo() {
  const [shown, setShown] = useState(true);
  const [run, setRun] = useState(0);
  return (
    <div className="w-full max-w-[460px]">
      {/* Reserved stage: as tall as the banner's tallest state (the Deploy confirmation wrapped onto two rows at 390 px),
          top-anchored, so no click moves anything below it. The re-show button lands in the same stage. */}
      <div className="hb-stage stage-actions">
        <AnimatePresence>
          {shown && (
            <LiveBanner
              key={run}
              app="CI Bot" icon="ci"
              items={[{ id: "d", title: "Build 4f2a passed", body: "All 214 tests passed on main." }]}
              buttons={[
                { label: "Open log", role: "open", url: "ci.example.com/4f2a" },
                { label: "Deploy", role: "deploy", primary: true },
                { label: "Dismiss", role: "dismiss" },
              ]}
              confirmText="Deploy 4f2a to production?"
              onClose={() => setShown(false)}
            />
          )}
        </AnimatePresence>
        {!shown && (
          <button type="button" className="btn btn-ghost btn-sm hb-stage-note" onClick={() => { setRun((r) => r + 1); setShown(true); }}>
            <History size={15} aria-hidden /> Re-show from History
          </button>
        )}
      </div>
    </div>
  );
}
