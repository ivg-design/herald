# Testing Herald

## Unit tests

```sh
swift test
```

Runs the package's tests (router, payloads, history, snooze, templates, grid solver, designer model, MCP protocol and so
on) without launching the app. The SwiftUI views live in the Xcode app target, which the package test host cannot
link, so everything that is pure (`Sources/Herald/Core`, `Sources/HeraldClient`, the models) is tested here.

## Banner snapshot tests (live)

`Tests/HeraldTests/BannerSnapshotTests.swift` covers what a banner looks like. It renders templates through a running
Debug Herald over `POST /v1/preview` (the route the Designer, the MCP's `render_preview` and agents use; one
`GridBannerView` draws it, offscreen with `ImageRenderer`) and compares the PNG with a reference in `Tests/Fixtures/`.

These tests are opt-in: without `HERALD_UI_TESTS=1` the live ones are skipped, so a plain `swift test` stays fast and
needs no window server.

```sh
xcodegen generate
xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug \
  -derivedDataPath /tmp/herald-dd build CODE_SIGNING_ALLOWED=NO

HERALD_UI_TESTS=1 HERALD_UI_APP=/tmp/herald-dd/Build/Products/Debug/Herald.app \
  swift test --filter BannerSnapshotTests
```

| Variable | Meaning |
|---|---|
| `HERALD_UI_TESTS=1` | Run the live tests. |
| `HERALD_UI_APP=/path/to/Herald.app` | Launch that build on a free port with a throwaway support folder (its own token, history and settings files; quit when the run ends). Your installed Herald is not touched. |
| `HERALD_PORT`, `HERALD_SUPPORT_DIR` | Instead of `HERALD_UI_APP`: use a Debug Herald you started yourself with the same variables. The tests register an app called `ui-tests` in it. |
| `HERALD_UI_PORT` | Port for the launched instance (default: any free one). |
| `HERALD_UI_RECORD=1` | Write the references instead of comparing against them. |

### What is covered

| Test | Checks |
|---|---|
| `testEveryBuiltinTemplateMatchesItsReference` | `builtin.imageLeft`, `imageRight`, `hero`, `compact`, light and dark, against references. The same built-in asked for by name has the same width. |
| `testCustom3x4GridMatchesItsReference` | A 3 x 4 grid with an image over two rows, a badge, the issuer icon and an action row, light and dark. |
| `testCollapseKeepMatrixOnTheRealRenderer` | An empty subtitle under every combination of the template's `collapseEmpty` and the component's `emptyBehavior`: collapsed, kept, and equal to the banner with data when kept. Two references. |
| `testActionRowOverflowOnTheRealRenderer` | Six buttons in `row`, `wrap` and `stack` layouts, with and without `maxVisible`: `row` stays one line (the rest behind "+N"), `wrap` and `stack` grow, the cap changes what is drawn, and the banner is never wider than its grid, even at 280 pt. Four references. |
| `testPreviewShowsNoImageRendererPlaceholder` | `ImageRenderer` cannot draw an AppKit-backed view (an `NSViewRepresentable`, even inside a `.background`): it paints a saturated yellow card with a "prohibited" sign over the banner. One such view in `BannerView` or a component ruins every preview, so this fails with a message that says so. |
| `testTheSameRequestRendersTheSameImage` | The same request twice gives (nearly) the same pixels, which the references rely on. |

Always on, no app needed: `SnapshotInfrastructureTests` (the PNG comparator and that every reference exists and decodes),
`CollapseKeepMatrixTests` (the same collapse/keep matrix through `HeraldTemplate.plan` and `GridSolver`, rows and columns,
against an independently written oracle), `ActionsRowOverflowTests` (`ActionOverflow` and how rules decide which
buttons survive a cap).

### References

Fixtures are 1x PNGs named after what they show (`builtin-hero-dark.png`, `grid3x4-light.png`,
`matrix-collapse-light.png`, `actions-row-max2-light.png`). The comparison is tolerant: a pixel differs when a channel
is more than 12 off, and at most 0.4% of the pixels may differ with a mean difference under 1 level
(`PNGCompare.Tolerance.standard`). A mismatch writes the actual image and a diff (differing pixels in red) to
`$TMPDIR/herald-ui-tests-failures/` and attaches both to the test report.

The references are pixels of the macOS version they were recorded on. After an OS update that moves text, or after a
deliberate change to a banner, a template or a built-in, re-record, look at the changed PNGs in git, and commit them:

```sh
HERALD_UI_TESTS=1 HERALD_UI_RECORD=1 HERALD_UI_APP=/tmp/herald-dd/Build/Products/Debug/Herald.app \
  swift test --filter BannerSnapshotTests
git diff --stat Tests/Fixtures
```

Two things are pinned so a reference does not change between runs, and are worth knowing when you add a case:

- **The clock.** A built-in's timestamp shows the delivery time, and its text width moves everything to its right by
  fractions of a point, so the tests draw the built-ins with the timestamp bound to a fixed `{frozenClock}` field.
- **The issuer icon.** An app without an icon gets a letter tile whose hue comes from `String.hashValue`, which Swift
  seeds per process, so the tests register their app with a fixed icon.
