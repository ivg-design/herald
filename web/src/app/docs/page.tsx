import SiteLink from "@/components/SiteLink";
import OpenSearchButton from "@/components/docs/OpenSearchButton";
import { getPages } from "@/lib/docs";
import { DOC_TREE } from "@/lib/docs-tree";

export default function DocsIndex() {
  const pages = getPages();
  const start = pages.filter((p) => p.groupId === "getting-started").slice(0, 3);
  const rest = DOC_TREE.map((g) => ({ g, items: pages.filter((p) => p.groupId === g.id) }));
  return (
    <div className="docs-index">
      <p className="eyebrow">Documentation</p>
      <h1 className="display docs-h1">Design it, send it, <em>wire it up.</em></h1>
      <p className="docs-lead">
        Install Herald, send a banner from a terminal, then lay it out on the grid. Every page here is rendered from the Markdown in the repository.
      </p>
      <OpenSearchButton />

      <section aria-labelledby="start-here" className="docs-start">
        <h2 id="start-here" className="docs-index-h">Start here</h2>
        <ol>
          {start.map((p, i) => (
            <li key={p.href}>
              <SiteLink href={p.href}>
                <span className="docs-start-n" aria-hidden>{i + 1}</span>
                <span>
                  <span className="docs-start-title">{p.title}</span>
                  <span className="docs-start-desc">{p.description}</span>
                </span>
              </SiteLink>
            </li>
          ))}
        </ol>
      </section>

      <div className="docs-all">
        {rest.map(({ g, items }) => (
          <section key={g.id} aria-labelledby={`g-${g.id}`}>
            <h2 id={`g-${g.id}`} className="docs-index-h">{g.title}</h2>
            <ul>
              {items.map((p) => (
                <li key={p.href}>
                  <SiteLink href={p.href}>{p.title}</SiteLink>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  );
}
