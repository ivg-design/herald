"use client";

import { useEffect, useMemo, useState } from "react";
import type { Heading } from "@/lib/markdown";

const METHOD = /^(GET|POST|PUT|DELETE|PATCH)\s+(\/\S*)$/;
/** Above this many entries the sub-headings fold away, except under the section being read. */
const FOLD_OVER = 16;

interface Group {
  head: Heading | null;
  subs: Heading[];
}

function Label({ h }: { h: Heading }) {
  const m = h.code ? h.text.match(METHOD) : null;
  if (m) {
    return (
      <>
        <span className="toc-method" data-method={m[1]}>{m[1]}</span>
        <span className="toc-code">{m[2]}</span>
      </>
    );
  }
  return h.code ? <span className="toc-code">{h.text}</span> : <>{h.text}</>;
}

export default function Toc({ headings }: { headings: Heading[] }) {
  const [active, setActive] = useState<string | null>(headings[0]?.id ?? null);

  const groups = useMemo(() => {
    const out: Group[] = [];
    for (const h of headings) {
      if (h.depth === 2 || !out.length) out.push({ head: h.depth === 2 ? h : null, subs: h.depth === 2 ? [] : [h] });
      else out[out.length - 1].subs.push(h);
    }
    return out;
  }, [headings]);
  const fold = headings.length > FOLD_OVER;

  useEffect(() => {
    if (!headings.length) return;
    const els = headings.map((h) => document.getElementById(h.id)).filter((e): e is HTMLElement => !!e);
    const visible = new Set<string>();
    const pick = () => {
      const first = els.find((e) => visible.has(e.id));
      if (first) return setActive(first.id);
      // Nothing in the band: the last heading above the viewport stays current.
      const above = els.filter((e) => e.getBoundingClientRect().top < 120);
      setActive(above.length ? above[above.length - 1].id : els[0]?.id ?? null);
    };
    const io = new IntersectionObserver(
      (entries) => {
        for (const en of entries) {
          if (en.isIntersecting) visible.add(en.target.id);
          else visible.delete(en.target.id);
        }
        pick();
      },
      { rootMargin: "-88px 0px -65% 0px", threshold: 0 },
    );
    els.forEach((e) => io.observe(e));
    return () => io.disconnect();
  }, [headings]);

  useEffect(() => {
    if (!active) return;
    const a = document.querySelector<HTMLElement>(`.docs-toc a[href="#${CSS.escape(active)}"]`);
    const nav = a?.closest<HTMLElement>(".docs-toc");
    if (!a || !nav || !a.offsetParent) return;
    // Keep the current entry in view inside the rail only; the page itself is never scrolled from here.
    const top = a.getBoundingClientRect().top - nav.getBoundingClientRect().top;
    if (top < 32 || top > nav.clientHeight - 48) nav.scrollTop += top - nav.clientHeight / 2;
  }, [active]);

  if (!headings.length) return null;
  const link = (h: Heading) => (
    <a href={`#${h.id}`} aria-current={active === h.id ? "location" : undefined}>
      <Label h={h} />
    </a>
  );
  return (
    <nav className="docs-toc" aria-label="On this page">
      <p className="docs-toc-title">On this page</p>
      <ul>
        {groups.map((g, i) => {
          const open = !fold || !g.head || g.head.id === active || g.subs.some((s) => s.id === active);
          return (
            <li key={g.head?.id ?? `g${i}`} className={g.subs.length ? "has-subs" : undefined} data-open={open ? "" : undefined}>
              {g.head && link(g.head)}
              {g.subs.length > 0 && (
                <ul hidden={!open}>
                  {g.subs.map((s) => (
                    <li key={s.id} className="is-sub">{link(s)}</li>
                  ))}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
