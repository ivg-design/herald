import type { ReactNode } from "react";

type Row = { label: string; mac: ReactNode; herald: ReactNode };

const ROWS: Row[] = [
  { label: "Lifetime", mac: "Banner fades in ~5 s, or Alert style stays until closed", herald: "Stays until you dismiss, snooze, or act" },
  { label: "Layout", mac: "Apple’s template only: title, body, thumbnail", herald: "Your grid, any size: text, images, badges, progress, Rive" },
  { label: "Actions", mac: "Up to a few buttons, no scripts", herald: "URLs, callbacks, scripts, Apple Shortcuts, two-way" },
  { label: "History", mac: "None. Dismissed or cleared means gone", herald: "SQLite, searchable, re-show any banner, export" },
  {
    label: "Focus",
    mac: "Can activate the app on click",
    herald: <b className="font-semibold">Never. Not on show, not on click, not on confirm</b>,
  },
  { label: "Grouping", mac: "Per app only", herald: "By app, issuer or sender, stacked with a counter" },
];

/** One static ledger. A table is for reading, so nothing here moves or reacts. */
export default function Comparison() {
  return (
    <table className="ledger">
      <caption className="sr-only">macOS Notification Center compared with Herald</caption>
      <thead>
        <tr>
          <th scope="col" className="sr-only">Property</th>
          <th scope="col" className="ledger-h">macOS Notification Center</th>
          <th scope="col" className="ledger-h ledger-h-herald">Herald</th>
        </tr>
      </thead>
      <tbody>
        {ROWS.map((r) => (
          <tr key={r.label}>
            <th scope="row" className="ledger-label">{r.label}</th>
            <td className="ledger-mac" data-col="macOS">{r.mac}</td>
            <td className="ledger-herald" data-col="Herald">{r.herald}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
