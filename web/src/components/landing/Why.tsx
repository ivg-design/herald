import Comparison from "./a-compare";
import SideBySide from "./b-side-by-side";

export default function Why() {
  return (
    <section id="why" className="section why">
      <div className="shell">
        <div className="g items-start">
          <div className="col-span-full min-w-0 lg:col-span-7">
            <h2 className="display display-l">
              You can&rsquo;t restyle a macOS notification, and you can&rsquo;t get one back. Herald fixes both.
            </h2>
            <p className="lede">
              A system alert can stay on screen, but it is one Apple template with the buttons the app
              registered, and it can take focus. A Herald banner is laid out by you, acts on your Mac, never takes focus, and every
              one lands in a searchable history.
            </p>
          </div>
          <div className="col-span-full min-w-0 max-lg:mt-8 lg:col-span-5 lg:col-start-8">
            <SideBySide />
          </div>
        </div>
        <Comparison />
      </div>
    </section>
  );
}
