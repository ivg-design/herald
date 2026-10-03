"use client";
import { useState } from "react";
import { AnimatePresence } from "framer-motion";
import { History } from "lucide-react";
import LiveBanner from "@/components/mock/LiveBanner";

export default function CloudMock() {
  const [shown, setShown] = useState(true);
  const [run, setRun] = useState(0);
  return (
    <div className="w-full max-w-[480px] lg:ml-auto">
      <div className="min-h-[200px]">
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
      </div>
      {shown ? (
        <p className="readout mt-3 mb-0 text-right">Type a reply or press Record. Nothing leaves this page.</p>
      ) : (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setRun((r) => r + 1); setShown(true); }}>
          <History size={15} aria-hidden /> Re-show from History
        </button>
      )}
    </div>
  );
}
