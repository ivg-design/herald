import Image from "next/image";
import { Bell } from "lucide-react";
import { asset } from "@/lib/config";

/** Same notification, same desktop, same scale: Apple's template next to a real Herald capture. */
export default function SideBySide() {
  return (
    <div className="sbs">
      <figure className="sbs-fig">
        <figcaption className="sbs-cap mono">macOS <span className="nowrap">Notification Center</span></figcaption>
        <div className="sbs-frame" data-testid="mac-alert">
          <div className="mac-alert">
            <div className="mac-icon" aria-hidden><Bell size={22} strokeWidth={2} fill="currentColor" /></div>
            <div className="mac-text">
              <p className="mac-title">Deploy finished</p>
              <p className="mac-body">Built in 42 s with no warnings. The new landing page is live.</p>
            </div>
            <span className="mac-now">now</span>
          </div>
        </div>
      </figure>
      <figure className="sbs-fig">
        <figcaption className="sbs-cap sbs-cap-herald mono">Herald</figcaption>
        <Image
          src={asset("/shots/banner-plain.png")}
          alt="The same notification as a Herald banner: title, project line, body, an Open site button, time and a bell icon button."
          width={920}
          height={406}
          unoptimized
          className="sbs-frame sbs-img"
        />
      </figure>
    </div>
  );
}
