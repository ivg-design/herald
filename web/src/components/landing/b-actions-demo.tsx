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
      <div className="min-h-[148px]">
        <AnimatePresence>
          {shown && (
            <LiveBanner
              key={run}
              app="CI Bot"
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
      </div>
      {!shown && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => { setRun((r) => r + 1); setShown(true); }}>
          <History size={15} aria-hidden /> Re-show from History
        </button>
      )}
    </div>
  );
}
