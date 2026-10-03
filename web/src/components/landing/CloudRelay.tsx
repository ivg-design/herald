import SectionHead from "./SectionHead";
import CloudMock from "./b-cloud-mock";

const POINTS = [
  "Speaks the message out loud with a local voice, nothing leaves your Mac.",
  "Reply by typing, or hold Record and talk; the agent gets your words and the transcript.",
  "Not at your Mac? The relay queues it and the agent gets a receipt the moment it is shown.",
  "One switch to enable; the agent approves itself with a code you confirm in a banner; revoke any time.",
];

export default function CloudRelay() {
  return (
    <section id="cloud" className="section night">
      <div className="shell g">
        <SectionHead
          title="Let your agent speak to you."
          titleCols="lg:col-span-9"
          ledeCols="lg:col-span-8"
          lede={
            <>
              An agent running in the cloud, <span className="nowrap">ChatGPT</span>, <span className="nowrap">Codex</span>, <span className="nowrap">Claude</span>, can reach your Mac even when you&rsquo;re not looking at it. It sends a banner that reads itself aloud, asks you a question, and waits for your answer: typed, or spoken into the banner with one press.
            </>
          }
        />
        <ul className="col-span-full m-0 min-w-0 list-none self-start border-t border-line p-0 lg:col-span-6">
          {POINTS.map((text) => (
            <li key={text} className="border-b border-line py-5 text-[17px] leading-snug">{text}</li>
          ))}
        </ul>
        <div className="cell col-span-full mt-2 min-w-0 self-start lg:col-span-6 lg:mt-0" data-filled="false" style={{ padding: "30px 16px 16px" }}>
          <span className="slot" aria-hidden>banner</span>
          <CloudMock />
        </div>
      </div>
    </section>
  );
}
