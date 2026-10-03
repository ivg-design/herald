import { Bot, Globe, Terminal } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import CodeTabs from "./b-code-tabs";

const USERS = [
  { icon: Globe, name: "WebWatcher", href: null, copy: "Page and Gmail watchers as persistent banners with working Open / Archive / Mark read buttons." },
  { icon: Bot, name: "bidbot (example in the repo)", href: "/docs/examples/bidbot", copy: "A complete issuer: manifest, template bundle, callbacks and Shortcuts, in docs/examples/bidbot." },
  { icon: Terminal, name: "Your scripts", href: null, copy: "Any cron job, build, or agent that can run curl." },
];

export default function Integrate() {
  return (
    <section id="integrate" className="section section-paper on-paper">
      <div className="shell">
        <p className="eyebrow">Integrate</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]">Ten lines, any language.</h2>
        <p className="lede">Loopback HTTP + JSON on 127.0.0.1 with a bearer token Herald writes for you. Clients for Swift, Python and Node; a CLI for everything else.</p>
        <div className="mt-12 grid gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,380px)] lg:gap-12">
          <CodeTabs />
          <div>
            <h3 className="m-0 text-[20px] font-medium">Already speaking Herald</h3>
            <ul className="m-0 mt-5 flex list-none flex-col gap-5 p-0">
              {USERS.map(({ icon: Icon, name, href, copy }) => (
                <li key={name} className="flex gap-4">
                  <span aria-hidden className="flex size-10 shrink-0 items-center justify-center rounded-lg border border-paper-line bg-[#e3e6ea] text-paper-muted">
                    <Icon className="size-[18px]" />
                  </span>
                  <div>
                    <p className="m-0 text-[15px] font-semibold">
                      {href ? <SiteLink href={href} className="underline decoration-paper-line underline-offset-4 hover:decoration-[var(--accent-on-paper)]">{name}</SiteLink> : name}
                    </p>
                    <p className="m-0 mt-1 text-[13.5px] leading-snug text-paper-muted">{copy}</p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
}
