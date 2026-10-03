import DesignerShowcase, { type ShotDims } from "@/components/motion/DesignerShowcase";
import GridBanner from "@/components/rive/GridBanner";

/**
 * Compact head for this section only: title, body and the Rive piece in one row (the Designer capture and its six
 * notes must fit the screen when the anchor lands). Same markup contract as SectionHead: a `.sec-head` whose first
 * cell is the `title` slot around an h2 `.display .display-l`.
 */
export default function Designer({ shots }: { shots: { light?: ShotDims; dark?: ShotDims } }) {
  return (
    <section id="designer" className="section">
      <div className="shell">
        <DesignerShowcase
          shots={shots}
          head={
            <header className="sec-head dz-head g col-span-full">
              <div className="cell col-span-full lg:col-span-5" data-filled="false">
                <span className="slot" aria-hidden>title</span>
                <h2 className="display display-l">A grid, not a form. Any size.</h2>
              </div>
              <div className="cell col-span-full lg:col-span-4" data-filled="false">
                <span className="slot" aria-hidden>body</span>
                <p className="lede">
                  As many rows and columns as the banner needs, merged where you like. Drop fields, images, badges,
                  buttons, progress bars, <span className="nowrap">SF Symbols</span> and Rive animations into cells; align them on nine points; decide
                  whether an empty field collapses or holds its place.
                </p>
              </div>
              <div className="cell dz-rive col-span-full lg:col-span-3" data-filled="false">
                <span className="slot" aria-hidden>rive</span>
                <GridBanner />
              </div>
            </header>
          }
        />
      </div>
    </section>
  );
}
