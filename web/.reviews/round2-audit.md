# Round 2 audit (independent reviewer, 2026-10-02)

Scope: production build served on :3222, headless Chrome 1440×900 / 834×1100 / 390×844, every landing section plus `/docs`, `/docs/getting-started/install`, `/docs/getting-started/agent-quickstart`, `/changelog`; `scripts/test-demos.mjs` (95/95 before changes); interaction states driven with puppeteer and screenshotted. Product claims checked against `Sources/` and `docs/`.

## Anti-patterns verdict

Mostly passes the "AI slop" test: Instrument Serif display + DM Sans + JetBrains Mono, blue-tinted charcoal, one red signal colour, real captures, no gradient text, no glassmorphism, no icon-above-heading cards. Tells that remain: the Flow section's three identical bordered cards with arrows; the Living section's three equal cards; the Why section's empty right quadrant; the decorative waveform bars in the voice card (a sparkline that says nothing until Play).

## Findings ranked by impact

### Critical
1. **Why section is built on a false premise** (`Why.tsx`, `b-five-seconds.tsx`, `a-compare.tsx` row "Lifetime"). The "5 s" countdown, "Send the same alert to both", "Gone. It is not in any history." and the ledger's "Banner fades in ~5 s" argue that macOS banners vanish. macOS Alert style stays until dismissed (per app, System Settings). Owner-confirmed factual error. Must be rewritten around the honest case: one Apple template, no actions of your own, no inline confirmation / reply / record, no searchable history or re-show, no issuer/sender grouping with counters, no voice, click activates the app, no agent/relay story.
2. **Why section composition**: right half of the section is empty at 1440 except a stray mono caption "Herald's corner…" (`.why-corner`). No side-by-side evidence.
3. **Overlay covers content for 6 s** after any send from a lower section (`PageStack.tsx`, `HeraldHost.expandFor(6000)`): the full stack (3 cards + header + Dismiss all, ≈ 500 px tall) drops over the right column (e.g. hides "Already speaking Herald" beside the Integrate code). Screenshot `s-overlay-after-integrate-send.png`.

### High
4. **Flow logic contradicts the product rule** (`Flow.tsx`): the icon cell sits in row 1 and is never empty, yet emptying title+status "collapses row 1" and the summary says "every cell in it is empty". Herald collapses a row only when every cell is empty. Also keep-space labels `status: empty (held)` overflow and clip inside the cell (`s-flow-keep-space.png`).
5. **Flow composition**: three equal bordered boxes with arrows (the lead's own weakest point) – reads as a template diagram.
6. **Phone hero**: at 390 the dock (the banners, i.e. the product) begins ≈ 900 px down; the first screen is text + buttons only (`390-top.png`).
7. **Agents typed list renders blank check marks** for several seconds while "typing" (`b-agents-ui.tsx`, `s-agents-waited.png`): rows 2–7 are empty ticks at uneven spacing; row 3 wraps to two lines at 1440.
8. **Scrollbar-gutter shift** (owner's bug on a sister site): no `scrollbar-gutter` on `html`; `.hb-overlay` positions with `calc((100vw - 1200px)/2)` so with classic scrollbars the overlay is offset from the shell by half a scrollbar; headless measurement cannot show the shift (overlay scrollbars) so the fix is applied by rule and verified by forced-scrollbar CSS.
9. **Proper nouns wrap** (owner's bug): footer "IVG / Design" at 1440 and 390; at 390 also "SF Symbols" (Designer lede), "Claude Desktop" (Agents lede), "Claude Code"/"Claude Desktop" in changelog list items. Measured with Range client rects.
10. **Stack badge not clickable** (owner's bug, `LiveBanner.tsx`): only the title block toggles a stack; the red count badge and chevron are inert spans.

### Medium
11. **Invented feature**: Download card shows `brew install --cask herald (planned)` – no cask exists in README/docs. Remove.
12. **Living cards unequal heights** (212/222/206 px) so the three h3 headings sit at y 675/686/669 (`1440-living.png`).
13. **Docs wide tables / code blocks**: lead's claim "tables fixed" unverified by me at 834/390; install page's `xcodebuild …` line is clipped at the right edge at 390 and reaches the card edge at 1440 (`1440-_docs_getting-started_install.png`).
14. **Docs article gutter**: on pages without a TOC rail (install) the article leaves ≈ 300 px empty to the right at 1440.
15. **Rive usage is modest**: a 22 px bell and a 20 px status ring. Nothing on the page shows the grid → banner idea in motion, which is the product's one-sentence pitch.

### Low
16. Hero stack title truncates "Office hours moved to Thurs…" (real banner behaviour; acceptable, but the seeded title could be shorter).
17. `.hb-head-l` counts "3 banners · 5 new" on first paint before any interaction – reads as if the user already has unread items; fine for the demo, noted.
18. Changelog preview rows are plain; acceptable.

## Accuracy check (no invented features)
Verified against the repo: 67 MCP tool names in `Sources/herald-mcp` ("60+ tools" ok); Kokoro ≈ 340 MB (`docs/VOICE.md:23`); 9 alignment points (`docs/TEMPLATES.md:59`); `reshow_notification`, `export_history`, `history_search`, `expand_stack` (`docs/MCP.md:126`); action kinds url/callback/command/script/shortcut/openApp/dismiss/snooze and confirmation (`docs/ACTIONS.md`); never takes focus (`docs/TEMPLATES.md:161`, `docs/CLOUD.md:207`); typed/recorded reply with transcript and receipts (`docs/CLOUD.md`); macOS 13.1 (`project.yml`). Not backed: Homebrew cask (removed). To re-check after W2b: "resumable" download, "Reminders access".

## Positive
The host concept works and is coherent (one stack, bell count, History counter, snooze, inline confirm with the Rive ring); the Designer RAV-style hotspots on the real capture are excellent; LERP flipper is distinctive; docs search is fast and clean; the transparent SVG mark with the ping is right.

## Status after the round-2 fixes (commits 61270ea, 5a40926)
Fixed and verified headless (125/125 assertions in `scripts/test-demos.mjs`, screenshots at 1440/834/390): 1–14 above. Added: Rive grid-to-banner piece (`web/rive/grid-banner`, 43 KB with a subset DM Sans) in the Designer head; `scrollbar-gutter: stable`; `.nowrap` helper (`src/lib/nowrap.tsx`) plus a rehype pass for docs/changelog; arrival-card overlay mode; badge/chevron buttons on stacks; phone hero reorder with a "+N more" pill; Flow field-linked highlights and icon rail; docs solo column and scrolling tables; Homebrew line removed.
Still weakest: the Living voice card's waveform is static until Play (decorative while idle); the Why mac-alert is a CSS reproduction, not a system capture (capturing one would post a real notification on the owner's screen); the arrival card still covers ~200 px of the right column for 4 s at 1440 (by design, like the app).
