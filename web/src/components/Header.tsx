"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { ArrowUpRight, Download, Menu, X } from "lucide-react";
import SiteLink from "./SiteLink";
import { asset, REPO_URL } from "@/lib/config";

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

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg">
      <div className="shell flex h-[68px] items-center justify-between gap-6">
        <SiteLink href="/" className="flex items-center gap-3 font-semibold" aria-label="Herald home">
          <Image src={asset("/herald-icon.png")} alt="" width={26} height={26} className="rounded-[6px]" unoptimized />
          <span className="text-[17px]">Herald</span>
        </SiteLink>

        <nav aria-label="Primary" className="hidden items-center gap-1 lg:flex">
          {NAV.map((n) => (
            <SiteLink key={n.label} href={n.href} className="rounded-md px-3 py-2 text-[14px] text-muted transition-colors duration-150 hover:text-ink">
              {n.label}
            </SiteLink>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <a href={REPO_URL} target="_blank" rel="noopener noreferrer" className="hidden items-center gap-1 px-2 text-[14px] text-muted hover:text-ink sm:inline-flex">
            GitHub <ArrowUpRight size={14} aria-hidden />
          </a>
          <a href={downloadUrl} className="btn btn-primary btn-sm hidden sm:inline-flex">
            Download for Mac
          </a>
          <button
            type="button"
            className="inline-flex h-10 w-10 items-center justify-center rounded-md border border-line text-ink lg:hidden"
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
              <SiteLink key={n.label} href={n.href} onClick={() => setOpen(false)} className="border-b border-line py-3 text-[16px] text-ink last:border-0">
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
