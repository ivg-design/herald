import type { ReactNode } from "react";

type Row = { label: string; mac: ReactNode; herald: ReactNode };

const NC = <span className="nowrap">Notification Center</span>;

const ROWS: Row[] = [
  { label: "Layout", mac: "One Apple template: icon, title, subtitle or body, one thumbnail", herald: "Your own grid: text, images, badges, progress, Rive, buttons, nine alignment points" },
  { label: "Actions", mac: "The buttons the app registered; no scripts or callbacks of yours", herald: <>URLs, callbacks, commands, scripts, <span className="nowrap">Apple Shortcuts</span>, open an app, snooze, dismiss</> },
  { label: "Confirmation", mac: "None inline; a click hands off to the app", herald: "Commands ask first; the question is drawn in the banner itself" },
  { label: "Reply", mac: "A text reply, when the app offers one", herald: "Typed or recorded reply, with a transcript, relayed back to the sender" },
  { label: "History", mac: <>{NC} lists them, but you can&rsquo;t search it or re-show one</>, herald: "Searchable per-app history; re-show or export any banner" },
  { label: "Grouping", mac: "By app, or by the thread the app sets", herald: "By app, issuer or sender, stacked with a counter" },
  { label: "Voice", mac: "A sound; no speech", herald: "Reads the message aloud with a local voice (Kokoro)" },
  {
    label: "Focus",
    mac: "Clicking a notification activates the app",
    herald: <b className="font-semibold">Never takes focus. Not on show, not on click</b>,
  },
  { label: "Agents", mac: "No story for an agent or a remote sender", herald: <>An MCP server and a relay: <span className="nowrap">Claude Code</span> or <span className="nowrap">Claude Desktop</span> can send, search, re-show and read receipts</> },
];

/** One static ledger. A table is for reading, so nothing here moves or reacts. */
export default function Comparison() {
  return (
    <table className="ledger">
      <caption className="sr-only">macOS <span className="nowrap">Notification Center</span> compared with Herald</caption>
      <thead>
        <tr>
          <th scope="col" className="sr-only">Property</th>
          <th scope="col" className="ledger-h">macOS <span className="nowrap">Notification Center</span></th>
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
