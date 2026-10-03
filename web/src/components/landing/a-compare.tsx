import type { ReactNode } from "react";

type Row = [label: string, value: ReactNode];

const MAC: Row[] = [
  ["Lifetime", "Banner fades in ~5 s, or Alert style stays until closed"],
  ["Layout", "Apple’s template only: title, body, thumbnail"],
  ["Actions", "Up to a few buttons, no scripts"],
  ["History", "None. Dismissed or cleared means gone"],
  ["Focus", "Can activate the app on click"],
  ["Grouping", "Per app only"],
];
const HERALD: Row[] = [
  ["Lifetime", "Stays until you dismiss, snooze, or act"],
  ["Layout", "Your 3×4 grid: text, images, badges, progress, Rive"],
  ["Actions", "URLs, callbacks, scripts, Apple Shortcuts, two-way"],
  ["History", "SQLite, searchable, re-show any banner, export"],
  ["Focus", <b key="never" className="font-semibold">Never. Not on show, not on click, not on confirm</b>],
  ["Grouping", "By app, issuer or sender, stacked with a counter"],
];

function Table({ title, rows, herald }: { title: string; rows: Row[]; herald?: boolean }) {
  return (
    <table
      className={`w-full overflow-hidden rounded-xl border-collapse text-left text-[14px] ${
        herald ? "border-2 border-accent bg-white" : "border border-paper-line bg-white"
      }`}
      style={{ borderCollapse: "separate", borderSpacing: 0 }}
    >
      <caption className="sr-only">{title}</caption>
      <thead>
        <tr>
          <th colSpan={2} scope="colgroup" className={`h-10 px-[17px] text-[13px] font-semibold ${herald ? "bg-accent text-accent-ink" : "bg-[#ecebe6] text-paper-ink/80"}`}>
            {title}
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map(([label, value]) => (
          <tr key={label}>
            <th scope="row" className="w-[30%] border-t border-paper-line px-[17px] py-[12px] align-top text-[13px] font-medium text-paper-muted sm:w-[28%]">
              {label}
            </th>
            <td className={`border-t border-paper-line px-2 py-[12px] align-top ${herald ? "font-medium text-paper-ink" : "text-paper-ink"}`}>{value}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Static comparison. A table is for reading, so nothing here moves or reacts. */
export default function Comparison() {
  return (
    <div className="mt-14 grid gap-6 md:grid-cols-2">
      <Table title="macOS Notification Center" rows={MAC} />
      <Table title="Herald" rows={HERALD} herald />
    </div>
  );
}
