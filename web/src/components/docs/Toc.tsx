"use client";

import { useEffect, useState } from "react";
import type { Heading } from "@/lib/markdown";

export default function Toc({ headings }: { headings: Heading[] }) {
  const [active, setActive] = useState<string | null>(headings[0]?.id ?? null);

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

  if (!headings.length) return null;
  return (
    <nav className="docs-toc" aria-label="On this page">
      <p className="docs-toc-title">On this page</p>
      <ul>
        {headings.map((h) => (
          <li key={h.id} className={h.depth === 3 ? "is-sub" : undefined}>
            <a href={`#${h.id}`} aria-current={active === h.id ? "location" : undefined}>
              {h.text}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
