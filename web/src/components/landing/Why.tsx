import Comparison from "./a-compare";
import FiveSeconds from "./b-five-seconds";

const POINTS = [
  { lead: "Persistent", body: "Banners live on your screen until you deal with them. Snooze returns them later; dismiss sends them to history." },
  { lead: "Always on top, never in the way", body: "Status-bar level panels that never take key or main window status. Your keystrokes keep going where they were going." },
  { lead: "Everything remembered", body: "Every banner, every spoken message, every action lands in a searchable per-app history you can re-show or export." },
];

export default function Why() {
  return (
    <section id="why" className="section section-paper on-paper why">
      <div className="shell">
        <div className="why-top">
          <div className="why-copy">
            <p className="eyebrow">Why Herald</p>
            <h2 className="display why-h" style={{ fontSize: "clamp(36px, 5.2vw, 64px)" }}>
              You can&rsquo;t restyle a macOS notification, and you can&rsquo;t get one back. Herald fixes both.
            </h2>
            <p className="lede">
              Even set to stay on screen, a system alert is one fixed template, and once it&rsquo;s dismissed
              it&rsquo;s gone. Herald banners use the layout you design on a grid of any size, and every one lands in a
              searchable history.
            </p>
            <FiveSeconds />
          </div>
          <p className="why-corner mono" aria-hidden>
            Herald&rsquo;s corner. Whatever you send lands here and stays until you deal with it.
          </p>
        </div>
        <Comparison />
        <ul className="why-points">
          {POINTS.map((p) => (
            <li key={p.lead}>
              <span className="why-lead">{p.lead}.</span> <span className="why-body">{p.body}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
