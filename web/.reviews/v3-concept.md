# Herald web v3 — concept

v2 is a correct product page that runs Herald in-page (one real banner stack, LERP flipper, RAV-style hotspots
on the real Designer, a Rive grid-to-banner piece, Kokoro samples). What it lacks is a single idea, and a visual
system that is not the 2025 template: serif display + humanist sans, blue-tinted charcoal alternating with paper,
an eyebrow over every heading, three equal cards per row. v3 keeps the engine and the honesty and replaces the
composition, the type, the colour and the motion with one idea taken from the product.

Not SBF, not fNav+, not LERP: no UI object at poster scale, no grey world resolving into colour, no serif, no
italic pivot word, no magenta, no "resolve", no pinned zoom-out, no dark spectrum, no Rive hero.

## The idea: the page is laid out on Herald's grid

Herald's one unique object is a banner you lay out yourself on a grid of any size: fields bound to cells, cells
merged, nine-point alignment, empty fields that collapse or hold their place. v3 makes that grid the page.

At 1440×900 the first screen is a Designer canvas at page scale: twelve columns of dashed, rounded cells on a
bone ground, each cell carrying its small mono label in the corner the way the Designer draws an empty slot:
`icon`, `title`, `time`, `body`, `actions`. For 400 ms that is all there is. Then the fields take their cells,
one every 90 ms, each arriving from the right edge the way a banner arrives on a Mac: the Herald mark into
`icon` (its red dot pings), the real clock into `time`, the headline into `title`, the lede into `body`, the
real Download button and the docs link into `actions`. The labels fade as their cells fill.

    Notifications you'd actually design.

The headline is set in Archivo, a grotesk with a width axis, and the width axis is bound to the cell: the words
expand or condense to fit the cell they are in. At 1.9 s the template is sent: a banner with the same fields
slides in under the bell at Mac size, the bell counts 1, and the poster's Send button reads "Sent". The thing
you were looking at was a notification. (As first built the template also switched layout by itself at 1.9 s;
that moved every cell for a visitor who had not asked, measured as a 0.38 layout shift, so the re-layout is now
only the visitor's.)

Then it is yours. Three real Herald layouts (`imageLeft`, `hero`, `compact`) sit where the Designer's layout
picker sits; click one and the fields move. `compact` collapses `body` (an empty field that collapses) and the
headline condenses to one line. On the template's right edge is a handle: drag it and the grid reflows live,
the headline re-fits its width axis as you drag, cells merge and split. "A grid, not a form. Any size." at
page scale, in type, not in a screenshot. Send puts the template under the bell again, stacked with a counter.

Why it is true to the product: the Designer binds fields to cells on a grid you size; the banner that results
stays on screen and acts. The hero does exactly those things with the page's own headline, then proves the
result by sending it to the page's own Herald. Nothing in the fold is decoration: every line is a cell, every
word is a field, every button is a real action.

Why it is bold: a page whose headline moves between cells and changes width to fit is an image nobody puts on
a product page; a dashed Designer grid as the first thing on screen, with mono slot labels and no picture, is
a composition, not a template; and the load sequence ends by turning the hero into a notification, which is
the product's whole claim in one move.

## Type system

- One family: **Archivo** variable (wdth 62–125, wght 100–900), via next/font. Headline: wght 800,
  `clamp(52px, 7.2vw, 118px)`, leading 0.9, tracking −0.03em, width axis bound to the cell (62–125, the fit
  computed from a hidden measuring span, never below 62: if it still does not fit, it wraps). Sentence case,
  full stop. No accent word, no italic.
- Section titles: Archivo 800 at `clamp(36px, 4.6vw, 68px)`, wdth 100, leading 0.95, tracking −0.025em. No
  eyebrows anywhere. No numbering. A title carries its section.
- Body: Archivo 400 at 17/1.55 (16 on phones), measure ≤ 62ch; lede 20/1.4 wdth 100 wght 500 for the
  hero only.
- Labels, readouts, timestamps, cell slots, code: **Fragment Mono** 400, 11–13 px, letter-spacing 0.02em,
  lowercase, never tracked uppercase. The mono is the Designer's voice (slot names, `{title}`, `22:56`,
  `360 pt`) and the API's (`herald send …`); it is used nowhere else.
