"use client";
import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "framer-motion";
import { Mic } from "lucide-react";
import { useInViewOnce } from "./b-hooks";
import MiniWave from "./b-wave";

const RECEIPTS = ["received", "displayed", "spoken", "replied"];

export default function CloudMock() {
  const reduced = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInViewOnce(ref, 0.5);
  const [lit, setLit] = useState(0);

  useEffect(() => {
    if (reduced || !seen) return;
    const timers = RECEIPTS.map((_, i) => setTimeout(() => setLit(i + 1), 500 + i * 650));
    return () => timers.forEach(clearTimeout);
  }, [reduced, seen]);
  const count = reduced ? RECEIPTS.length : lit;

  return (
    <div ref={ref} className="w-full max-w-[480px] lg:ml-auto">
      <div aria-hidden className="rounded-xl border border-line bg-surface p-4">
        <div className="flex items-start gap-3">
          <span className="size-9 shrink-0 rounded-lg bg-surface-2" />
          <div className="min-w-0 flex-1">
            <p className="m-0 text-[11px] text-muted">Claude · cloud session</p>
            <p className="m-0 text-[16px] font-semibold">Deploy to production now?</p>
          </div>
          <MiniWave className="h-6 shrink-0" bars={10} />
        </div>
        <p className="mt-3 mb-4 text-[13px] leading-snug text-muted">All 214 tests passed on main. Say the word and I&rsquo;ll ship 4f2a to prod.</p>
        <div className="flex gap-2">
          <div className="flex h-10 min-w-0 flex-1 items-center rounded-lg border border-line bg-bg px-3 text-[13px] text-muted">Type a reply…</div>
          <span className="inline-flex h-10 items-center gap-1.5 rounded-lg bg-signal px-3.5 text-[13px] font-semibold text-white"><Mic className="size-4" />Record</span>
          <span className="inline-flex h-10 items-center rounded-lg bg-accent px-3.5 text-[13px] font-semibold text-accent-ink">Send</span>
        </div>
      </div>
      <p className="mt-3 mb-0 text-right text-[12px] text-muted">
        <span className="sr-only">Receipts: received, displayed, spoken, replied.</span>
        <span aria-hidden>
          Receipts:{" "}
          {RECEIPTS.map((r, i) => (
            <span key={r} className="transition-opacity duration-500" style={{ opacity: i < count ? 1 : 0.3, color: i < count ? "var(--ink)" : undefined }}>
              {r}{i < RECEIPTS.length - 1 ? " · " : ""}
            </span>
          ))}
        </span>
      </p>
    </div>
  );
}
