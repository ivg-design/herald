import DesignerShowcase, { type ShotDims } from "@/components/motion/DesignerShowcase";

export default function Designer({ shots }: { shots: { light?: ShotDims; dark?: ShotDims } }) {
  return (
    <section id="designer" className="section">
      <div className="shell">
        <DesignerShowcase
          shots={shots}
          intro={
            <>
              <h2 className="display display-l">A grid, not a form. Any size.</h2>
              <p className="lede">
                As many rows and columns as the banner needs, merged where you like. Drop fields, images, badges,
                buttons, progress bars, <span className="nowrap">SF Symbols</span> and Rive animations into cells; align them on nine points; decide
                whether an empty field collapses or holds its place.
              </p>
            </>
          }
        />
      </div>
    </section>
  );
}
