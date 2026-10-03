"use client";
import { useState } from "react";
import { Bell } from "lucide-react";
import MiniIcon from "./MiniIcon";

/** Same notification, same desktop, same scale: Apple's template next to the Herald banner, which is live. */
export default function SideBySide() {
  const [opened, setOpened] = useState(false);
  return (
    <div className="sbs">
      <figure className="sbs-fig">
        <figcaption className="sbs-cap readout">macOS <span className="nowrap">Notification Center</span></figcaption>
        <div className="sbs-frame sbs-wall" data-testid="mac-alert">
          <div className="mac-alert">
            <div className="mac-icon" aria-hidden><Bell size={22} strokeWidth={2} fill="currentColor" /></div>
            <div className="mac-text">
              <p className="mac-title">Deploy finished</p>
              <p className="mac-body">Built in 42 s with no warnings. The new landing page is live.</p>
            </div>
            <span className="mac-now">now</span>
          </div>
        </div>
        <p className="sbs-out readout" aria-hidden>&nbsp;</p>
      </figure>
      <figure className="sbs-fig">
        <figcaption className="sbs-cap sbs-cap-herald readout">Herald</figcaption>
        <div className="sbs-frame sbs-wall" data-testid="herald-banner">
          <div className="mb herald-alert">
            <MiniIcon size={34} />
            <div className="mac-text">
              <p className="mac-title">Deploy finished</p>
              <p className="herald-sender">herald.site</p>
              <p className="herald-body">Built in 42 s with no warnings. The new landing page is live.</p>
              <div className="herald-actions">
                <button type="button" className="mb-btn is-primary herald-open" onClick={() => setOpened(true)}>Open site</button>
              </div>
            </div>
            <span className="herald-now">now</span>
          </div>
        </div>
        <p className="sbs-out readout" role="status" aria-live="polite" aria-label="Open outcome">
          {opened ? "Opened the site. The banner stays and focus stays put." : " "}
        </p>
      </figure>
    </div>
  );
}
