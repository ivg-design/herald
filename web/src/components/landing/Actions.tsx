"use client";
import { AlarmClock, Link2, SquareTerminal, Undo2, Workflow } from "lucide-react";
import WordFlipper, { type FlipPhrase } from "@/components/motion/WordFlipper";
import ActionsDemo from "./b-actions-demo";

/* Herald's real action kinds, each in its own face. Mobile floors are measured so the longest
   phrase still fits one line at 390px (358px of content). Widths in em at 100px:
   script 7.80, open 4.73, archive 7.59, ask 10.52, call 7.26, Shortcut 5.86, snooze 4.19. */
const PHRASES: FlipPhrase[] = [
  { text: "run a script.", fontFamily: "var(--font-mono)", fontSize: "clamp(38px, 5.4vw, 66px)", fontWeight: 700 },
  { text: "open the app.", fontFamily: "var(--font-display)", fontSize: "clamp(46px, 7vw, 84px)", fontStyle: "italic" },
  { text: "archive the mail.", fontFamily: "'Playfair Display', serif", fontSize: "clamp(42px, 6vw, 72px)", fontWeight: 700, fontStyle: "italic", googleFamily: "Playfair+Display:ital,wght@1,700" },
  { text: "ask before deploying.", fontFamily: "'Space Grotesk', sans-serif", fontSize: "clamp(32px, 5.4vw, 64px)", fontWeight: 700, googleFamily: "Space+Grotesk:wght@700" },
  { text: "call your app back.", fontFamily: "'Bebas Neue', sans-serif", fontSize: "clamp(46px, 7.2vw, 86px)", letterSpacing: "0.04em", googleFamily: "Bebas+Neue" },
  { text: "run a Shortcut.", fontFamily: "'Fraunces', serif", fontSize: "clamp(40px, 6vw, 72px)", fontWeight: 600, fontStyle: "italic", fontVariationSettings: '"opsz" 144', googleFamily: "Fraunces:ital,opsz,wght@1,144,600" },
  { text: "snooze till 9.", fontFamily: "'Caveat', cursive", fontSize: "clamp(54px, 8vw, 92px)", fontWeight: 700, googleFamily: "Caveat:wght@700" },
];

const LEDGER = [
  { icon: Link2, name: "URL", copy: "Open a page, a mail thread, a deep link." },
  { icon: SquareTerminal, name: "Command / script", copy: "Run a shell command or a script file with the banner's fields as arguments." },
  { icon: Workflow, name: "Apple Shortcut", copy: "Run any Shortcut via the shortcuts CLI; pass fields as input." },
  { icon: Undo2, name: "Callback", copy: "POST back to the issuing app; Herald waits for the outcome before dismissing." },
  { icon: AlarmClock, name: "Snooze / dismiss", copy: "Built-in. Snoozed banners vanish and return on time." },
];

export default function Actions() {
  return (
    <section id="actions" className="section section-dark">
      <div className="shell">
        <p className="eyebrow">Two-way actions</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]">
          Buttons that
          <WordFlipper phrases={PHRASES} />
        </h2>
        <p className="lede !max-w-[78ch]">
          An app ships its own actions in the manifest. You can relabel, hide, reorder them, or add your own: open a URL, run a shell command or script, trigger an Apple Shortcut, call back into the app. Dangerous ones ask first, inline, without a dialog.
        </p>

        <ul className="m-0 mt-10 list-none border-t border-line p-0">
          {LEDGER.map(({ icon: Icon, name, copy }) => (
            <li key={name} className="grid grid-cols-1 gap-1 border-b border-line py-4 md:grid-cols-[minmax(200px,260px)_1fr] md:items-baseline md:gap-6">
              <div className="flex items-center gap-4">
                <Icon aria-hidden className="size-[18px] shrink-0 text-accent" />
                <span className="text-[17px] font-medium">{name}</span>
              </div>
              <p className="m-0 pl-[34px] text-[14px] leading-relaxed text-muted md:pl-0">{copy}</p>
            </li>
          ))}
        </ul>

        <div className="mt-12 grid gap-8 md:grid-cols-[minmax(0,460px)_1fr] md:items-start md:gap-14">
          <ActionsDemo />
          <div className="md:pt-2">
            <p className="eyebrow !mb-3">Confirmation gates</p>
            <h3 className="m-0 text-[clamp(20px,2vw,24px)] font-medium leading-snug">Per app or per template</h3>
            <p className="mt-3 max-w-[62ch] text-[16px] leading-relaxed text-muted">
              Mark an action as needing confirmation and Herald swaps the button row for a yes/no strip inside the banner. Press Deploy on the banner to see it. Callbacks report success, failure or still-running, so a banner is only dismissed when the thing actually happened.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
