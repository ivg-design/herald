import type { Metadata } from "next";
import DocsShell from "@/components/docs/DocsShell";
import "@/components/docs/docs.css";
import { DOC_TREE } from "@/lib/docs-tree";
import { getPages, searchIndex } from "@/lib/docs";

export const metadata: Metadata = {
  title: "Docs",
  description: "Herald documentation: install, send a notification, design the banner, and the full API, CLI, MCP and client reference.",
  alternates: { canonical: "/docs" },
};

export default function DocsLayout({ children }: { children: React.ReactNode }) {
  const pages = getPages();
  const tree = DOC_TREE.map((g) => ({
    id: g.id,
    title: g.title,
    items: pages.filter((p) => p.groupId === g.id).map((p) => ({ title: p.title, href: p.href })),
  }));
  return (
    <DocsShell tree={tree} index={searchIndex()}>
      {children}
    </DocsShell>
  );
}
