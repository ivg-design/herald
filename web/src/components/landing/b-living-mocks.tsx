"use client";
import { useEffect, useId, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { Play, Plus, Send, Square } from "lucide-react";
import { useHerald } from "@/components/herald/useHerald";
import { playVoice, stopVoice, usePlayingKey } from "@/components/herald/voice";
import LiveBanner, { type BItem } from "@/components/mock/LiveBanner";
import Wave from "./b-wave";

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
    <div>
      <div className="min-h-[104px]">
        <AnimatePresence>
          {shown && items.length > 0 && (
            <LiveBanner
              key="stack"
              app="Gmail · @rive.app" icon="mail"
              items={items}
              onClose={() => setShown(false)}
              onDismissItem={(id) => setItems((i) => i.filter((x) => x.id !== id))}
            />
          )}
        </AnimatePresence>
        {(!shown || items.length === 0) && <p className="readout m-0">Dismissed. It stays in History.</p>}
      </div>
      <button type="button" className="btn btn-ghost btn-sm mt-4" onClick={add}>
        <Plus size={14} aria-hidden /> +1 from the same sender
      </button>
      <p className="readout m-0 mt-3">The count goes up; click the banner to fan the stack out.</p>
    </div>
  );
}

const T0 = 18 * 60; // the bar starts at 18:00 and runs 24 h
const TW = 14; // handle width in px (matches --tw in night.css)
const clock = (min: number) => {
  const m = ((min % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
};
/** Left offset of minute `v` on the bar, corrected for the handle width so a handle's centre sits on its time. */
const pos = (v: number) => `calc(${(v / 1440) * 100}% + ${(0.5 - v / 1440) * TW}px)`;
const TICKS = [0, 180, 360, 540, 720, 900, 1080, 1260, 1440];

export function QuietMock() {
  const id = useId();
  const [from, setFrom] = useState(4 * 60); // 22:00
  const [to, setTo] = useState(13 * 60); // 07:00
  const [sound, setSound] = useState(true);
  const [voice, setVoice] = useState(true);
  const [hold, setHold] = useState(false);
  const herald = useHerald();
  const [outcome, setOutcome] = useState("");
  const pretend = herald.quiet.pretendNow !== undefined;
  const STEP = 30;
  const push = (p: { from?: number; to?: number; sound?: boolean; voice?: boolean; hold?: boolean }) => {
    const f = p.from ?? from, t = p.to ?? to;
    herald.setQuiet({
      from: (T0 + f) % 1440,
      to: (T0 + t) % 1440,
      muteSound: p.sound ?? sound,
      muteVoice: p.voice ?? voice,
      hold: p.hold ?? hold,
    });
  };
  const sendOne = () => {
    const quiet = herald.isQuiet();
    const until = clock(T0 + to);
    herald.send({ app: "webwatcher.email", appName: "WebWatcher · Email", icon: "mail", title: "Invoice #4021", body: "Acme Billing", speak: true });
    if (!quiet) setOutcome("Shown, with voice");
    else if (hold) setOutcome(`Held until ${until}`);
    else {
      const m = [voice && "voice", sound && "sound"].filter(Boolean).join(" and ");
      setOutcome(`Shown${m ? `, ${m} muted` : ""}: it is quiet until ${until}`);
    }
  };
  const a = clock(T0 + from);
  const b = clock(T0 + to);
  const muted = [voice && "voice", sound && "sound"].filter(Boolean).join(" and ");
  const sentence = `${muted ? `${muted} muted` : "nothing muted"} ${a}–${b}${hold ? ", banners held until morning" : ""}`;
  const lo = from / 1440, hi = to / 1440;
  const [real, setReal] = useState<number | null>(null);
  const { nowMinute } = herald;
  const pn = herald.quiet.pretendNow;
  useEffect(() => {
    const tick = () => setReal(nowMinute());
    tick();
    const t = window.setInterval(tick, 20000);
    return () => window.clearInterval(t);
  }, [nowMinute, pn]);
  const nowMin = real !== null ? (real - T0 + 1440) % 1440 : null;
  return (
    <div className="contents">
      <div className="col-span-full mt-8 min-w-0 lg:col-span-4">
        <h3 className="display display-m m-0">Quiet hours</h3>
        <p className="body mt-4 max-w-[44ch]">Pick windows where voice and sound stay off and, if you want, banners wait. Per app overrides for the ones that may wake you.</p>
      </div>
      <p className="col-span-full m-0 min-w-0 text-[17px] font-medium lg:col-span-8 lg:self-end lg:text-right" role="status" aria-live="polite" id={id}>{sentence}</p>
      <div className="col-span-full min-w-0">
        <div className="qh">
          {nowMin !== null && <div className="qh-now" style={{ left: pos(nowMin) }}><span>now {clock(T0 + nowMin)}</span></div>}
          <div className="qh-bar">
            <div className="qh-band" style={{ left: `calc(${lo * 100}% - ${lo * TW}px)`, width: `calc(${(hi - lo) * 100}% + ${1 - (hi - lo)} * ${TW}px)` }} aria-hidden>
              <span>{a}</span><span>{b}</span>
            </div>
            <input type="range" min={0} max={1440} step={STEP} value={from} aria-label="Quiet hours start" onChange={(e) => { const v = Math.min(Number(e.target.value), to - STEP); setFrom(v); push({ from: v }); }} className="qh-range" />
            <input type="range" min={0} max={1440} step={STEP} value={to} aria-label="Quiet hours end" onChange={(e) => { const v = Math.max(Number(e.target.value), from + STEP); setTo(v); push({ to: v }); }} className="qh-range" />
          </div>
          <div className="qh-ticks" aria-hidden>
            {TICKS.map((t) => <span key={t} className="qh-tick" data-minor={t % 360 !== 0 || undefined} style={{ left: pos(t) }}>{clock(T0 + t)}</span>)}
          </div>
        </div>
        <div className="mt-4 flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
          <fieldset className="qh-checks m-0 flex flex-wrap gap-x-5 gap-y-0 border-0 p-0">
            <legend className="sr-only">Quiet hours rules</legend>
            <label><input type="checkbox" checked={sound} onChange={(e) => { setSound(e.target.checked); push({ sound: e.target.checked }); }} />mute sound</label>
            <label><input type="checkbox" checked={voice} onChange={(e) => { setVoice(e.target.checked); push({ voice: e.target.checked }); }} />no voice</label>
            <label><input type="checkbox" checked={hold} onChange={(e) => { setHold(e.target.checked); push({ hold: e.target.checked }); }} />hold banners until morning</label>
          </fieldset>
          <div className="flex flex-wrap items-center gap-3">
            <button type="button" aria-pressed={pretend} onClick={() => herald.setQuiet({ pretendNow: pretend ? undefined : 23 * 60 + 30 })} className="btn btn-ghost btn-sm">
              Pretend it is 23:30
            </button>
            <button type="button" onClick={sendOne} className="btn btn-ghost btn-sm">
              <Send size={13} aria-hidden /> Send one now
            </button>
          </div>
        </div>
        <p className="readout m-0 mt-3 min-h-[1.4em]" role="status" aria-live="polite" aria-label="Quiet hours outcome">{outcome}</p>
      </div>
    </div>
  );
}

const KEY = "living-voice";

export function VoiceMock() {
  const playing = usePlayingKey() === KEY;
  return (
    <div>
      <Wave sample="voice-sample" playing={playing} />
      <p className="m-0 mt-4 max-w-[44ch] text-[20px] font-medium leading-snug">&ldquo;Build passed. One hundred forty-two tests, zero failures.&rdquo;</p>
      <button type="button" onClick={() => (playing ? stopVoice() : playVoice(KEY, "voice-sample"))} aria-pressed={playing} className="btn btn-ghost btn-sm mt-4">
        {playing ? <Square size={13} aria-hidden /> : <Play size={13} aria-hidden />}
        {playing ? "Stop" : "Play"}
      </button>
      <p className="readout m-0 mt-3">Kokoro, rendered on the Mac. This is the real voice; the text always lands in History.</p>
    </div>
  );
}
