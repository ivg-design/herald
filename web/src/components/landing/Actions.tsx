"use client";
import WordFlipper, { type FlipPhrase } from "@/components/motion/WordFlipper";
import { nowrapText } from "@/lib/nowrap";
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

export default function Actions() {
  return (
    <section id="actions" className="section">
      <div className="shell g">
        <div className="col-span-full">
          <h2 className="display display-l">
            Buttons that
            <WordFlipper phrases={PHRASES} />
          </h2>
          <p className="lede !max-w-[78ch]">
            {nowrapText("An app ships its own actions in the manifest. You can relabel, hide, reorder them, or add your own: open a URL, run a shell command or script, trigger an Apple Shortcut, call back into the app. Dangerous ones ask first, inline, without a dialog.")}
          </p>
        </div>

        <div className="col-span-full mt-6 lg:col-span-6">
          <ActionsDemo />
        </div>
        <div className="col-span-full mt-6 lg:col-span-6">
          <h3 className="display display-m">Per app or per template</h3>
          <p className="body mt-4">
            Mark an action as needing confirmation and Herald swaps the button row for a yes/no strip inside the banner. Press Deploy on the banner to see it. Callbacks report success, failure or still-running, so a banner is only dismissed when the thing actually happened.
          </p>
        </div>
      </div>
    </section>
  );
}
