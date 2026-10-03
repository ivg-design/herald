"use client";

import { Search } from "lucide-react";
import { OPEN_SEARCH_EVENT } from "./DocsShell";

export default function OpenSearchButton() {
  return (
    <button type="button" className="docs-hint" onClick={() => window.dispatchEvent(new Event(OPEN_SEARCH_EVENT))}>
      <Search size={16} aria-hidden />
      <span>Search titles and headings</span>
      <kbd>/</kbd>
    </button>
  );
}
