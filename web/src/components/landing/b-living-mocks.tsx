"use client";
import { useId, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { Plus } from "lucide-react";
import LiveBanner, { type BItem } from "@/components/mock/LiveBanner";
import { WAVE } from "./b-wave";

const PANEL = "rounded-xl border border-paper-line bg-white p-4 min-h-[168px] text-paper-ink";
const SMALL = "text-[12px] text-paper-muted";

const SUBJECTS = ["Release notes 0.9", "Scripting update", "Office hours moved", "Invoice #4021", "Weekly digest", "Rive 0.9.1 is out", "Hiring: motion designer"];
const mail = (n: number): BItem => ({ id: `m${n}`, title: SUBJECTS[n % SUBJECTS.length], body: "Rive <hello@rive.app>" });

export function StackMock() {
  const [items, setItems] = useState<BItem[]>([mail(2), mail(1), mail(0)]);
  const [n, setN] = useState(3);
  const [shown, setShown] = useState(true);
  const add = () => {
    setShown(true);
    setItems((i) => [mail(n), ...(shown ? i : [])]);
    setN((v) => v + 1);
  };
  return (
    <div className={PANEL}>
      <div className="min-h-[104px]">
        <AnimatePresence>
          {shown && items.length > 0 && (
            <LiveBanner
              key="stack"
              app="Gmail · @rive.app"
              items={items}
              onClose={() => setShown(false)}
              onDismissItem={(id) => setItems((i) => i.filter((x) => x.id !== id))}
            />
          )}
        </AnimatePresence>
        {(!shown || items.length === 0) && <p className={`m-0 ${SMALL}`}>Dismissed. It stays in History.</p>}
      </div>
      <button type="button" className="mb-btn mt-3" onClick={add} style={{ background: "#e8edf2", color: "var(--paper-ink)" }}>
        <Plus size={14} aria-hidden /> +1 from the same sender
      </button>
      <p className={`m-0 mt-2 ${SMALL}`}>The count goes up; click the banner to fan the stack out.</p>
    </div>
  );
}

const T0 = 18 * 60; // the bar starts at 18:00 and runs 24 h
const clock = (min: number) => {
  const m = ((min % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
};

export function QuietMock() {
  const id = useId();
  const [from, setFrom] = useState(4 * 60); // 22:00
  const [to, setTo] = useState(13 * 60); // 07:00
  const [sound, setSound] = useState(true);
  const [voice, setVoice] = useState(true);
  const [hold, setHold] = useState(false);
  const STEP = 30;
  const a = clock(T0 + from);
  const b = clock(T0 + to);
  const muted = [voice && "voice", sound && "sound"].filter(Boolean).join(" and ");
  const sentence = `${muted ? `${muted} muted` : "nothing muted"} ${a}–${b}${hold ? ", banners held until morning" : ""}`;
  const pct = (v: number) => `${(v / 1440) * 100}%`;
  const thumb = "pointer-events-none absolute inset-0 m-0 h-full w-full appearance-none bg-transparent [&::-webkit-slider-thumb]:pointer-events-auto [&::-webkit-slider-thumb]:size-5 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-white [&::-webkit-slider-thumb]:bg-[#1b6fb8] [&::-webkit-slider-thumb]:cursor-grab [&::-moz-range-thumb]:pointer-events-auto [&::-moz-range-thumb]:size-5 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-white [&::-moz-range-thumb]:bg-[#1b6fb8]";
  return (
    <div className={PANEL}>
      <div className="relative h-5 rounded-full bg-[#e3e6ea]">
        <div className="absolute inset-y-0 rounded-full bg-accent" style={{ left: pct(from), width: pct(Math.max(to - from, 0)) }} />
        <input type="range" min={0} max={1440} step={STEP} value={from} aria-label="Quiet hours start" onChange={(e) => setFrom(Math.min(Number(e.target.value), to - STEP))} className={thumb} />
        <input type="range" min={0} max={1440} step={STEP} value={to} aria-label="Quiet hours end" onChange={(e) => setTo(Math.max(Number(e.target.value), from + STEP))} className={thumb} />
      </div>
      <div className={`mt-1.5 flex justify-between ${SMALL} mono`} aria-hidden>
        <span>18:00</span><span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span>
      </div>
      <p className="m-0 mt-2 text-[13px] font-medium" role="status" aria-live="polite" id={id}>{sentence}</p>
      <fieldset className={`m-0 mt-3 flex flex-wrap gap-x-4 gap-y-1 border-0 p-0 ${SMALL}`}>
        <legend className="sr-only">Quiet hours rules</legend>
        <label className="inline-flex min-h-8 items-center gap-1.5"><input type="checkbox" checked={sound} onChange={(e) => setSound(e.target.checked)} />mute sound</label>
        <label className="inline-flex min-h-8 items-center gap-1.5"><input type="checkbox" checked={voice} onChange={(e) => setVoice(e.target.checked)} />no voice</label>
        <label className="inline-flex min-h-8 items-center gap-1.5"><input type="checkbox" checked={hold} onChange={(e) => setHold(e.target.checked)} />hold banners until morning</label>
      </fieldset>
    </div>
  );
}

/** No audio sample ships with the site, so the waveform is a picture of one and does nothing. */
export function VoiceMock() {
  return (
    <div className={PANEL}>
      <div className="flex h-12 w-full items-end gap-[3px] p-1" aria-hidden>
        {WAVE.map((h, i) => (
          <span key={i} className="w-[5px] rounded-full bg-accent" style={{ height: `${Math.round(h * 100)}%` }} />
        ))}
      </div>
      <p className="m-0 mt-3 text-[13px] font-medium">“Build passed. One hundred forty-two tests.”</p>
      <p className={`m-0 mt-2 ${SMALL}`}>Kokoro, local, optional download · falls back to the system voice · text always lands in history</p>
    </div>
  );
}
