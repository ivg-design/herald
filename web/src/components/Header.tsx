"use client";

import { useContext, useEffect, useState } from "react";
import Image from "next/image";
import { ArrowUpRight, Download, Menu, X } from "lucide-react";
import SiteLink from "./SiteLink";
import Bell from "@/components/rive/Bell";
import { HeraldInternalContext } from "@/components/herald/internal";
import { asset, REPO_URL, route } from "@/lib/config";

const NAV = [
  { label: "Why", href: "/#why" },
  { label: "Designer", href: "/#designer" },
  { label: "Actions", href: "/#actions" },
  { label: "For agents", href: "/#agents" },
  { label: "Integrate", href: "/#integrate" },
  { label: "Download", href: "/#download" },
  { label: "Changelog", href: "/changelog" },
  { label: "Docs", href: "/docs" },
];

export default function Header({ downloadUrl }: { downloadUrl: string }) {
  const [open, setOpen] = useState(false);
  const herald = useContext(HeraldInternalContext);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg">
      <div className="shell flex h-16 items-center justify-between gap-6">
        <SiteLink href="/" data-testid="brand-home" onClick={(e) => {
            // Already on the landing page: go to the very top and drop any #section, instead of a no-op or a reload.
            const here = window.location.pathname.replace(/\/$/, "");
            const home = route("/").replace(/\/$/, "");
            if (here === home && !e.metaKey && !e.ctrlKey && !e.shiftKey && !e.altKey) {
              e.preventDefault();
              window.history.replaceState(null, "", window.location.pathname + window.location.search);
              window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
            }
          }} className="site-brand flex h-full min-w-0 shrink-0 items-center gap-3" aria-label="Herald home">
          <Image src={asset("/herald-icon.png")} alt="" width={64} height={64} className="site-brand-icon" unoptimized />
          <span className="text-[17px] font-semibold tracking-[-0.01em]">Herald</span>
        </SiteLink>

        <nav aria-label="Primary" className="hidden items-center gap-1 lg:flex">
          {NAV.map((n) => (
            <SiteLink key={n.label} href={n.href} className="rounded-md px-3 py-2 text-[14px] font-medium text-muted transition-colors duration-[220ms] hover:text-ink">
              {n.label}
            </SiteLink>
          ))}
        </nav>

        <div className="flex shrink-0 items-center gap-2 sm:gap-3">
          {herald && (
            <button
              type="button"
              className="hb-bell"
              aria-label={herald.pending > 0 ? `Show ${herald.pending} Herald ${herald.pending === 1 ? "banner" : "banners"}` : "Show Herald banners"}
              aria-expanded={herald.expanded}
              aria-controls="herald-overlay"
              onPointerEnter={(e) => {
                if (e.pointerType === "mouse") {
                  herald.setHold("hover", true);
                  herald.show();
                }
              }}
              onPointerLeave={() => herald.setHold("hover", false)}
              onClick={herald.toggle}
            >
              <Bell count={herald.pending} ring={herald.ring} size={22} tone="paper" />
            </button>
          )}
          <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="hb-dl hidden items-center gap-1 px-2 text-[14px] font-medium text-muted transition-colors duration-[220ms] hover:text-ink sm:inline-flex">
            GitHub <ArrowUpRight size={14} aria-hidden />
          </a>
          <a href={downloadUrl} className="btn btn-primary btn-sm hb-dl hidden sm:inline-flex">
            Download for Mac
          </a>
          <button
            type="button"
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-line text-ink transition-colors duration-[220ms] hover:bg-surface lg:hidden"
            aria-expanded={open}
            aria-controls="mobile-nav"
            aria-label={open ? "Close menu" : "Open menu"}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X size={18} /> : <Menu size={18} />}
          </button>
        </div>
      </div>

      {open && (
        <nav id="mobile-nav" aria-label="Mobile" className="border-t border-line bg-bg lg:hidden">
          <div className="shell flex flex-col py-3">
            {NAV.map((n) => (
              <SiteLink key={n.label} href={n.href} onClick={() => setOpen(false)} className="border-b border-line py-3 text-[16px] font-medium text-ink last:border-0">
                {n.label}
              </SiteLink>
            ))}
            <a href={downloadUrl} className="btn btn-primary mt-4">
              <Download size={16} aria-hidden /> Download for Mac
            </a>
          </div>
        </nav>
      )}
    </header>
  );
}
