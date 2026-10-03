# v3 build rules (every worker)

Read `.reviews/v3-concept.md` first; it is the design. Tokens and primitives live in `src/app/globals.css`
(read it: `.g` grid, `.cell` + `.slot`, `.display-xl/-l/-m`, `.lede`, `.body`, `.readout`, `.btn`, `.mb*`, `.night`).

Ground: Day is the default (bone ground, deep blue-black ink). Only the Night band (Living + Cloud) and the
footer use `.night`. Drop every `section-dark` / `section-paper` / `on-paper` class from your sections unless the
concept says the section is Night. Never use `--paper*` or `accent-on-paper` names in new code.

Type: Archivo only (`var(--font-sans)` = `var(--font-display)`), Fragment Mono for readouts/labels/code
(`var(--font-mono)`). Titles: `.display .display-l` (hero: `.display-xl`). No eyebrows (delete every `.eyebrow`),
no tracked uppercase labels, no accent-coloured or italic words in titles, no "→" after links, no "A · B · C"
meta strings except real timestamps/senders inside banners, no numbered 01/02 markers.

Colour: `--blue` only for what Herald says (links `text-accent-text`, the bell, Open, waveform, selected state);
`--red` only for what needs you (counters, Record, destructive, confirm). No gradients, no glass, no glow, no
shadows except `.mb`'s. No #000/#fff large areas. Tailwind colour classes map to the ground tokens
(`text-ink`, `text-muted`, `bg-surface`, `border-line`, `text-accent-text`, `text-signal`).

Layout: sections are placed on the `.g` 12-column grid (6 at 640–1023, 4 at <640) with explicit
`grid-column` spans (Tailwind `col-span-*` / `lg:col-start-*`), titles in columns 1–8, proof in 7–12 or full
width; no centred stacks, no three-equal-card rows, no cards except banners and real captures. Section padding
is `.section`'s. Everything must fit 390 px wide with no horizontal overflow; proper nouns never wrap
(`nowrapText` from `@/lib/nowrap` or `.nowrap`).

Motion: one verb, "take its cell": no fade-up-on-scroll reveals, no hover-scale, no blur-in, no springs,
no parallax. Entrances from the right edge 420 ms `--ease-expo`; layout changes FLIP 560 ms expo (framer-motion
`layout` / `layoutId` is fine); state 220 ms `--ease-quint`; press 120 ms. Respect reduced motion (end state).

Behaviour (hard): every interactive element shows a visible outcome in the page; every demo sends to the
page's Herald via `useHerald()` (`send`, `setQuiet`, ...) so banners stack under the header bell; keep every
section `id` (`top why flow designer actions living cloud agents integrate download changelog`), keep the
existing data attributes, roles, button labels and `aria-*` the puppeteer suite reads
(`scripts/test-demos.mjs`, grep your section before changing any text or selector). Voice is click-only
Kokoro samples (`playVoice`); never speechSynthesis. Facts come from `getRelease()` (1.6.5 fallback).

Process: edit only the files you own. Type-check with `npx tsc --noEmit` and lint your files with
`npx eslint <paths>`; do NOT run `next build`, `next dev` or any server (the lead builds and screenshots), and
never touch port 3102. Do not commit. Report: what you changed, what each interactive element now demonstrates,
and anything you could not finish.
