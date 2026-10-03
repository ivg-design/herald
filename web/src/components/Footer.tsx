import Image from "next/image";
import SiteLink from "./SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { asset, REPO_URL } from "@/lib/config";

const COLUMNS = [
  {
    title: "Product",
    links: [
      ["Why", "/#why"],
      ["Designer", "/#designer"],
      ["Actions", "/#actions"],
      ["For agents", "/#agents"],
      ["Download", "/#download"],
      ["Changelog", "/changelog"],
    ],
  },
  {
    title: "Docs",
    links: [
      ["API", "/docs/reference/http-api"],
      ["Authoring", "/docs/more/authoring"],
      ["Templates", "/docs/concepts/templates"],
      ["Actions", "/docs/concepts/actions"],
      ["MCP", "/docs/more/mcp-guide"],
      ["Voice", "/docs/concepts/voice"],
      ["Agent quickstart", "/docs/getting-started/agent-quickstart"],
    ],
  },
  {
    title: "Resources",
    links: [
      ["GitHub", REPO_URL],
      ["Report an issue", `${REPO_URL}/issues`],
      ["Discussions", `${REPO_URL}/discussions`],
      ["Example: bidbot", "/docs/examples/bidbot"],
    ],
  },
  {
    title: "More from Forge",
    links: [
      ["Forge hub", "https://forge.mograph.life"],
      ["WebWatcher", "https://forge.mograph.life/apps/webwatcher/"],
      ["RAV", "https://forge.mograph.life/apps/rav/"],
      ["LERP", "https://forge.mograph.life/apps/lerp/"],
      ["fNav+", "https://forge.mograph.life/apps/fnav-plus/"],
      ["Services", "https://forge.mograph.life/services/"],
    ],
  },
];

export default function Footer() {
  return (
    <footer className="border-t border-line bg-bg">
      <div className="shell grid gap-12 py-16 md:grid-cols-[1.3fr_repeat(4,1fr)]">
        <div>
          <Image src={asset("/herald-icon.png")} alt="" width={36} height={36} className="rounded-[8px]" unoptimized />
          <p className="mt-3 text-[17px] font-semibold">Herald</p>
          <p className="mt-3 max-w-[30ch] text-[13px] leading-relaxed text-muted">{nowrapText("A notification service for macOS by IVG Design. MIT license.")}</p>
          <p className="mt-4 text-[12px] text-muted">{nowrapText("\u00a9 2026 IVG Design")}</p>
        </div>
        {COLUMNS.map((c) => (
          <nav key={c.title} aria-label={c.title}>
            <h2 className="m-0 text-[12px] font-semibold tracking-wide text-muted">{c.title}</h2>
            <ul className="m-0 mt-4 flex list-none flex-col gap-2.5 p-0">
              {c.links.map(([label, href]) => (
                <li key={label}>
                  <SiteLink href={href} className="text-[14px] text-ink/90 transition-colors duration-150 hover:text-accent">
                    {label}
                  </SiteLink>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>
    </footer>
  );
}
