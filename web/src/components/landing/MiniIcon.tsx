import Image from "next/image";
import { Bot, Globe, Mail } from "lucide-react";
import type { HeraldIcon } from "@/components/herald/types";
import type { ReactNode } from "react";
import { asset } from "@/lib/config";

/** Herald app icon for decorative banner mocks. */
export default function MiniIcon({ size = 24, className = "" }: { size?: number; className?: string }) {
  return (
    <Image
      src={asset("/herald-icon.png")}
      alt=""
      aria-hidden
      width={64}
      height={64}
      unoptimized
      className={`shrink-0 ${className}`}
      style={{ width: size, height: size, borderRadius: "22%" }}
    />
  );
}

const MARKS: Record<Exclude<HeraldIcon, "herald">, ReactNode> = {
  ci: (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M6 8.5l4.5 3.5L6 15.5M13 16h5" />
    </svg>
  ),
  mail: <Mail size={18} aria-hidden />,
  ae: (
    <svg viewBox="0 0 24 24" width={20} height={20} aria-hidden>
      <text x={12} y={16} textAnchor="middle" fontSize={12} fontWeight={500} fill="currentColor" style={{ fontFamily: "var(--font-fragment), ui-monospace, monospace" }}>Ae</text>
    </svg>
  ),
  claude: (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden>
      <path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6L5.6 18.4" />
    </svg>
  ),
  web: <Globe size={18} aria-hidden />,
  agent: <Bot size={18} aria-hidden />,
};

/** Sender icon for a Herald banner: the app icon, or a small mono mark on a rounded tile. */
export function HeraldMark({ icon = "herald", size = 32 }: { icon?: HeraldIcon; size?: number }) {
  if (icon === "herald") return <MiniIcon size={size} />;
  return (
    <span className="hb-mark" aria-hidden style={{ width: size, height: size }}>
      {MARKS[icon]}
    </span>
  );
}
