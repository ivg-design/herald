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

---

## After (same day, measured on the final build)

Evidence: `t-*` (hero tour frames), `a-*` / `z-*` (sections at 1440 / 1280 / 834 / 390), `j-*` (interactions) in
`web/.screenshots/r2/`.

| Finding | Before | After |
| --- | --- | --- |
| B1 type shared with WebWatcher | Archivo 800, titles at wdth 68 | Georama (wdth 62.5–150); titles wide at wdth 132; hero bound to the cell, 143 at rest on 1440 |
| B2 version | 1.6.4 / build 14 | 1.6.5 / build 15 in the hero button and Download; fallback carries the real size and digest; a live answer can no longer downgrade it; changelog content synced |
| B3 hero needs a click | static until clicked | sent at 1.4 s, then tours imageLeft → compact → hero and the handle glides to 70 % and back, once; any input ends it. Measured CLS through load + tour + glide: 0.0001 (1440), 0.0001 (390), 0.007 (834, buttons re-wrapping inside the actions cell) |
| M1 timid hero | navy on bone | blueprint ground (#1554c0), white wide headline at 124 px on three lines, column ruler with live track widths, layout picker with glyphs above the canvas, labelled grip |
| M2 step-down | 124 → 102 px at 702 pt | size constant; the axis runs 143 → 62.5 across the whole drag range (suite asserts it) |
| M3 compact empty | 70 px strip | one line across twelve columns at 99 px, second row icon / time / actions, centred in the reserved canvas |
| M4 time overflow | clipped | sized from its cell (container query); asserted at the narrow end |
| M5 Flow | three baselines, empty cells | one baseline, cells show `{title}` … `{action}`, hot cell fills, switch under the template |
| M6 grid only in copy | plain heads | every section head is a `title` cell and a `body` cell; Download is the closing blueprint template (icon, title, version, size, sha, requirements, actions); changelog has a head and wide version numerals |
| M7 1280 gutter | 12 px | fluid gutter, 41 px at 1280 |
| M8 docs index | left 60 %, eyebrow | centred, no eyebrow |
| M9 404 | Next's black page | the site's own, Day ground, header and footer |
| M10 Cloud | small low card | banner is the figure in cols 7–12, ruled capability list in 1–6 |
| M11 Rive piece | white card, green pill | night card, blue pill and button; rebuilt locally with `rive --once` |
| m1 drum faces | two synthesised | mono at 400, "open the app." upright wide Georama |
| m2 status wrap | wrapped | one line with ellipsis |
| m3 Why on a phone | 3 371 px | 2 529 px, every row kept |
| m4 agents list | typed in late | present at first paint |

Not changed: m5 (PNG icon in header and footer: transparent, left as is), m6 (wallpaper gradients behind the real
captures stay).

Also changed: section rhythm tightened (`clamp(64px, 8vw, 112px)`); Changelog now precedes Download so the page
ends on the blueprint band; banner primary buttons moved from `--blue` to `--blue-ink` and the Record button to a
darker red (white text was 2.98:1 and 4.33:1); quiet-hours "now" label lightened on Night.

### Numbers (final build)

- Suite: 195 passed, 0 failed (was 164; 31 added for the tour, real-mouse drag, CLS, blueprint, section heads,
  Flow baseline and tokens, version, 404, docs index, 1280 gutter).
- ESLint: 0 errors, 4 warnings (unused helpers in `scripts/test-demos.mjs`, there before this round).
- `next build`: clean, 68 static pages.
- Lighthouse desktop: performance 99, accessibility 100, best practices 100, SEO 100; LCP 1.0 s, CLS 0, TBT 0 ms.
- Lighthouse mobile: performance 90, accessibility 100, best practices 100, SEO 100; LCP 3.7 s, CLS 0, TBT 10 ms.

### Still weak or unverified

- Mobile LCP 3.7 s: the headline is the LCP element and waits for the Georama file. Not tuned this round.
- 834: the tour costs 0.007 CLS (action buttons re-wrap when their cell narrows). Under the 0.01 the suite
  allows, but not zero.
- On a phone the hero is 1 046 px tall, so the Download button is below the first screen at 390 × 844.
- 834 uses the phone ledger in Why rather than the table; readable, but a table would fit.
- The blueprint blue and Georama are this reviewer's call; the owner has not seen them.
- The Rive piece's small mark is a blue tile with two dots, not the real Herald mark.
- Hotspots, waveform play and cloud Record were exercised headless only; audio output itself was not heard.
- `/changelog` and docs article pages were looked at once after the type change (1440 and 390), not at 834 / 1280.
- The drum's Georama phrase and the two long phrases at 390 were checked by the suite's overflow test, not by eye
  in every phase of the flip.

---

## Owner pass (after the round-2 review)

Requests from the owner after seeing the first result, and what was done. Evidence in `web/.screenshots/r2/`
(`g-*` large viewports, `e-*` editor, `an-*` anchors, `nar-*` narrowed headline).

- **Hero on large monitors.** Only the hero scales. Above 1440 the canvas is `max(1200px, 82vw)` wide and the
  headline takes the height the fixtures leave: `(100vh − 64px − 462px × kf) / 2.92` (three lines plus descender
  room). Labels, buttons and the lede grow by `kf = 1 + 0.4 (k − 1)`, at most 1.3, where
  `k = min(width / 1440, height / 900)`. Measured (canvas share of the window width / template bottom as a share
  of the first screen / headline size): 1440×900 81.8 % / 93.9 % / 124 px; 1920×1080 80.8 % / 94.6 % / 177 px;
  2560×1440 80.9 % / 95.1 % / 275 px; 2681×1589 80.9 % / 95.3 % / 317 px; 3440×1440 81.2 % / 95.1 % / 275 px.
  The hero is exactly the first screen at all five. Nothing outside the hero is scaled. On the landing page the
  header keeps its size and takes the canvas's edges above 1440.
- **The hero is a small Designer.** Drag a field by its grip onto another cell: the two swap (GridEditing.move),
  the headline re-fits by break, size and width axis. Drag a column divider on the ruler or a row divider on the
  left ruler: the track takes the size, its neighbour gives way (24 pt floor for columns as in the app; rows stop
  at 64 px here). Double-click a column divider: equal columns again. Keyboard: arrows on a grip move the field to
  the nearest cell, arrows on a divider resize by 8 pt. Touch: tap a grip, then tap the target cell; tap a column
  on the ruler for a − / + stepper. The right edge, the three presets, Replay and Send stay; Reset is new. The
  tour shows one move and one track resize, then goes back. The first edit turns content-sized rows into fixed
  ones, so the hero's height never changes (asserted). Left out: span changes by dragging a cell edge, per-cell
  alignment, field on/off in the hero (Flow has collapse / keep space). The banner Send puts under the bell
  states the arrangement in its body text; it does not re-lay itself out.
- **Descenders and touching lines.** The headline carries 0.16 em under its last line; condensed settings open
  the leading from 0.92 to 1.02 and give up a little size instead of growing. Lines are placed by transform, so
  a change of break or size shifts nothing. Asserted across the width range in all presets at 1440 and 2560.
- **Real app icon** in the hero and Download icon cells (512 PNG / 1024 WebP via srcSet), fitted to the cell's
  content box, no tile, radius or clip. Radius clips removed from the header icon, footer icon and MiniIcon.
  Left: `.docs-brand-icon` in docs.css (another worker's file at the time).
- **Flow** has four payload presets (ci.bot passed / failed, WebWatcher, Claude) and per-field value chips; one
  template renders all. Badge colour stays one tone because the docs make it a template setting.
- **No demo moves the page.** Every interactive banner sits in a reserved stage; a suite section clicks every
  button in seven sections at 1440 and 390 and asserts section height, next section top and document height.
- **Focus rings** are no longer clipped in banners (asserted geometrically).
- **Designer at its anchor** fits one screen: compact head row, the capture sized from the height left, the six
  notes beside it. All nav anchors land with the title cell about 16 px under the header.
- **Header at 1024** no longer overflows (links tighten 1024–1199); the changelog-only patch is gone.
- **Download band**: icon fills a square cell; version, size and sha are sized to their cells.

Numbers on the final build: suite 352 passed, 0 failed; ESLint 0 errors, 5 warnings; Lighthouse desktop 99 / 100 /
100 / 100 (LCP 0.9 s, CLS 0), mobile 90 / 100 / 100 / 100 (LCP 3.7 s, CLS 0); CLS through load and tour 0 at 1440
and 2681.

Still weak: a dragged field is carried as its whole cell (a large title cell covers much of the canvas while it
moves); with the body in a very large cell the lede sits small in its top-left; the editor was judged from
headless frames, not by hand; Safari was not run; mobile LCP unchanged.
