# Herald web v3 — round 2 independent review

Reviewer did not build the page. Production build served on :3294, headless Chrome, screenshots at 1440 / 1280 /
834 / 390 in `web/.screenshots/r2/` (gitignored; names below are files in that folder). Every interaction was
driven with real mouse events (`act.mjs`).

## Verdict

1. **Would the owner be wowed? No.** The hero has one genuinely good move (drag the edge, the headline changes
   width to fit its cell) but it is hidden behind a 4 px grey bar, and what loads is navy type on a bone page with
   barely visible dashes. From the second section down it is a standard product page: condensed headline,
   paragraph, a small demo, and half a screen of empty bone.
2. **Distinct from SidebarFavorites? Yes.** No shared structure, type or colour.
3. **Distinct from WebWatcher? No — this is the blocker.** WebWatcher v3 is Archivo 800 at `font-stretch: 62%`
   with mono readouts and a banner under the header mark. Herald's section titles are Archivo 800 at `wdth 68`
   with mono readouts and a banner under the header bell. Side by side (`ref-ww.png` vs `b-1440-flow.png`)
   "Three steps. No DevTools." and "Apps declare. You design." are the same typographic voice on inverted grounds.

## Blockers

**B1. Same typeface and the same condensed-black title voice as WebWatcher.**
Evidence: `ref-ww.png`, `b-1440-flow.png`, `b-1440-actions.png`. Cause: `src/app/layout.tsx:7` (Archivo),
`src/app/globals.css:160-161` (`.display-l` / `.display-m` at `wdth 68` / `78`; the concept specified `wdth 100`,
the builder's round two condensed them). WebWatcher: `web-watcher/web/src/app/globals.css:68,72`.
Fix: change the family. Georama (wdth 62.5–150, wght 100–900) keeps the hero's width-axis idea with a wider
range than Archivo and has a wide end WebWatcher never uses. Section titles go **wide** (wdth 125–140, 800),
the opposite pole from WebWatcher's condensed. Mono stays Fragment Mono (WebWatcher is JetBrains Mono).

**B2. The site says 1.6.4; the release is 1.6.5 (build 15).**
Evidence: `b-1440-fold.png` ("Download Herald · 1.6.4"), `b-1440-download.png` ("Herald 1.6.4 · Build 14").
Cause: `src/lib/release.ts:15-26`: the fallback is hard-coded to 1.6.4 and is returned whenever the
unauthenticated GitHub API call fails or is rate-limited at build time (60 requests an hour; every `next build`
and every dev reload spends one). GitHub itself answers `v1.6.5`, published 2026-10-03T05:07:58Z, DMG digest
`2311d622…`. The concept and build rules both say "1.6.5 fallback"; the code never got it. Also
`web/content/CHANGELOG.md` is committed at 1.6.4 and only catches up when `npm run sync` runs.
Fix: fallback to the 1.6.5 asset with its real size and digest; commit the synced changelog.

**B3. The hero's proof needs a click nobody will make.** (builder's point 1, confirmed)
Evidence: `b-1440-fold.png`: the layout picker is three 36 px ghost buttons below the template and the drag
handle is a 4 × 120 px grey bar at 50 % opacity that reads as a scrollbar thumb. A visitor who does nothing sees
a static headline in dashed boxes. Cause: `src/components/landing/Hero.tsx:92-110` (auto re-layout removed for
CLS), `src/styles/hero.css:106-109` (handle), `:117-120` (picker).
Fix: transform-only FLIP in reserved space. A hidden grid (`visibility: hidden`, not tracked by the
layout-shift API) solves each layout; the visible cells are absolutely positioned and moved with
`transform` only, inside a stage whose height is reserved. Then the template can tour its three layouts once on
load without shifting anything. The picker moves into a toolbar above the canvas with layout glyphs; the handle
becomes a labelled grip with a live width readout; column rulers above the canvas show the tracks changing.

## Major

**M1. The hero is timid.** Navy on bone, 1 px dashes at `--hair`, a 112 px icon, and 150 px of empty bone under
the picker at 1440 × 900 (`b-1440-fold.png`). Nothing says "Designer canvas" except the dashes.
Fix (bolder): the first screen becomes a blueprint: one saturated Herald-blue ground, white dashed cells, white
wide type, column rulers with live track sizes. It is the Designer's canvas at page scale and it is the one
ground neither sibling uses (SBF is a purple-to-orange gradient, WebWatcher is graphite).

