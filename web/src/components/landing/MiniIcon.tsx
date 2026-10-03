import Image from "next/image";
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
