"use client";

import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { CornerDownLeft, Hash, Search } from "lucide-react";
import { route } from "@/lib/config";
import type { SearchItem } from "@/lib/docs";

interface Props {
  index: SearchItem[];
  open: boolean;
  onClose: () => void;
}

function rank(item: SearchItem, tokens: string[]): number {
  const primary = (item.heading ?? item.title).toLowerCase();
  const hay = `${item.title} ${item.heading ?? ""} ${item.group}`.toLowerCase();
  if (!tokens.every((t) => hay.includes(t))) return -1;
  const joined = tokens.join(" ");
  let score = item.heading ? 20 : 40; // page titles beat headings
  if (primary === joined) score += 100;
  else if (primary.startsWith(joined)) score += 60;
  else if (primary.includes(joined)) score += 30;
  else if (tokens.every((t) => primary.includes(t))) score += 15;
  return score - Math.min(primary.length, 40) / 10;
}

function Mark({ text, tokens }: { text: string; tokens: string[] }) {
  if (!tokens.length) return <>{text}</>;
  const esc = tokens.map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const parts = text.split(new RegExp(`(${esc.join("|")})`, "ig"));
  return (
    <>
      {parts.map((p, i) => (i % 2 ? <mark key={i}>{p}</mark> : <Fragment key={i}>{p}</Fragment>))}
    </>
  );
}

export default function SearchDialog({ index, open, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const [q, setQ] = useState("");
  const [active, setActive] = useState(0);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      d.showModal();
      requestAnimationFrame(() => input.current?.select());
    } else if (!open && d.open) d.close();
  }, [open]);

  const tokens = useMemo(() => q.toLowerCase().split(/\s+/).filter(Boolean), [q]);

  const groups = useMemo(() => {
    let items: SearchItem[];
    if (!tokens.length) {
      items = index.filter((i) => !i.heading).slice(0, 8);
    } else {
      items = index
        .map((i) => ({ i, s: rank(i, tokens) }))
        .filter((x) => x.s >= 0)
        .sort((a, b) => b.s - a.s)
        .slice(0, 30)
        .map((x) => x.i);
    }
    const map = new Map<string, SearchItem[]>();
    for (const it of items) {
      if (!map.has(it.group)) map.set(it.group, []);
      map.get(it.group)!.push(it);
    }
    return [...map.entries()];
  }, [index, tokens]);

  const flat = useMemo(() => groups.flatMap(([, items]) => items), [groups]);

  useEffect(() => {
    list.current?.querySelector<HTMLElement>(`[data-i="${active}"]`)?.scrollIntoView({ block: "nearest" });
  }, [active]);

  function go(item: SearchItem | undefined) {
    if (!item) return;
    onClose();
    router.push(route(item.href));
  }

  function onKeyDown(e: React.KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => (flat.length ? (a + 1) % flat.length : 0));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => (flat.length ? (a - 1 + flat.length) % flat.length : 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      go(flat[active]);
    }
  }

  let n = -1;
  return (
    <dialog
      ref={ref}
      className="docs-search"
      aria-label="Search docs"
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
    >
      <div className="docs-search-panel" onKeyDown={onKeyDown}>
        <div className="docs-search-field">
          <Search size={18} aria-hidden />
          <input
            ref={input}
            value={q}
            onChange={(e) => {
              setQ(e.target.value);
              setActive(0);
            }}
            type="search"
            placeholder="Search titles and headings"
            aria-label="Search docs"
            role="combobox"
            aria-expanded="true"
            aria-controls="docs-search-list"
            aria-activedescendant={flat.length ? `docs-hit-${active}` : undefined}
            autoComplete="off"
            spellCheck={false}
          />
          <kbd>Esc</kbd>
        </div>
        <div ref={list} id="docs-search-list" role="listbox" aria-label="Results" className="docs-search-results">
          {flat.length === 0 && <p className="docs-search-empty">No page or heading matches &ldquo;{q}&rdquo;.</p>}
          {groups.map(([group, items]) => (
            <div key={group} role="group" aria-label={group}>
              <div className="docs-search-group">{group}</div>
              {items.map((it) => {
                n += 1;
                const i = n;
                return (
                  <button
                    key={it.href}
                    type="button"
                    id={`docs-hit-${i}`}
                    data-i={i}
                    role="option"
                    aria-selected={i === active}
                    className="docs-hit"
                    onMouseMove={() => active !== i && setActive(i)}
                    onClick={() => go(it)}
                  >
                    {it.heading ? <Hash size={14} aria-hidden /> : <span className="docs-hit-dot" aria-hidden />}
                    <span className="docs-hit-text">
                      <span className="docs-hit-title"><Mark text={it.heading ?? it.title} tokens={tokens} /></span>
                      {it.heading && <span className="docs-hit-sub"><Mark text={it.title} tokens={tokens} /></span>}
                    </span>
                    {i === active && <CornerDownLeft size={14} aria-hidden />}
                  </button>
                );
              })}
            </div>
          ))}
        </div>
        <div className="docs-search-foot" aria-hidden>
          <span><kbd>↑</kbd><kbd>↓</kbd> move</span>
          <span><kbd>↵</kbd> open</span>
          <span><kbd>/</kbd> or <kbd>⌘K</kbd> anywhere</span>
        </div>
      </div>
    </dialog>
  );
}
