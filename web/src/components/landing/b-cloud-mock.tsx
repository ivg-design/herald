"use client";
import { useState } from "react";
import { AnimatePresence } from "framer-motion";
import { History } from "lucide-react";
import LiveBanner from "@/components/mock/LiveBanner";

export default function CloudMock() {
  const [shown, setShown] = useState(true);
  const [run, setRun] = useState(0);
  return (
    <div className="w-full xl:min-w-[520px]">
      {/* Reserved stage: the reply banner's tallest state (transcript line plus receipts, wrapped at 390 px). */}
      <div className="hb-stage stage-cloud">
        <AnimatePresence>
          {shown && (
            <LiveBanner
              key={run}
              app="Claude · cloud session" icon="claude" speak="voice-cloud"
              items={[{ id: "c", title: "Deploy to production now?", body: "All 214 tests passed on main. Say the word and I’ll ship 4f2a to prod." }]}
              reply={{ transcript: "Yes, ship it to production." }}
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
      <p className={`readout mb-0 mt-3 min-h-[3em] leading-[1.5]${shown ? "" : " invisible"}`} aria-hidden={!shown}>Type a reply or press Record. Nothing leaves this page.</p>
    </div>
  );
}
