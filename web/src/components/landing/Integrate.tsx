import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
import SectionHead from "./SectionHead";
import CodeTabs from "./b-code-tabs";

const USERS = [
  { name: "WebWatcher", href: null, copy: "Page and Gmail watchers as persistent banners with working Open / Archive / Mark read buttons." },
  { name: "bidbot (example in the repo)", href: "/docs/examples/bidbot", copy: "A complete issuer: manifest, template bundle, callbacks and Shortcuts, in docs/examples/bidbot." },
  { name: "Your scripts", href: null, copy: "Any cron job, build, or agent that can run curl." },
];

export default function Integrate() {
  return (
    <section id="integrate" className="section">
      <div className="shell g">
        <SectionHead
          title="Ten lines, any language."
          titleCols="lg:col-span-9"
          ledeCols="lg:col-span-8"
          lede="Loopback HTTP + JSON on 127.0.0.1 with a bearer token Herald writes for you. Clients for Swift, Python and Node; a CLI for everything else."
        />
        <div className="col-span-full min-w-0 lg:col-span-8">
          <h3 className="display display-m !mb-5">Send from your language</h3>
          <CodeTabs />
          <p className="mt-5 text-[15px] leading-snug text-muted">
            Building an app?{" "}
            <SiteLink href="/docs/getting-started/integrate" className="font-semibold text-accent-text underline underline-offset-4">
              {nowrapText("Integrate Herald into your app")}
            </SiteLink>{" "}
            walks through finding Herald, the manifest, buttons, a default template and testing.
          </p>
        </div>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-4 lg:col-start-9 lg:mt-0">
          <h3 className="display display-m m-0">Already speaking Herald</h3>
          <ul className="m-0 mt-5 list-none border-t border-line p-0">
            {USERS.map(({ name, href, copy }) => (
              <li key={name} className="border-b border-line py-4 text-[15px] leading-snug text-muted">
                <strong className="font-semibold text-ink">
                  {href ? <SiteLink href={href} className="text-accent-text underline underline-offset-4">{nowrapText(name)}</SiteLink> : nowrapText(name)}
                </strong>{" "}
                {nowrapText(copy)}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
