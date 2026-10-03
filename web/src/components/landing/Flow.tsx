"use client";
import MiniIcon from "./MiniIcon";
import { useRef } from "react";
import { useScroll } from "framer-motion";
import { ArrowDown, ArrowRight } from "lucide-react";
import { Lit, LitProvider } from "./a-lit";

const JSON_LINES: [string, number, number][] = [
  ['{ "app": "ci.bot",', 0.04, 0.1],
  ['  "fields": [', 0.1, 0.14],
  ['    {"name":"title","type":"text"},', 0.14, 0.2],
  ['    {"name":"status","type":"badge"},', 0.2, 0.26],
  ['    {"name":"log","type":"url"}],', 0.26, 0.32],
  ['  "actions": ["open","deploy"] }', 0.32, 0.38],
];

/** [row, col, lit?] for a 4 x 3 grid; lit cells light in sequence. */
const LIT_CELLS = new Set([0, 1, 2, 5, 6, 7, 11]);

const card = "relative min-w-0 rounded-xl border border-line bg-surface p-5";
const well = "rounded-md bg-bg p-4";
const prose = "mt-4 text-[12px] leading-[1.6] text-muted";

function Arrow() {
  return (
    <>
      <ArrowRight
        aria-hidden
        size={48}
        strokeWidth={1.5}
        className="absolute -right-[84px] top-[108px] hidden text-accent lg:block"
      />
      <ArrowDown aria-hidden size={40} strokeWidth={1.5} className="mx-auto -mb-2 mt-4 text-accent lg:hidden" />
    </>
  );
}

function Step({ n, title }: { n: string; title: string }) {
  return (
    <h3 className="m-0 mb-3 text-[15px] font-medium text-ink">
      {n} · {title}
    </h3>
  );
}

export default function Flow() {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start 85%", "end 55%"] });
  let cellOrder = 0;
  return (
    <section id="flow" className="section section-dark">
      <div className="shell">
        <p className="eyebrow md:text-center">How it fits together</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]" style={{ lineHeight: 1 }}>
          <span className="block">Apps declare.</span>
          <span className="block pl-[8vw] md:pl-[20%]">You design.</span>
          <span className="block pl-[16vw] md:pl-[38%]">Herald renders.</span>
        </h2>
        <p className="lede mx-auto mt-8 md:max-w-[56ch] md:text-center" style={{ maxWidth: "62ch" }}>
          An app registers a manifest once — the fields it can send, sample values, the actions it offers. You lay
          those fields out in the Designer. Every notification from then on is rendered through your template.
        </p>

        <div
          ref={ref}
          className="mt-14 grid gap-4 lg:grid-cols-[330px_330px_minmax(0,1fr)] lg:gap-x-[108px]"
        >
          <LitProvider progress={scrollYProgress}>
            <article className={card}>
              <Step n="1" title="Manifest" />
              <pre className={`${well} mono m-0 overflow-x-auto text-[11px] leading-[1.7] text-ink`} tabIndex={0}>
                <code>
                  {JSON_LINES.map(([t, a, b]) => (
                    <Lit key={t} from={a} to={b} className="block whitespace-pre">
                      {t}
                    </Lit>
                  ))}
                </code>
              </pre>
              <p className={prose}>
                Your app registers once — from the app itself, a script, or an agent over MCP. Fields carry
                types and sample values so the Designer can preview with real-looking data.
              </p>
              <Arrow />
            </article>

            <article className={card}>
              <Step n="2" title="Template, any grid" />
              <div className={well}>
                <div aria-hidden className="grid grid-cols-4 gap-2">
                  {Array.from({ length: 12 }, (_, i) => {
                    const lit = LIT_CELLS.has(i);
                    const k = lit ? cellOrder++ : 0;
                    return (
                      <div key={i} className="relative h-[38px] rounded-[5px] border border-line bg-surface">
                        {lit && (
                          <Lit
                            aria-hidden
                            from={0.38 + k * 0.03}
                            to={0.42 + k * 0.03}
                            dim={0}
                            className="absolute -inset-px block rounded-[5px] border border-accent bg-accent-soft"
                          />
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
              <p className={prose}>
                Place fields on a grid of any size — add rows and columns, merge cells, pick nine-point
                alignment, size rules, collapse-empty per template or per component.
              </p>
              <Arrow />
            </article>

            <article className={`${card} border-accent`}>
              <Step n="3" title="Banner" />
              <div className={`${well} min-h-[150px]`}>
                <Lit from={0.66} to={0.72} dim={0} rise={8} className="flex items-center gap-2">
                  <MiniIcon size={20} />
                  <span className="text-[12px] font-semibold text-ink">Build passed</span>
                  <span className="rounded-full bg-[#2fbf71] px-2 py-px text-[9px] font-bold text-bg">OK</span>
                </Lit>
                <Lit from={0.72} to={0.78} dim={0} rise={8} className="mt-3 block text-[11px] text-muted">
                  142 tests, 0 failures · main
                </Lit>
                <Lit from={0.78} to={0.86} dim={0} rise={8} className="mt-3 flex gap-2">
                  <span className="mini-btn">Open log</span>
                  <span className="mini-btn">Deploy</span>
                </Lit>
              </div>
              <p className={prose}>
                Every POST /v1/notify from that app is rendered through your template — with buttons wired to
                real actions.
              </p>
            </article>
          </LitProvider>
        </div>
      </div>
    </section>
  );
}