**M2. Narrowing the canvas shrinks the headline instead of re-breaking it.** (builder's point 2, confirmed)
Evidence: `i-hero-drag-600.png`: at 702 pt the title drops from 124 px to 102 px (`fit.scale`), and on a phone
(`m1.png`) the headline is two small lines. Cause: `Hero.tsx:163-167`.
Fix: choose the line break by fit: two lines while the longest fits at the narrow end of the axis, otherwise
three ("Notifications / you'd actually / design."), and the width opens up again. Size stays.

**M3. `compact` leaves the first screen empty.** (builder's point 5, confirmed) `i-hero-compact.png`: a 70 px strip
and 700 px of nothing. Cause: `hero.css:34-39`.
Fix: compact sets the headline on one line across all twelve columns at full size (the axis at its narrow end),
with icon, time and actions on a second row; the stage keeps its reserved height and the blueprint ground.

**M4. The time field overflows its cell when the canvas is narrow.** `i-hero-drag-600.png`: "12:13" is cut by the
handle. Cause: `hero.css:83` (clamp to 28 px in a two-column cell). Fix: size from the cell (container query).

**M5. Flow: three column heads on three baselines; the template is five empty grey boxes.** (point 3, confirmed)
`b-1440-flow.png`: "manifest" at y 498, "template · 4 × 3" at 466 with the switch on a second row, "banner" at 466.
The template cells show only slot names, so the middle column, the Designer's own picture, is the dullest
thing in the section. Cause: `Flow.tsx:113,131-151`, `flow.module.css:2,27`.
Fix: one head row on one baseline; the collapse switch moves under the template; cells show the bound token
(`{title}`, `{status}` …) the way the Designer does, and the hot cell fills blue.

**M6. Below the hero the grid idea is carried only by copy.** (point 4, confirmed) Why, Actions, Agents,
Integrate, Download, Changelog: `b-1440-*.png`. Title top-left, paragraph, small proof, bone. Changelog has no
title at all (`ChangelogPreview.tsx:8-10`). Download is a paragraph and a button (`Download.tsx:23-55`).
Fix: every section title is a field in a cell (dashed cell, slot name, the page's column ruler above it);
Download becomes the closing blueprint band (the template again: icon, title, version, size, sha, actions);
Changelog gets a title and wide version numerals.

**M7. 1280: the page touches the window.** `s-1280.png`: the title cell starts 12 px from the edge.
Cause: `globals.css:131` removes the shell padding at ≥ 1280 while the shell is 1232 wide. Fix: a fluid gutter.

**M8. Docs index is not centred and still has an eyebrow.** `s-docs.png`: content sits in the left 60 % at 1440.
Cause: `docs.css:217` (`max-width` without `margin-inline: auto`), `app/docs/page.tsx:12`.

**M9. Unknown URLs get Next's default black 404.** `s-d.png` (middle). No `app/not-found.tsx`. Fix: a Day page
with the header, one line and two links.

**M10. Cloud band: the proof is small and low.** `b-1440-cloud.png`: the reply banner is 480 px wide at the
bottom right of an 835 px band, the top right quarter is empty.

**M11. The grid-to-banner Rive piece is off-system.** `i-designer-head.png`: a white card with a green "OK" pill
and a generic "h" tile beside a page that has one banner skin (night card) and two signal colours.
Cause: `scripts/gen-grid-banner.mjs` / `public/rive/grid-banner.riv`.

## Minor

- m1. Drum: "run a script." asks for Fragment Mono 700 and "open the app." for Archivo italic; neither face is
  loaded, so both are synthesised (`Actions.tsx:11-12`).
- m2. Hero status "Sent · stacked with Herald · this page (3)" wraps under the buttons (`i-hero-sent2.png`).
- m3. Why on a phone is 3 370 px, most of it the ledger restated row by row (`m0.png`).
- m4. Agents: the tool list types itself only after it scrolls in, so the right column is empty for a moment
  (`b-1440-agents.png`); the left list's caption is the only thing saying the buttons are links.
- m5. Footer and header use `herald-icon.png`; the SVG mark exists (`public/herald-logo.svg`). The PNG is
  transparent, so not a rule violation, but the SVG is sharper at 54 px.
- m6. Why and Designer frames are gradients (`why.css`, capture frame) while the concept says "no gradients".
  They are a wallpaper behind a real capture, so they stay; noted.

## Checked and fine

Send / Replay, stack counter and fan, Flow hover linking and collapse / keep space, six hotspots on the real
capture with Dark / Light, the drum (per-character 3D, each phrase in its own face, nothing listed under it),
Deploy → Yes → outcome, quiet hours hold and release, the waveform (click-only, Kokoro mp3, no speechSynthesis
anywhere in `src`), cloud reply and receipts, code tabs Run. No console errors. CLS 0.0001 on load.
No "5 s" claim. Proper nouns do not wrap at any of the four widths. `scrollbar-gutter: stable` is set.