- Inside banners: Archivo too (title 15/600, sender 12 muted, body 13), because the page's banners are the
  page's own rendering of Herald, not a macOS mock. The real captures in the Designer section stay SF.
- Type scale ratio 1.333 from 13: 13 · 17 · 23 · 31 · 41 · 55 · 73 · 97 (fluid between the top sizes).

## Colour

Two inks and two signals. Everything is tinted toward Herald's blue (hue ≈ 250) so no grey is neutral.

- Day (the page, ~75 %): ground `--bone #f4f6fa`, cell `--bone-2 #e8edf4`, hairline `--hair #cdd6e2`,
  ink `--ink #0e1b36` (deep blue-black, never #000), muted `--ink-2 #4b5a75`.
- Night (one band: Living + Cloud, and the footer): ground `--night #0b1530`, surface `--night-2 #13203f`,
  hairline `--night-hair #263559`, ink `--bone`, muted `#9aa8c4`.
- Herald blue `--blue #3b9be8` (the mark's blue) for what Herald says: links, the bell, the Open button,
  the live waveform, selected layout, a filled cell's outline on hover. On bone, text uses
  `--blue-ink #1b6fb8` (≥ 4.5:1).
- Signal red `--red #d9371e` for what needs you: the stack counter, Record, destructive buttons, the
  confirmation strip's Deploy, the mark's dot. Never decorative.
- Banners: `--night` cards with `--night-hair` edge and 14 px radius on Day; the same card with the
  `--night-2` ground in the Night band. One skin.
- No gradients, no glass, no glow, no shadows except the banner's one 0 8px 24px tinted to the ground.

## Grid and layout

- The page grid: 12 columns in a 1200 px shell (6 at 640–1023, 4 below), 24 px gutter. Sections are laid on
  it with named areas, not centred stacks; titles take columns 1–8, proof takes 7–12 or the full width.
- The Designer cell: 1px dashed `--hair`, 8 px radius, the slot name in Fragment Mono 11 at top-left inset
  8 px. Used literally in the hero and the Flow template; a filled cell loses its label and its dash.
- Rhythm: section padding `clamp(88px, 11vw, 160px)`; one 1 px `--hair` rule between sections on Day, none in
  the Night band. No cards except banners and the real captures. Three-equal-card rows are gone: Living
  is a 7/5 split with the quiet-hours clock as the figure; the Why ledger is a two-column table that reads
  as one.
- Header 64 px, the icon 54 px, nav in Archivo 500 14 px, the Rive bell with its red count, one primary
  button. Footer in the Night band, 56 px bottom bar.

## Motion language

One verb: **take its cell**. Nothing fades up from below; a thing moves from where it was to where it belongs
and the ground stays still. Entrances arrive from the right edge (Herald's arrival), 420 ms expo; layout changes
are FLIP, 560 ms expo; state changes 220 ms quint; press feedback 120 ms. Eases: expo `(.16,1,.3,1)` for
layout and arrivals, quint `(.22,1,.36,1)` for state. No springs, no bounce, no blur-in, no hover-scale, no
parallax, no pinning, no looping attention-seekers (the mark's ping and the bell ring answer a send; the
waveform moves only while a sample plays).

Four motion pieces, each with a reason:

1. **The template (time-driven, once, 1.9 s):** empty grid 0–400 ms; fields take cells from 400 ms at 90 ms
   stagger; auto Send at 1.9 s (arrival under the bell above 1024 px, bell rings, counter 1). Replay in the layout picker. Reduced motion: end state at t = 0, no auto
   send.
2. **Layout and width (answers to the user):** the three layouts FLIP the fields; the handle (or the Width
   slider on touch) reflows the grid and re-fits the headline on every frame of the drag; Send stacks the
   template under the bell with a counter.
3. **The grid-to-banner Rive piece** in the Designer section plays once in view and replays on click; the
   hotspots on the real capture draw their callouts.
4. **The LERP drum** in Actions: per-character flip of the action kinds, nothing listed beneath the headline.

Reveals on scroll: none. Sections are visible as they come; only the Rive piece and the arrival cards animate.

## Sections and what each interactive element demonstrates

1. **Template (hero).** Layout picker → fields FLIP (Herald's four built-in layouts; three shown). Drag handle
   / Width slider → grid reflows, headline re-fits (grid of any size). Send → a banner with these fields
   stacks under the bell with a counter (same app = same stack). Download → the 1.6.5 DMG. Docs → the API.
2. **Why.** A real macOS alert beside a real Herald banner at one scale; the ledger argues layout, actions,
   confirmation, reply, history, grouping, voice, focus, agents. Nothing in it says five seconds. The Herald
   banner's Open runs the action and shows the outcome line.
3. **Apps declare. You design. Herald renders.** The manifest → template → banner pipeline on Designer cells;
   hover a field and its cell and its rendered element light together; collapse / keep space switches the
   rule and the banner reflows; Send test stacks it under the bell.
4. **The Designer.** Real captures (light/dark) with RAV-style hotspots; the Rive grid-to-banner piece heads
   it and replays on click.
5. **Buttons that …** (the drum). Deploy on the banner → inline Yes/Cancel → "Deployed · kept in History";
   Snooze → gone and back; × → History.
6. **Night band — Loud when it matters. Quiet when it doesn't.** Same sender again → the counter goes up,
   click fans the stack; the quiet-hours clock (drag or "Pretend it is 23:30") holds a send until 07:00 and
   "Show anyway" releases it; the voice sample's real waveform (decoded from the Kokoro mp3) draws under
   Play, click-only. **Let your agent speak to you:** the cloud banner reads itself (Play), takes a typed
   reply or Record → transcript → Send, and the receipt line fills received · displayed · spoken · replied.
7. **For agents / Ten lines.** One section, two columns: the MCP install list (click → the steps) and the
   code tabs (Run → a banner under the bell).
8. **Ready when you are.** Facts from the 1.6.5 release with fallback; recent changelog.

## Three alternatives I rejected

- **The stage.** Notifications as actors, a cue list, GO fires the next, house lights down for quiet hours. The
  most theatrical and the least true: Herald has no stage, no lighting, and the metaphor would sell drama on
  a product whose point is that it never steals focus. The cue list survives as nothing.
- **The day.** The scroll as a clock from 07:00 to 22:00, the ground going from day to night, banners held
  at night and released in the morning, the whole page obeying quiet hours. True, and it would have made
  the quiet-hours engine the page's physics, but it is a colour arc driven by scroll, which is SBF's structure
  in a different costume, and it spends the fold on the feature you use least. Quiet hours keep one band.
- **The broadsheet.** "The Herald" as a newspaper: masthead, dateline, columns, every section a story with a
  banner you act on. A good pun and a strong typographic page, but a newspaper is the one thing you cannot
  act on or get back, which is the opposite of the product's claim. Type at scale and the mono datelines
  survive without the costume.

(Also rejected: a control-room page of readouts — the dark-terminal cluster every AI reaches for; and a
poster-scale banner — a UI object at 2.4× is SBF's hero.)

## What stays from v2

HeraldHost and the one list of cards (send, stack, snooze, held, history, arrival card, bell pin); LiveBanner's
behaviour (Deploy → inline confirmation, Snooze returns, counters, ×, reply + Record); the LERP flipper; the
Designer hotspots on the real captures and the Rive grid-to-banner piece; the Rive bell and status ring;
Kokoro samples, click-only; the Why argument; the docs shell (centred, 54 px icon in 64 px bars linking home,
entities decoded, tables never wrap code); the release fetch with the 1.6.5 fallback; nowrap nouns;
scrollbar-gutter stable; the transparent SVG mark; the puppeteer suite, extended.
