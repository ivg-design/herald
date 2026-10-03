# Round 2 delight pass

Context: audience is Mac developers and agent builders; brand tone is precise, warm, a little playful (the ⌘⇧H egg). Delight must demonstrate the product, never decorate.

## Keep (already earning its place)
- The red dot on the hero mark pings when a banner is sent; the Rive bell swings and its badge pops.
- Inline confirmation strip with the Rive status ring (working → done) inside the banner.
- LERP per-character drum flipper for the action kinds.
- Cloud banner: Record → 3 s → transcript line; receipts light up.
- ⌘⇧H easter egg sends "You found it." through the page's own Herald.

## Add
1. **Grid → banner assembly (Rive)** in the Designer section, next to "A grid, not a form. Any size.": a 4×3 dashed grid draws itself, cells merge (title spans two columns), the icon, title, status badge, body and two buttons drop into their cells, the grid lines fade and a finished banner remains. Plays once when scrolled into view; click replays. It is the product's thesis in 2.5 seconds and it is not a duplicate of the editor capture below it.
2. **Field linking in Flow**: hover a JSON field and its cell and its rendered element light up together. Discovery reward: the reader "finds" the mapping.
3. **Arrival card**: a single banner sliding in under the bell after a send feels like the real app; the full stack on bell hover is the second layer of discovery.
4. **Why side-by-side**: both frames share the same desktop gradient; the macOS alert is faithful and quiet, the Herald banner is the one with buttons. The contrast speaks without copy.
5. **Phone hero**: the first screen shows a real banner card under the headline, with "+N more" to fan out – the product is visible before the pitch is read.

## Do not add
- Confetti, bounce easing, sound on load, cursor effects, parallax. Motion stays on transform/opacity with quart/quint/expo easing; everything respects prefers-reduced-motion.
