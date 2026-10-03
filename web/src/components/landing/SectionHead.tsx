import type { ReactNode } from "react";

/**
 * A section head laid out the way the hero is: the title is a field in a `title` cell, the lede a field in a
 * `body` cell, on the page's 12-column grid. `aside` is an optional third cell (a readout, a control, a figure).
 * Column spans are Tailwind classes so each section can keep its own proportions.
 */
export default function SectionHead({
  title,
  lede,
  aside,
  asideSlot = "meta",
  titleCols = "lg:col-span-8",
  ledeCols = "lg:col-span-7",
  asideCols = "lg:col-span-4",
  as: Tag = "h2",
  id,
}: {
  title: ReactNode;
  lede?: ReactNode;
  aside?: ReactNode;
  asideSlot?: string;
  titleCols?: string;
  ledeCols?: string;
  asideCols?: string;
  as?: "h1" | "h2";
  id?: string;
}) {
  return (
    <header className="sec-head g col-span-full">
      <div className={`cell col-span-full ${titleCols}`} data-filled="false">
        <span className="slot" aria-hidden>title</span>
        <Tag id={id} className="display display-l">{title}</Tag>
      </div>
      {aside && (
        <div className={`cell sec-meta col-span-full ${asideCols}`} data-filled="false">
          <span className="slot" aria-hidden>{asideSlot}</span>
          {aside}
        </div>
      )}
      {lede && (
        <div className={`cell col-span-full ${ledeCols}`} data-filled="false">
          <span className="slot" aria-hidden>body</span>
          <p className="lede">{lede}</p>
        </div>
      )}
    </header>
  );
}
