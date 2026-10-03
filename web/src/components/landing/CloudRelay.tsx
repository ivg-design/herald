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
    <section id="cloud" className="section night">
      <div className="shell g">
        <div className="col-span-full min-w-0 lg:col-span-7">
          <h2 className="display display-l">Let your agent speak to you.</h2>
          <p className="lede">
            An agent running in the cloud, <span className="nowrap">ChatGPT</span>, <span className="nowrap">Codex</span>, <span className="nowrap">Claude</span>, can reach your Mac even when you&rsquo;re not looking at it. It sends a banner that reads itself aloud, asks you a question, and waits for your answer: typed, or spoken into the banner with one press.
          </p>
        </div>
        <ul className="col-span-full m-0 mt-6 flex min-w-0 list-none flex-col gap-5 p-0 lg:col-span-6 lg:row-start-2 lg:mt-8 lg:self-center">
          {POINTS.map(({ icon: Icon, text }) => (
            <li key={text} className="flex max-w-[56ch] gap-4 text-[16px] leading-snug">
              <Icon aria-hidden className="mt-0.5 size-[18px] shrink-0 text-blue" />
              <span>{text}</span>
            </li>
          ))}
        </ul>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-6 lg:col-start-7 lg:row-start-2 lg:mt-8 lg:self-center"><CloudMock /></div>
      </div>
    </section>
  );
}
