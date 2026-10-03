# Round 2 critique (UX / design effectiveness)

**One-line read of the page before fixes:** a strong hero and a strong Designer section carrying a middle that still argues the wrong point (Why) and diagrams instead of demonstrates (Flow).

## Hierarchy and narrative
- Hero → Why → Flow → Designer → Actions → Living → Cloud → Agents → Integrate → Download → Changelog is the right order. Each section has one headline idea; the display serif at 64–128 px with a single italic accent line is doing the work.
- The Why section breaks the narrative: the "5 s" numeral is the loudest element on the first scroll and it is wrong. The ledger (good, static, readable) is buried below a gimmick and a blank column. Fix: lead with evidence (a real macOS alert beside a real Herald banner at the same scale), make the ledger the argument.
- Flow explains the product's mechanism but the three-box diagram with arrows is the least designed moment on the page; the mechanism (field → cell → banner) is a mapping, and mapping is best shown by linked highlighting, not by arrows.

## Interaction honesty
- Every demo really does something Herald does (send, stack, snooze, confirm, quiet hours, reply/record, MCP tools, copy/run). Good. Two honesty gaps: the Flow row-collapse rule (icon cell in row 1) and the Why premise.
- The overlay after a send is the one interaction that works against the reader: it covers what they are reading. In the real app a new banner arrives alone in the corner; the full stack is a menu-bar click away. The page should do the same (single arrival card, 4 s; full stack on bell hover/click).

## Composition at each width
- 1440: Why right column empty; Living headings misaligned; Agents list half-empty while typing. Everything else balanced.
- 834: nothing breaks, but the hero dock lands below the first screen.
- 390: dock far below the fold; code block clipped on the install page; proper nouns wrap.

## Copy
- Headlines are specific and short. The Why headline survives if rewritten around history ("get one back"). Remove "Gone. It is not in any history." and "Herald's corner".
- "brew install --cask herald (planned)" invents a feature; remove.

## What will the owner remember?
The page running its own notifications (hero dock → bell → stack) and the Designer hotspots. Add one more memorable thing that is about the product idea itself: a banner that assembles from grid cells (Rive) in the Designer section.
