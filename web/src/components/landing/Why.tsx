import Comparison from "./a-compare";
import SideBySide from "./b-side-by-side";

const POINTS = [
  { lead: "Persistent", body: "Banners stay until you deal with them. Snooze returns them later; dismiss sends them to history." },
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
              A system alert can stay on screen, but it is one Apple template with the buttons the app
              registered, and it can take focus. A Herald banner is laid out by you, acts on your Mac, never takes focus, and every
              one lands in a searchable history.
            </p>
          </div>
          <SideBySide />
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
