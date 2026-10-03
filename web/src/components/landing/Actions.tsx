"use client";
import { useState } from "react";
import { AlarmClock, Link2, SquareTerminal, Undo2, Workflow } from "lucide-react";
import WordSwapper from "@/components/motion/WordSwapper";
import ConfirmDemo from "./b-confirm-demo";

const WORDS = ["run a script", "open the app", "archive the mail", "ask before deploying", "call your app back", "run a Shortcut", "snooze till 9"];

const LEDGER = [
  { icon: Link2, name: "URL", copy: "Open a page, a mail thread, a deep link." },
  { icon: SquareTerminal, name: "Command / script", copy: "Run a shell command or a script file with the banner's fields as arguments." },
  { icon: Workflow, name: "Apple Shortcut", copy: "Run any Shortcut via the shortcuts CLI; pass fields as input." },
  { icon: Undo2, name: "Callback", copy: "POST back to the issuing app; Herald waits for the outcome before dismissing." },
  { icon: AlarmClock, name: "Snooze / dismiss", copy: "Built-in. Snoozed banners vanish and return on time." },
];

export default function Actions() {
  const [active, setActive] = useState(0);
  return (
    <section id="actions" className="section section-dark">
      <div className="shell">
        <p className="eyebrow">Two-way actions</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]">
          <span className="sr-only">Buttons that do things.</span>
          <span aria-hidden>
            Buttons that <span className="block md:inline"><em><WordSwapper words={WORDS} staticWord="do things" onIndex={setActive} /></em></span>
          </span>
        </h2>
        <div className="mt-5 flex flex-wrap items-center gap-2" aria-hidden>
          <span className="mono mr-1 text-[12px] font-bold text-accent">rotates:</span>
          {WORDS.map((w, i) => (
            <span
              key={w}
              className="mono rounded-md px-2.5 py-1 text-[12px] text-accent transition-[opacity,background-color] duration-300"
              style={{ background: i === active ? "var(--accent-soft)" : "transparent", opacity: i === active ? 1 : 0.8, boxShadow: "inset 0 0 0 1px var(--accent-soft)" }}
            >
              {w}
            </span>
          ))}
        </div>
        <p className="lede !max-w-[78ch]">
          An app ships its own actions in the manifest. You can relabel, hide, reorder them, or add your own: open a URL, run a shell command or script, trigger an Apple Shortcut, call back into the app. Dangerous ones ask first, inline, without a dialog.
        </p>

        <ul className="m-0 mt-12 list-none p-0">
          {LEDGER.map(({ icon: Icon, name, copy }) => (
            <li key={name} className="grid grid-cols-1 gap-1 border-b border-line py-5 md:grid-cols-[minmax(200px,260px)_1fr] md:items-center md:gap-6 first:border-t md:first:border-t-0">
              <div className="flex items-center gap-4">
                <Icon aria-hidden className="size-[18px] shrink-0 text-accent" />
                <span className="text-[17px] font-medium">{name}</span>
              </div>
              <p className="m-0 pl-[34px] text-[14px] text-muted md:pl-0">{copy}</p>
            </li>
          ))}
        </ul>

        <div className="mt-14 grid gap-8 md:grid-cols-[minmax(0,440px)_1fr] md:items-center md:gap-14">
          <ConfirmDemo />
          <div>
            <h3 className="m-0 text-[clamp(20px,2vw,24px)] font-medium">Confirmation gates, per app or per template</h3>
            <p className="mt-3 max-w-[62ch] text-[16px] leading-relaxed text-muted">
              Mark an action as needing confirmation and Herald swaps the button row for a yes/no strip inside the banner. Callbacks report success, failure or still-running, so a banner is only dismissed when the thing actually happened.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
