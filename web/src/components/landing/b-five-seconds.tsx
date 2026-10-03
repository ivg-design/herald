"use client";

import { Bell } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { useHerald } from "@/components/herald/useHerald";

type Banner = "none" | "in" | "out";

/** The "5 s" numeral is a live countdown for a system banner; the same alert goes to the page's Herald. */
export default function FiveSeconds() {
  const herald = useHerald();
  const [n, setN] = useState(5);
  const [banner, setBanner] = useState<Banner>("none");
  const [gone, setGone] = useState(false);
  const [sent, setSent] = useState(false);
  const timers = useRef<number[]>([]);

  const clear = useCallback(() => {
    timers.current.forEach((t) => window.clearTimeout(t));
    timers.current = [];
  }, []);
  useEffect(() => clear, [clear]);

  const run = () => {
    clear();
    const at = (ms: number, fn: () => void) => {
      timers.current.push(window.setTimeout(fn, ms));
    };
    setN(5);
    setGone(false);
    setBanner("none");
    // restart the enter animation cleanly on a repeat press
    at(16, () => setBanner("in"));
    for (let k = 1; k <= 5; k++) at(16 + k * 1000, () => setN(5 - k));
    at(16 + 5000, () => setBanner("out"));
    at(16 + 5400, () => {
      setBanner("none");
      setGone(true);
    });
    at(16 + 7200, () => setN(5));
    setSent(true);
    herald.send({
      app: "ci.bot",
      appName: "CI Bot",
      icon: "ci",
      title: "Build passed",
      body: "142 tests, 0 failures · main",
      buttons: [
        { label: "Open log", role: "open", primary: true, url: "ci.example.com/142" },
        { label: "Snooze", role: "snooze" },
      ],
    });
  };

  return (
    <div className="fs">
      <div className="fs-num">
        <span key={n} className="fs-glyph display" aria-hidden>
          {n}&nbsp;s
        </span>
        <span className="sr-only">Countdown: {n} seconds</span>
      </div>
      <div className="fs-side">
      <button type="button" className="btn btn-ghost fs-btn" onClick={run} aria-label="Send the same alert to both">
        Send the same alert to both
      </button>
      {banner !== "none" && (
        <div className={`sysn sysn-${banner}`} data-testid="system-banner">
          <span className="sysn-icon" aria-hidden>
            <Bell size={26} strokeWidth={1.75} />
          </span>
          <span className="sysn-text">
            <span className="sysn-title">Build passed</span>
            <span className="sysn-body">142 tests, 0 failures</span>
          </span>
          <span className="sysn-now">now</span>
        </div>
      )}
      <div className="fs-lines">
        <p className="fs-gone" data-testid="gone-line" aria-live="polite">
          {gone ? "Gone. It is not in any history." : ""}
        </p>
        <p role="status" aria-live="polite" className="fs-herald" data-testid="herald-line">
          {sent
            ? herald.docked
              ? "Herald\u2019s copy is in the hero above. It stays until you deal with it."
              : "Herald\u2019s copy is in the stack at the top right. It stays until you deal with it."
            : ""}
        </p>
      </div>
      </div>
    </div>
  );
}
