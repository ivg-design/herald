import DesignerShowcase from "@/components/motion/DesignerShowcase";

export default function Designer({ hasShots }: { hasShots: { light: boolean; dark: boolean } }) {
  return (
    <section id="designer" className="section section-paper on-paper">
      <div className="shell">
        <p className="eyebrow">The Designer</p>
        <h2 className="display" style={{ fontSize: "clamp(40px, 5.6vw, 72px)" }}>
          A grid, not a form. Any size.
        </h2>
        <p className="lede" style={{ maxWidth: "66ch" }}>
          As many rows and columns as the banner needs, merged where you like. Drop fields, images, badges,
          buttons, progress bars, SF Symbols and Rive animations into cells; align them on nine points; decide
          whether an empty field collapses or holds its place.
        </p>
        <div className="mt-12">
          <DesignerShowcase hasShots={hasShots} />
        </div>
      </div>
    </section>
  );
}
