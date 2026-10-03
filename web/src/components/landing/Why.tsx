import Comparison from "./a-compare";
import SideBySide from "./b-side-by-side";
import SectionHead from "./SectionHead";

export default function Why() {
  return (
    <section id="why" className="section why">
      <div className="shell">
        <SectionHead
          title={<>You can&rsquo;t restyle a macOS notification, and you can&rsquo;t get one back. Herald fixes both.</>}
          titleCols="lg:col-span-12"
          ledeCols="order-1 lg:order-none lg:col-span-4 lg:col-start-1 lg:row-start-2"
          asideSlot="alert"
          asideCols="order-2 lg:order-none lg:col-span-8 lg:col-start-5 lg:row-start-2"
          lede={
            <>
              A system alert can stay on screen, but it is one Apple template with the buttons the app
              registered, and it can take focus. A Herald banner is laid out by you, acts on your Mac, never takes focus, and every
              one lands in a searchable history.
            </>
          }
          aside={<SideBySide />}
        />
        <Comparison />
      </div>
    </section>
  );
}
