import type { ReactNode } from "react";

type Row = { label: string; mac: ReactNode; herald: ReactNode };

const NC = <span className="nowrap">Notification Center</span>;

const ROWS: Row[] = [
  { label: "layout", mac: "One Apple template: icon, title, subtitle or body, one thumbnail", herald: "Your own grid: text, images, badges, progress, Rive, buttons, nine alignment points" },
  { label: "actions", mac: "The buttons the app registered; no scripts or callbacks of yours", herald: <>URLs, callbacks, commands, scripts, <span className="nowrap">Apple Shortcuts</span>, open an app, snooze, dismiss</> },
  { label: "confirmation", mac: "None inline; a click hands off to the app", herald: "Commands ask first; the question is drawn in the banner itself" },
  { label: "reply", mac: "A text reply, when the app offers one", herald: "Typed or recorded reply, with a transcript, relayed back to the sender" },
  { label: "persistence", mac: "Banners leave on their own unless you switch the app to Alerts", herald: "Stays until you deal with it. Snooze returns it later; dismiss sends it to History" },
  { label: "history", mac: <>{NC} lists them, but you can&rsquo;t search it or re-show one</>, herald: "Every banner, spoken message and action lands in a searchable per-app History; re-show or export any" },
  { label: "grouping", mac: "By app, or by the thread the app sets", herald: "By app, issuer or sender, stacked with a counter" },
  { label: "voice", mac: "A sound; no speech", herald: "Reads the message aloud with a local voice (Kokoro)" },
  { label: "focus", mac: "Clicking a notification activates the app", herald: "Status-bar level panels that never take key or main window status. Never takes focus, not on show, not on click" },
  { label: "agents", mac: "No story for an agent or a remote sender", herald: <>An MCP server and a relay: <span className="nowrap">Claude Code</span> or <span className="nowrap">Claude Desktop</span> can send, search, re-show and read receipts</> },
];

/** One static ledger on the page's 12 columns. A table is for reading, so nothing here moves or reacts. */
export default function Comparison() {
  return (
    <div className="ledger" role="table" aria-label="macOS Notification Center compared with Herald">
      <div role="rowgroup" className="ledger-head">
        <div role="row" className="ledger-row g">
          <span role="columnheader" className="sr-only">Property</span>
          <span role="columnheader" className="ledger-h ledger-c-mac">notification center</span>
          <span role="columnheader" className="ledger-h ledger-c-herald">herald</span>
        </div>
      </div>
      <div role="rowgroup">
        {ROWS.map((r) => (
          <div role="row" key={r.label} className="ledger-row g">
            <span role="rowheader" className="ledger-label">{r.label}</span>
            <span role="cell" className="ledger-c-mac ledger-mac" data-col="notification center" data-short="macOS">{r.mac}</span>
            <span role="cell" className="ledger-c-herald ledger-herald" data-col="herald" data-short="Herald">{r.herald}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
