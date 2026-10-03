import SiteLink from "@/components/SiteLink";
import { nowrapText } from "@/lib/nowrap";
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
        <h2 className="display display-l col-span-full lg:col-span-8">Ten lines, any language.</h2>
        <p className="lede col-span-full !mt-0 lg:col-span-8">Loopback HTTP + JSON on 127.0.0.1 with a bearer token Herald writes for you. Clients for Swift, Python and Node; a CLI for everything else.</p>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-8">
          <CodeTabs />
        </div>
        <div className="col-span-full mt-6 min-w-0 lg:col-span-4 lg:col-start-9">
          <h3 className="display display-m">Already speaking Herald</h3>
          <ul className="m-0 mt-6 list-none p-0">
            {USERS.map(({ name, href, copy }) => (
              <li key={name} className="border-t border-line py-4 text-[15px] leading-snug text-muted">
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
