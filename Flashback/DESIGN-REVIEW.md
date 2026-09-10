# Flashback 1.5 design review

This pass reviews the app’s own interface: welcome, library, website importer,
player chrome and states, native dialogs, menus, About, Help, and license/source
information. Game artwork and the games’ own interfaces remain their original content.

## Findings and changes

| Surface | Finding | Change |
| --- | --- | --- |
| Welcome | Nested rounded panels, icon tiles, repeated purple accents, and promotional headings competed with the instructions. | One plain reading column, shorter feature names, unboxed formats, a clear copyright-free extraction reminder, and named navigation actions. |
| Shared appearance | Tinted backgrounds and several button treatments made the windows feel unrelated to macOS. | System surface colors, standard macOS button styles, restrained brand color, and consistent control sizes. A separate primary-action tint preserves white-label contrast in dark mode. |
| Library navigation | The sidebar used custom navigation buttons and a decorative online-style status dot for a local app. | A native sidebar list, direct filter names, compact branding, and no status dot. |
| Library content | Large slogans and placeholder gradients took attention from the games; screenshots could be cropped. | A smaller functional heading, quiet placeholders, complete artwork within consistent thumbnail bounds, and useful format/play metadata. |
| Search and empty states | Focus was not visible; empty states used vague slogans and duplicated decorative information. | A visible focus outline, Find Game (⌘F), direct empty-state explanations, and relevant actions. |
| Website workflow | Search and navigation actions moved between locations, and every result had a separate accented card. | Stable footer actions, clear step headings, a single result list, naming at review, and source/file information grouped for scanning. |
| Import feedback | Errors were long red paragraphs, progress used an oversized card, and file details appeared as an undifferentiated report. | A clear error heading, compact progress, explanatory partial-recovery warnings, and a native disclosure for detailed file information. |
| Rendered website scan | WebKit could suspend the offscreen scan before delayed game loaders ran. | Keep its temporary web view active during the existing ten-second scan on macOS 14 and later, then dispose of it normally. |
| Player | Repeated branding/title, large controls, and vague pause/error messages added clutter; long loading text could enlarge the window beyond the screen. | A compact toolbar with a Library action, clear Paused / Unable to Open Game states, standard action buttons, and window sizing independent of status text. |
| Dialogs | Rename and removal used app-modal alerts while other decisions used sheets. | Window-attached rename, removal, file selection, and entry-choice sheets, with cancellation preserving the library. |
| About and Help | About opened a long help alert. | A native About panel and a dedicated scrolling Help window with readable sections and shortcuts. |
| Licenses and source | Documentation styling was separate from the product’s revised visual language. | A neutral, readable document layout that retains all source, license, and attribution information. |

## Review basis

The design choices follow Apple’s guidance on [consistent buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
[system colors and appearance](https://developer.apple.com/design/human-interface-guidelines/color),
and [clear interface writing](https://developer.apple.com/design/human-interface-guidelines/writing).
The scan fix uses WebKit’s public [inactive scheduling policy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property).
The review checks specific qualities: hierarchy, spacing, typography, action
priority, keyboard focus, cancellation, text length, contrast, and state coverage.
Visual taste is assessed from the rendered app rather than treated as an automated pass/fail property.

## Verification

Reviewed from native window captures on an Apple Silicon Mac running macOS 27.0.
The release targets macOS 13 or later and builds for both ARM64 and x86_64.

- Welcome: first launch, a single window, light/dark appearance, Return,
  remembered dismissal, reopening from Help, and the website shortcut.
- Library: 24 games, five widths from 800 to 1440 points, light/dark appearance,
  long and multilingual names, portrait/wide/missing artwork, bottom-row
  scrolling, empty states, long import status, and high contrast. Bounds and
  click checks passed; titles, favorites, and adjacent cards stay separate.
- Navigation: native sidebar selection, favorites, clear search, and Find Game
  keyboard focus. The visible search field accepts input and filters the games.
- Secondary windows: file/entry selection, rename, removal, cancellation,
  Help scrolling, native About, and the license page in both appearances.
- Website import: Find Games by native click, Recover and Add by the Return
  shortcut, persistent provenance, and recovered HTML playback with modules,
  assets, input, and offline requests. The final release passed the delayed
  loader check with its launch parameters, plus light/dark progress, empty,
  many-result, partial-recovery, long-name, adding, and error states.
- Player: compact Flash, HTML5, and Shockwave loading/error views, plus Flash
  pause. Long titles stay inside a 640 × 500-point player. Flash and HTML
  integration checks passed, including controls, restart, local storage,
  offline requests, and recent history.
- Build: importer, website parsing/recovery/routing, and ZIP checks passed.
  The final executable contains both Mac architectures.

GUI checks use isolated libraries. A separate copy of the release with a test
bundle identifier was used for the complete visual audit, avoiding focus
contention with the open app preview. Game artwork shown during local checks
is excluded from the release.

This was a rendered-interface and interaction review, not a human design
certification or a full accessibility audit. VoiceOver, physical Intel hardware,
and older supported macOS releases still need manual validation. Compatibility
with individual games remains subject to each player’s existing limitations.
