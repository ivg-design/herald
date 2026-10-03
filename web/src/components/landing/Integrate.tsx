import SiteLink from "@/components/SiteLink";
import CodeTabs from "./b-code-tabs";

const USERS = [
  { name: "WebWatcher", href: null, copy: "Page and Gmail watchers as persistent banners with working Open / Archive / Mark read buttons." },
  { name: "bidbot (example in the repo)", href: "/docs/examples/bidbot", copy: "A complete issuer: manifest, template bundle, callbacks and Shortcuts, in docs/examples/bidbot." },
  { name: "Your scripts", href: null, copy: "Any cron job, build, or agent that can run curl." },
];

export default function Integrate() {
  return (
    <section id="integrate" className="section section-paper on-paper">
      <div className="shell">
        <p className="eyebrow">Integrate</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]">Ten lines, any language.</h2>
        <p className="lede">Loopback HTTP + JSON on 127.0.0.1 with a bearer token Herald writes for you. Clients for Swift, Python and Node; a CLI for everything else.</p>
        <div className="mt-12 grid grid-cols-[minmax(0,1fr)] gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,380px)] lg:gap-12">
          <CodeTabs />
          <div className="min-w-0">
            <h3 className="m-0 text-[20px] font-medium">Already speaking Herald</h3>
            <ul className="m-0 mt-4 list-none border-t border-paper-line p-0">
              {USERS.map(({ name, href, copy }) => (
                <li key={name} className="border-b border-paper-line py-4 text-[14px] leading-snug text-paper-muted">
                  <strong className="font-semibold text-paper-ink">
                    {href ? <SiteLink href={href} className="underline decoration-paper-line underline-offset-4 hover:decoration-[var(--accent-on-paper)]">{name}</SiteLink> : name}
                  </strong>{" "}
                  {copy}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
}
