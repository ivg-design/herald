import Image from "next/image";
import SiteLink from "./SiteLink";
import { nowrapText } from "@/lib/nowrap";
import { asset, REPO_URL } from "@/lib/config";

const COLUMNS = [
  {
    title: "product",
    label: "Product",
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
    title: "docs",
    label: "Docs",
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
    title: "resources",
    label: "Resources",
    links: [
      ["GitHub", REPO_URL],
      ["Report an issue", `${REPO_URL}/issues`],
      ["Discussions", `${REPO_URL}/discussions`],
      ["Example: bidbot", "/docs/examples/bidbot"],
    ],
  },
  {
    title: "more from forge",
    label: "More from Forge",
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

/* Night band: bone type on --night. Grid: brand + line in columns 1-4, then four link columns of 2. */
export default function Footer() {
  return (
    <footer className="night">
      <div className="shell">
        <div className="g py-16 md:py-20">
          <div className="col-span-4 sm:col-span-6 lg:col-span-4">
            <Image src={asset("/herald-icon.png")} alt="" width={36} height={36} unoptimized />
            <p className="m-0 mt-3 text-[17px] font-semibold">Herald</p>
            <p className="m-0 mt-3 max-w-[30ch] text-[14px] leading-[1.5] text-muted">{nowrapText("A notification service for macOS by IVG Design.")}</p>
          </div>
          {COLUMNS.map((c) => (
            <nav key={c.label} aria-label={c.label} className={`col-span-2 sm:col-span-3 lg:col-span-2`}>
              <h2 className="m-0 font-mono text-[12px] font-normal tracking-[0.02em] text-muted">{c.title}</h2>
              <ul className="m-0 mt-4 flex list-none flex-col gap-2.5 p-0">
                {c.links.map(([label, href]) => (
                  <li key={label}>
                    <SiteLink href={href} className="text-[14px] text-ink transition-colors duration-[220ms] hover:text-accent-text">
                      {label}
                    </SiteLink>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="flex h-14 items-center justify-between gap-4 border-t border-line">
          <p className="m-0 font-mono text-[12px] tracking-[0.02em] text-muted">{nowrapText("© 2026 IVG Design · MIT")}</p>
        </div>
      </div>
    </footer>
  );
}
