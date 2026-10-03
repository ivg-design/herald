// STUB - owned by worker B.
import type { ReleaseInfo } from "@/lib/release";
export default function Download({ release }: { release: ReleaseInfo }) {
  return <section id="download" className="section section-accent"><div className="shell">Download {release.version}</div></section>;
}
