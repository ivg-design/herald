import { EyeOff, MessageCircle, ShieldCheck, Volume2 } from "lucide-react";
import CloudMock from "./b-cloud-mock";

const POINTS = [
  { icon: Volume2, text: "Speaks the message out loud with a local voice, nothing leaves your Mac" },
  { icon: MessageCircle, text: "Reply by typing, or hold Record and talk; the agent gets your words and the transcript" },
  { icon: EyeOff, text: "Not at your Mac? The relay queues it and the agent gets a receipt the moment it is shown" },
  { icon: ShieldCheck, text: "One switch to enable; the agent approves itself with a code you confirm in a banner; revoke any time" },
];

export default function CloudRelay() {
  return (
    <section id="cloud" className="section section-dark" style={{ paddingBlock: "clamp(72px, 10vw, 120px)" }}>
      <div className="shell grid grid-cols-[minmax(0,1fr)] gap-12 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,0.9fr)] lg:gap-16">
        <div className="min-w-0">
          <p className="eyebrow">From anywhere · Cloud relay</p>
          <h2 className="display max-w-[12ch] text-[clamp(44px,6vw,72px)]">Let your agent speak to you.</h2>
          <p className="lede">
            An agent running in the cloud, <span className="nowrap">ChatGPT</span>, <span className="nowrap">Codex</span>, <span className="nowrap">Claude</span>, can reach your Mac even when you&rsquo;re not looking at it. It sends a banner that reads itself aloud, asks you a question, and waits for your answer: typed, or spoken into the banner with one press.
          </p>
          <ul className="m-0 mt-10 flex list-none flex-col gap-5 p-0">
            {POINTS.map(({ icon: Icon, text }) => (
              <li key={text} className="flex max-w-[56ch] gap-4 text-[15px] leading-snug">
                <Icon aria-hidden className="mt-0.5 size-[18px] shrink-0 text-accent" />
                <span>{text}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="w-full min-w-0 lg:self-end"><CloudMock /></div>
      </div>
    </section>
  );
}
