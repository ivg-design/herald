"use client";

import { useCallback, useEffect, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { ArrowUpRight, Menu, Search, X } from "lucide-react";
import SiteLink from "@/components/SiteLink";
import SearchDialog from "./SearchDialog";
import { asset, PREFIX, REPO_URL } from "@/lib/config";
import type { SearchItem } from "@/lib/docs";

export interface NavGroup {
  id: string;
  title: string;
  items: { title: string; href: string }[];
}

export const OPEN_SEARCH_EVENT = "docs:open-search";

function isTyping(el: EventTarget | null): boolean {
  const t = el as HTMLElement | null;
  if (!t) return false;
  return t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName);
}

export default function DocsShell({ tree, index, children }: { tree: NavGroup[]; index: SearchItem[]; children: ReactNode }) {
  const rawPath = usePathname() || "";
  const path = (PREFIX && rawPath.startsWith(PREFIX) ? rawPath.slice(PREFIX.length) : rawPath).replace(/\/$/, "");
  const [drawer, setDrawer] = useState(false);
  const [search, setSearch] = useState(false);
  const menuBtn = useRef<HTMLButtonElement>(null);
  const closeBtn = useRef<HTMLButtonElement>(null);
  const mac = useSyncExternalStore(
    () => () => {},
    () => /Mac|iPhone|iPad/.test(navigator.platform),
    () => true,
  );
  const [seenPath, setSeenPath] = useState(path);
  if (seenPath !== path) {
    setSeenPath(path);
    setDrawer(false);
  }
  useEffect(() => {
    document.querySelector<HTMLElement>("#docs-sidebar [aria-current='page']")?.scrollIntoView({ block: "nearest" });
  }, [path]);

  const openSearch = useCallback(() => setSearch(true), []);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setSearch((s) => !s);
      } else if (e.key === "/" && !e.metaKey && !e.ctrlKey && !e.altKey && !isTyping(e.target)) {
        e.preventDefault();
        setSearch(true);
      } else if (e.key === "Escape") setDrawer(false);
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener(OPEN_SEARCH_EVENT, openSearch);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener(OPEN_SEARCH_EVENT, openSearch);
    };
  }, [openSearch]);

  useEffect(() => {
    if (drawer) closeBtn.current?.focus();
  }, [drawer]);

  function closeDrawer() {
    setDrawer(false);
    menuBtn.current?.focus();
  }

  const key = mac ? "⌘K" : "Ctrl K";

  return (
    <div className="docs-root">
      <header className="docs-header">
        <div className="docs-header-in">
          <div className="flex min-w-0 items-center gap-2">
            <button
              ref={menuBtn}
              type="button"
              className="docs-iconbtn lg:hidden"
              aria-label="Open docs navigation"
              aria-expanded={drawer}
              aria-controls="docs-sidebar"
              onClick={() => setDrawer(true)}
            >
              <Menu size={18} />
            </button>
            <SiteLink href="/" className="docs-brand" aria-label="Herald home">
              <Image src={asset("/herald-icon.png")} alt="" width={64} height={64} className="docs-brand-icon" unoptimized />
              <span className="text-[17px] font-semibold">Herald</span>
            </SiteLink>
            <SiteLink href="/docs" className="docs-doclink hidden min-[420px]:inline" aria-label="Docs home">/ Docs</SiteLink>
          </div>

          <button type="button" className="docs-searchbtn" onClick={openSearch} aria-label="Search docs" aria-keyshortcuts="Control+K Meta+K /">
            <Search size={16} aria-hidden />
            <span className="docs-searchbtn-label">Search docs...</span>
            <kbd className="hidden sm:inline">{key}</kbd>
          </button>

          <nav aria-label="Site" className="hidden items-center gap-1 text-[14px] text-muted md:flex">
            <SiteLink href="/" className="docs-toplink">Home</SiteLink>
            <SiteLink href="/changelog" className="docs-toplink">Changelog</SiteLink>
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="docs-toplink inline-flex items-center gap-1">
              GitHub <ArrowUpRight size={14} aria-hidden />
            </a>
          </nav>
        </div>
      </header>

      <div className="docs-body">
        <div className={`docs-scrim ${drawer ? "is-open" : ""}`} onClick={closeDrawer} aria-hidden />
        <aside id="docs-sidebar" className={`docs-sidebar ${drawer ? "is-open" : ""}`} aria-label="Docs navigation">
          <div className="docs-sidebar-top lg:hidden">
            <span className="text-[13px] font-semibold uppercase tracking-[0.14em] text-muted">Docs</span>
            <button ref={closeBtn} type="button" className="docs-iconbtn" aria-label="Close docs navigation" onClick={closeDrawer}>
              <X size={18} />
            </button>
          </div>
          <nav aria-label="Docs pages">
            {tree.map((g) => (
              <div key={g.id} className="docs-group">
                <p className="docs-group-title">{g.title}</p>
                <ul>
                  {g.items.map((it) => {
                    const current = path === it.href;
                    return (
                      <li key={it.href}>
                        <SiteLink href={it.href} className="docs-navlink" aria-current={current ? "page" : undefined}>
                          {it.title}
                        </SiteLink>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))}
          </nav>
          <div className="docs-sidebar-site lg:hidden">
            <SiteLink href="/" className="docs-navlink">Home</SiteLink>
            <SiteLink href="/changelog" className="docs-navlink">Changelog</SiteLink>
            <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="docs-navlink">GitHub</a>
          </div>
        </aside>

        <main id="docs-main" className="docs-main">{children}</main>
      </div>

      <SearchDialog index={index} open={search} onClose={() => setSearch(false)} />
    </div>
  );
}
