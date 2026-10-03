"use client";

import { useState } from "react";
import { AnimatePresence } from "framer-motion";
import { Plus } from "lucide-react";
import LiveBanner, { type BButton, type BItem } from "@/components/mock/LiveBanner";

interface Card { key: string; app: string; items: BItem[]; buttons: BButton[]; confirm?: string }

const CI_BUTTONS: BButton[] = [
  { label: "Open log", role: "open", primary: true, url: "ci.example.com/142" },
  { label: "Deploy", role: "deploy" },
  { label: "Snooze", role: "snooze" },
];

const INITIAL: Card[] = [
  {
    key: "ww",
    app: "WebWatcher · Email",
    items: [
      { id: "w3", title: "Office hours moved to Thursday", body: "Rive <hello@rive.app>" },
      { id: "w2", title: "Scripting update", body: "Rive <hello@rive.app>" },
      { id: "w1", title: "Release notes", body: "Rive <hello@rive.app>" },
    ],
    buttons: [{ label: "Open", role: "open", primary: true, url: "mail.google.com" }, { label: "Archive", role: "dismiss" }],
  },
  {
    key: "ae",
    app: "After Effects",
    items: [{ id: "ae1", title: "Render finished", body: "final_v3.mp4 · 02:14 · 1.2 GB" }],
    buttons: [{ label: "Show in Finder", role: "open", primary: true, url: "final_v3.mp4" }, { label: "Snooze", role: "snooze" }],
  },
  {
    key: "ci",
    app: "CI Bot",
    items: [{ id: "c142", title: "Build passed", body: "142 tests, 0 failures · main · 3m 12s" }],
    buttons: CI_BUTTONS,
    confirm: "Deploy build 4f2a to production?",
  },
];

const POOL: [string, string][] = [
  ["Build passed", "142 tests, 0 failures · main"],
  ["Deploy preview ready", "pr-318 · preview.example.com"],
  ["Lint: 3 warnings", "src/render.ts · main"],
  ["Build passed", "143 tests, 0 failures · main"],
];

/** Hero: three real-behaving banners and a control that sends another from the same sender. */
export default function BannerStack() {
  const [cards, setCards] = useState<Card[]>(INITIAL);
  const [gone, setGone] = useState(0);
  const [n, setN] = useState(0);

  const close = (key: string, members: number) => {
    setCards((c) => c.filter((x) => x.key !== key));
    setGone((g) => g + members);
  };
  const dismissItem = (key: string, id: string) => {
    setCards((c) => c.map((x) => (x.key === key ? { ...x, items: x.items.filter((i) => i.id !== id) } : x)));
    setGone((g) => g + 1);
  };
  const sendNew = () => {
    const [title, body] = POOL[n % POOL.length];
    const item: BItem = { id: `c-${n}`, title, body };
    setN((v) => v + 1);
    setCards((c) =>
      c.some((x) => x.key === "ci")
        ? c.map((x) => (x.key === "ci" ? { ...x, items: [item, ...x.items] } : x))
        : [...c, { ...INITIAL[2], items: [item] }],
    );
  };

  return (
    <div className="w-full" style={{ maxWidth: 520 }}>
      <div className="flex flex-col gap-3" role="region" aria-label="Interactive Herald banners">
        <AnimatePresence initial>
          {cards.map((c, i) => (
            <LiveBanner
              key={c.key}
              app={c.app}
              items={c.items}
              buttons={c.buttons}
              confirmText={c.confirm}
              delay={INITIAL.some((x) => x.key === c.key) && i < 3 ? i * 0.14 : 0}
              onClose={() => close(c.key, c.items.length)}
              onDismissItem={(id) => dismissItem(c.key, id)}
            />
          ))}
        </AnimatePresence>
        {cards.length === 0 && <p className="m-0 rounded-xl border border-line p-4 text-[14px] text-muted">All clear. Every banner you dismissed is in History.</p>}
      </div>
      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2">
        <button type="button" className="btn btn-ghost btn-sm" onClick={sendNew}>
          <Plus size={15} aria-hidden /> New notification from CI Bot
        </button>
        <p className="m-0 text-[12.5px] text-muted" aria-live="polite">
          {gone > 0 ? `${gone} dismissed · kept in History` : "Try Deploy, Snooze or ×"}
        </p>
      </div>
    </div>
  );
}
