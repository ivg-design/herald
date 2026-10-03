import DesignerShowcase, { type ShotDims } from "@/components/motion/DesignerShowcase";
import GridBanner from "@/components/rive/GridBanner";
import SectionHead from "./SectionHead";

export default function Designer({ shots }: { shots: { light?: ShotDims; dark?: ShotDims } }) {
  return (
    <section id="designer" className="section">
      <div className="shell">
        <DesignerShowcase
          shots={shots}
          head={
            <SectionHead
              title="A grid, not a form. Any size."
              titleCols="lg:col-span-8"
              ledeCols="lg:col-span-8"
              asideSlot="rive"
              asideCols="lg:col-span-4"
              lede={
                <>
                  As many rows and columns as the banner needs, merged where you like. Drop fields, images, badges,
                  buttons, progress bars, <span className="nowrap">SF Symbols</span> and Rive animations into cells; align them on nine points; decide
                  whether an empty field collapses or holds its place.
                </>
              }
              aside={
                <>
                  <GridBanner />
                  <p className="dz-side-cap readout" aria-hidden>a 4 × 3 grid becomes a banner · click to replay</p>
                </>
              }
            />
          }
        />
      </div>
    </section>
  );
}
