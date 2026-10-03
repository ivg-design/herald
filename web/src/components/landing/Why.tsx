import { ArrowUpToLine, History, Layers } from "lucide-react";
import Comparison from "./a-compare";

const PILLARS = [
  {
    Icon: Layers,
    title: "Persistent",
    body: "Banners live on your screen until you deal with them. Snooze returns them later; dismiss sends them to history.",
  },
  {
    Icon: ArrowUpToLine,
    title: "Always on top, never in the way",
    body: "Status-bar level panels that never take key or main window status. Your keystrokes keep going where they were going.",
  },
  {
    Icon: History,
    title: "Everything remembered",
    body: "Every banner, every spoken message, every action lands in a searchable per-app history you can re-show or export.",
  },
];

export default function Why() {
  return (
    <section id="why" className="section section-paper on-paper">
      <div className="shell">
        <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between lg:gap-10">
          <div className="min-w-0 lg:max-w-[820px]">
            <p className="eyebrow">Why Herald</p>
            <h2 className="display" style={{ fontSize: "clamp(36px, 5.2vw, 64px)" }}>
              You can&rsquo;t restyle a macOS notification, and you can&rsquo;t get one back. Herald fixes both.
            </h2>
            <p className="lede">
              Even set to stay on screen, a system alert is one fixed template, and once it&rsquo;s dismissed
              it&rsquo;s gone. Herald banners use the layout you design on a 3×4 grid, and every one lands in a
              searchable history.
            </p>
          </div>
          <span
            aria-hidden
            className="font-display italic leading-[0.8] text-accent-on-paper lg:pb-2"
            style={{
              fontFamily: "var(--font-display)",
              color: "var(--accent-on-paper)",
              fontSize: "clamp(110px, 18vw, 260px)",
              whiteSpace: "nowrap",
            }}
          >
            5 s
          </span>
        </div>
        <Comparison />
        <ul className="mt-12 grid list-none gap-8 p-0 md:grid-cols-3">
          {PILLARS.map(({ Icon, title, body }) => (
            <li key={title}>
              <div className="flex items-center gap-3">
                <Icon size={22} aria-hidden style={{ color: "var(--accent-on-paper)" }} className="shrink-0" />
                <h3 className="m-0 text-[18px] font-medium leading-tight">{title}</h3>
              </div>
              <p className="mt-2 pl-[34px] text-[13px] leading-[1.6] text-paper-muted">{body}</p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
