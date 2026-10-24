# Reader and Browse UI audit

> **Historical record, 2026-10-22.** Every defect in the corrected table below has been fixed
> and the branch it audited (`feat/v2-rewrite-manga`) is merged into `main`. Only the
> remaining findings are still live; they are tracked as open issues in
> [V2_PROGRESS.md](V2_PROGRESS.md). Do not treat the scores as current. Since then a device
> pass settled the right-edge dismissal finding (the swipe does not advance a page); Dynamic
> Type and the blur still have no device evidence.

Updated: 2026-10-22. Scope: the Browse, manga reader, chapter
directory, image-view, and Glur dependency changes on `feat/v2-rewrite-manga`.

This is a source audit with build and model regression checks. The supplied Browse
screenshots informed the spacing review. This Mac has no installed Simulator runtimes
or devices, so there is no new rendered-screen, gesture, haptic, or performance evidence.

## Platform conformance

The structure uses native navigation stacks, lists, tabs, sheets, SF Symbols, and glass
materials. It is not ready for a full conformance sign-off: the custom reader dismissal
gesture needs device testing *(settled later — see the banner)*, and GlurBackdrop uses private
system API.

## Provisional health score after fixes

Scores describe the changed surfaces from source; they are not a device certification.

| Dimension | Score | Main limitation |
|---|---|---|
| Accessibility | 2/4 | Some fixed text sizes and fixed control dimensions remain |
| Performance | 3/4 | Lazy rendering and image caching exist; blur performance is unmeasured |
| Appearance and theming | 3/4 | Requested white selections and gray surfaces are consistent; live contrast remains unchecked |
| Platform conformance | 2/4 | Private backdrop API and custom dismissal need release review |
| Adaptivity | 2/4 | Window width replaces screen width; compact landscape and large text are unverified |
| Total | 12/20 | Significant verification and accessibility work remains |

## Defects corrected

| Severity | Location | Finding and correction |
|---|---|---|
| P1 | `Features/MangaReader/MangaReaderView.swift`, webtoon and slider | Changing the slider only changed an integer. The webtoon never scrolled. Seeking now updates a bound scroll position; natural scrolling reports position back. Removed lazy-page `onAppear` writes, which could report prefetched pages as current. |
| P1 | `Features/MangaReader/MangaReaderView.swift`, slider | A tiny inner region owned the drag. The complete 44-point capsule now handles tap/drag seeking with clamped coordinates and VoiceOver adjustment. Removed the circular thumb as requested; the visual is a filled bar. |
| P1 | `Features/MangaReader/MangaPageView.swift`, `load()` | A retained image caused an early return even when its URL changed. Image reuse now checks the loaded URL, and cancelled requests cannot apply decoded images. Reader content also resets identity on chapter changes. |
| P1 | `Features/MangaReader/MangaReaderView.swift`, `loadChapter()` | An older fetch could replace a newer chapter's pages or error. Responses now check the requested chapter and cancellation. Loading clears old pages and progress writes require a valid loaded page. |
| P1 | `Features/MangaReader/MangaReaderView.swift`, chapter directory | The plain list lacked the existing reader's cover, bounded pages, search, jump, filters, and current-chapter navigation. It now reuses `ChapterDirectoryView`, including source cover/title metadata for unsaved manga. No TTS controls are introduced. |
| P2 | `Features/MangaReader/MangaReaderView.swift`, chapter choices | Unsaved titles previously had no usable directory or adjacent navigation. Source chapters load independently of library membership. The directory and arrows now share scanlator rules and ascending chapter order. |
| P2 | `Features/Browse/BrowseView.swift`, `loadPlugins()` | Defaulting only to `en` missed registries using `English`. The default now resolves either available value once, preserving later user choices. |
| P2 | `Features/Browse/BrowseView.swift`, controls | Removed duplicated grouped-list row margins. Selection is one persistent moving shape. Switcher, clear-search, and language-chip touch targets are now at least 44 points high. |
| P2 | `Features/MangaReader/MangaReaderView.swift`, geometry and chrome | Screen-global width broke local tap and edge coordinates in resized windows. Width is now measured from the actual reader. Control visibility respects Reduce Motion. |

## Remaining findings

### P1 — GlurBackdrop relies on private API

Location: `Features/MangaReader/MangaReaderView.swift`, `controls`, and the new
GlurBackdrop product in `LNReader.xcodeproj/project.pbxproj`.

The library explicitly documents private backdrop-filter API. A successful build does
not establish store acceptance or future OS compatibility. The requested Glur effect is
retained; evaluate distribution requirements before release. Suggested action:
`$impeccable harden` for the reader's blur implementation and fallback.

### P2 — Dynamic Type and narrow layouts need another pass

Location: manga `topBar` and `MangaPageSlider`; Browse `kindSwitcher` and `languageChip`.

Fixed title/chip font sizes and fixed label widths can clip at accessibility sizes.
The 44-point bottom row also leaves limited width in narrow windows. Use scalable text
and dimensions, then check portrait, landscape, and large text. Suggested action:
`$impeccable adapt` for these specific controls.

### P2 — Right-edge dismissal can overlap page gestures

Location: `MangaReaderView.dismissSwipe` and `pager`.

The requested leftward dismissal is simultaneous with page swipes. Starting at the
right edge can advance a page before dismissal. Local width measurement is corrected,
but recognizer arbitration needs a device test in both reading directions. Suggested
action: `$impeccable harden` for reader gesture ownership.

**Settled 2026-10-25:** the device pass showed the edge swipe does not advance a page.

## Verification

- iOS Simulator SDK build: **passed**, including the shared chapter directory changes.
- `./scripts/check.sh page-pipeline`: **passed** for cache, prefetch, loader, and progress.
- `./scripts/check.sh scanlators`: **passed** for priority, hide, dedup, and fallback rules.
- `git diff --check`: checked for whitespace errors.
- The scripts above do **not** exercise SwiftUI gestures, scroll-position binding,
  animation, haptic hardware, image appearance, or the new sheet presentation.
- Live checks remain: seek first/middle/last page in pager and webtoon; switch chapters
  during a slow load; verify directory cover and 50-item ranges; switch Browse tabs;
  inspect light/dark appearance and large text; feel selection haptics on hardware.

## Patterns and useful foundations

The earlier work repeatedly treated compilation as evidence that interactions worked.
The largest gaps were between the control's state and its rendered content, and between
saved-library data and Browse data. Shared navigation data and the existing chapter
directory reduce those gaps. Maintain the lazy page layout, cache/prefetch pipeline,
native navigation structure, adjustable slider accessibility, and Reduce Motion handling.

Recommended follow-up order: `$impeccable harden` for gesture/blur release concerns,
`$impeccable adapt` for large text and compact layouts, then `$impeccable polish` after
the listed device checks. Re-run the audit after those checks.
