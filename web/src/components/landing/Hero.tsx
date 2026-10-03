// STUB - owned by worker A.
import type { ReleaseInfo } from "@/lib/release";
export default function Hero({ release }: { release: ReleaseInfo }) {
  return <section id="top" className="section section-dark"><div className="shell">Hero {release.version}</div></section>;
}
