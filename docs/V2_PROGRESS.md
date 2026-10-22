# v2 rewrite — status

**Updated** 2026-10-23 · **Branch** `feat/v2-rewrite-manga` · **Version** 2.0.0 (build 3)
· **Latest update** Performance pass: library counts, reader save storm, cover decoding

The rewrite replaces the v1 store with `SchemaV1`, adds a manga path end to end, and puts
every source behind one protocol so a JS plugin and a transpiled extension are the same
thing to the rest of the app.

Migration (`docs/MIGRATION_TO_V2.md`, plan §1) stays **deferred by decision**. The one
migration property that is honoured is the cheap one: v2 opens its own store file and never
touches `default.store`, so the old data stays recoverable on disk.

## At a glance

| Area | State | Notes |
|---|---|---|
| Data model | **Done** | `SchemaV1`, own store `LNReader-v2.store`, v1 models deleted |
| Novel read path | **Done** | Library, detail, chapter list, web reader, history, updates, stats |
| Manga read path | **Done** | Pager + webtoon, cache, prefetch, progress |
| Source abstraction | **Done** | `CatalogSource` / `NovelSource` / `MangaSource`; `SourceManager` registry |
| JS extension host | **Done** | JSC + `http`/`dom` bridge, bundle contract, repo/trust/install service |
| First extension | **Done** | MangaFire, ported from keiyoushi, verified live |
| Chapter lists | **Done** | Number ordering, all-chapters for manga, scanlator priority |
| Browse | **Done** | Split into Light Novels / Manga |
| Reader and Browse UI polish | **Implemented; device check pending** | Manga controls and dismiss swipe; Browse title and switcher; English default for novel sources |
| Extension repo UI | **On hold by user** | Existing service retained |
| WebView fetch primitive | **On hold by user** | Captcha-gated sources remain blocked |
| Kotlin/JS transpiler | **On hold by user** | Toolchain also absent |
| Downloads | **Implemented; device check pending** | Novel text and manga pages, durable queue, offline reader paths, pause/retry/remove, Wi-Fi and storage guards |
| Update scheduling | **Implemented; device check pending** | App refresh, continued/processing download tasks, per-title policy, optional notifications and new-chapter downloads |
| Trackers | **Deferred** | User's call |
| Migration (`.tachibk`, bridge) | **Deferred** | User's call; fresh installs start empty |
| Backup / restore (`.lnbk`) | **Local v2 format implemented; device check pending** | Authenticated encrypted snapshots, recovery key, merge restore; protobuf/cloud interoperability remains deferred |
| Performance | **Pass done; device trace pending** | Library counts cached off-main, reader writes coalesced, covers downsampled; see [PERFORMANCE.md](PERFORMANCE.md) |

## Roadmap — Mihon / Yokai parity

Ordered by dependency, not by size: the
per-series settings store comes first because reader modes, filters and incognito all read it.

| # | Feature | State | Depends on |
|---|---|---|---|
| R1 | Per-series reader settings store | **Implemented; device check pending** | — |
| R2 | Per-series read mode (pager / webtoon / direction) | **Implemented; device check pending** | R1 |
| R3 | Tap-zone layouts | **Implemented; device check pending** | R1 |
| R4 | Volume-key page turns | **Implemented; device check pending** | R1 |
| R5 | Auto scroll | **Implemented; device check pending** | R1 |
| R6 | Hold to scroll, with swipe-to-change-speed | **Implemented; device check pending** | R5 |
| R7 | Library filters | Planned | — |
| R8 | Library sorts (per category) | Planned | R7 |
| R9 | Categories: per-category sort, display, update scope | Planned | R7, R8 |
| R10 | Library badges | Planned | — |
| R11 | Duplicate detection | Planned | — |
| R12 | Migrate manga / novel to another source | Planned | R11 |
| R13 | Incognito mode | Planned | — |
| R14 | Download UI/UX polish | Planned | — |

### Reader (R1–R6)

- **R1 settings store.** One resolved-settings struct: series override ➝ global default.
  Keep it in UserDefaults keyed by `sourceKey::url`, like scanlator rules, not in the
  schema — it is a view preference. Everything below reads through it.
- **R1 as built.** `MangaReaderSettings.swift`: `MangaReaderOverrides` (optional fields, so
  adding a setting never breaks saved data), `MangaReaderPreferences` (resolved values) and
  `MangaSeriesSettings` (the persisted `@Observable` store, key `mangareader.<sourceKey>::<url>`).
  Overrides win field by field; a series that never overrode a field follows the global default,
  and an empty override set is removed rather than stored. Later settings are new optional fields
  on `MangaReaderOverrides`.
- **R2 as built.** The reader's layout menu now writes the series override. "Use for all series"
  promotes the series' effective values to the global defaults and drops the override;
  "Reset to default" appears once a series has overrides. Chapters opened outside a library entry
  are keyed by chapter URL. The global default is edited from the new Reader settings sheet
  (options menu → Reader settings…) as well as through "Use for all series".
- **R2 original plan.** Today `manga.readingMode` / `manga.pagingDirection` are global
  `@AppStorage`. Add a "this series" override with a "use default" state, shown in the reader
  options menu. Novels keep their own reader settings; only manga needs this.
- **R3 tap zones.** Layouts: default (thirds), L-shaped, Kindlish, edge, disabled, plus an
  invert toggle. Zones stay a simultaneous gesture, never an overlay (see Decisions).
  Zones must respect right-to-left.
- **R4 volume keys.** Needs a hardware-key hook (observe `AVAudioSession` output volume or
  `onHardwareKeyPress`/`UIPress`), swallow the HUD where possible, and invert in RTL.
  Per-series override optional. Check it does not fight the screen-awake setting.
- **R5 auto scroll.** Webtoon only at first: a `CADisplayLink`-driven offset, not a timer,
  so speed is frame-rate independent. Setting: speed in points/second, default and
  min/max. Stops on touch, resumes on a tap or after a configurable delay.
- **R6 hold to scroll.** Press and hold scrolls at a configurable speed; while holding,
  dragging up or down raises or lowers the speed. Configurable: base speed, step size per
  point dragged, min/max, and **which direction increases** (up = faster by default, with
  an invert option). Must not use an overlay that eats the scroll view's drag; implement as
  a simultaneous long-press-then-drag gesture and cancel it when the hold ends. Share the
  scroller with R5 so there is one animation driver.

**How R3–R6 were built** (`Features/MangaReader/`):

- **Pure rules** in `MangaReaderControls.swift`, checked headless by
  `scripts/check-v2-reader-settings.sh`: `MangaTapZoneLayout.action(at:in:…)`,
  `HoldScrollConfig.speed(forDrag:)`, `ScrollStep.advance`, `VolumeKeyDetector`, and
  `MangaControlSettings` (one JSON value under `manga.controls`; missing fields keep defaults).
- **R3 tap zones** — Default, L-shaped, Kindle-style, Edges, Disabled, plus invert. Per series
  (R1 overrides `tapZones` / `invertTapZones`). Right-to-left and invert are two reversals that
  cancel. Paged mode only; webtoon taps still toggle the controls.
- **R4 volume keys** — `VolumeKeyHost`. iOS reports a press only as a change in
  `AVAudioSession.outputVolume`, so while the reader is open the media volume is parked at 50 %,
  each change is read as up or down, then the volume is set back to 50 %; the user's volume is
  restored on leaving and whenever the app resigns active. A hidden `MPVolumeView` suppresses
  the HUD. Volume up goes back, down goes forward, with an invert option. Paged: one page;
  webtoon: ~85 % of a screen. This is a global setting, not per series.
- **R5 auto scroll** — `WebtoonScrollController` drives the strip's `UIScrollView` from a
  `CADisplayLink` (SwiftUI has no per-frame offset API; SwiftUI's own position tracking follows
  the offset). Speed in pt/s; the user's finger always wins — it waits for the drag and its
  momentum to end, then continues. Starts from the options menu, hides the controls, shows a
  stop button, and brings the controls back at the end of the chapter. Webtoon only; the pager
  has no equivalent yet.
- **R6 hold to scroll** — a `UILongPressGestureRecognizer` on the same scroll view (0.3 s). While
  held, the pan recognizer is disabled so the finger changes the speed instead of dragging the
  content; swiping up/down raises or lowers speed by `speedPerPoint` pt/s per point, clamped to
  min/max, and which direction speeds up is a setting. A speed readout shows while holding, and
  the tap that the lifted finger would otherwise register is suppressed for 0.4 s. Optional
  haptics (`HoldHapticTracker`): a selection tick per 40 pt/s crossed, a firmer tap on reaching
  the slowest or fastest speed.
- **Tap zones apply in webtoon too** (scroll ~85 % of a screen; "Disabled" restores
  tap-only-toggles). Reading direction does not apply to a vertical strip.
- **Settings** — `MangaReaderSettingsSheet` (options menu → Reader settings…): layout, direction,
  tap zones and invert are per series; volume keys, auto scroll speed and every hold-to-scroll
  value are global.

**Device checks R3–R6 need** (none could be run here — no Simulator runtime, device unavailable):
the scroll view is actually found from the webtoon content (`WebtoonScrollBridge`); hold works
without the strip also scrolling and without the lifted finger toggling the controls; auto scroll
pauses and resumes around a drag; the volume HUD stays hidden, presses register at the ends of
the range, and the volume is restored after closing the reader or backgrounding the app.

### Library (R7–R10)

- **R7 filters.** Downloaded, unread, started, completed, tracked, source/kind. Tri-state
  (include / exclude / off) like Mihon, persisted per category. Counts must come from
  `LibraryChapterCounts` — no relationship walks in a `body` (see Decisions).
- **R8 sorts.** Sort orders exist today (`SortOrder`); add per-category sort + direction,
  and "latest chapter", "last checked", "chapter fetch date". Sorting by unread must use the
  cached counts, never `Entry.unreadCount`.
- **R9 categories.** Per-category display mode, sort, filter and update scope. The category
  chip row already exists; this adds the per-category state behind it.
- **R10 badges.** Unread, downloaded, source/language, "new". Compute off-main and cache;
  badges are the main per-cell cost in the grid.

### Library maintenance (R11–R13)

- **R11 duplicates.** On add-to-library, match by normalized title (and alt titles) across
  sources and warn with a "view existing / add anyway" choice. Matching must be cheap: index
  once, not per keystroke.
- **R12 migrate.** Pick a destination source, search it, choose the match, then carry over
  chapters read, bookmarks, categories, added date and tracking, and offer to keep or remove
  the old entry. Match chapters by number (reuse `ChapterRecognition`). Do this as one
  background transaction so a failed migrate leaves the old entry intact. Works for both
  manga and novels.
- **R13 incognito.** A global toggle that suppresses history writes, reading progress, and
  `lastReadAt`. Must be visible (a banner or icon) so it is never on by accident, and must
  be respected by both readers and the downloader's auto-mark-read.

### Downloads (R14)

Polish the More → Downloads screen and the per-chapter download controls: clearer
queue states (queued / downloading / paused / waiting for Wi-Fi / failed), reorderable
queue, per-title progress, swipe actions, a visible download state on chapter rows, a
storage summary with a clear-all, and a sensible empty state. The queue and guards already
exist; this is UI and information design, so it needs a device pass.

## Landed

| Commit | What |
|---|---|
| `8308535` | v2 foundations: schema, container factory, HTTP stack, source protocols, `SourceKey` |
| `8de89a5` | App runs on v2: read path ported, v1 models deleted, sync mapping |
| `3cce227` | Browse through the source layer (`CatalogSource`, `SourceEntry`) |
| `a1c7d7d` | `ChapterSourceSync` + `ChapterRecognition` (Yokai port, 40 reference cases) |
| `d2cba3b` | `ChapterCache` (LRU) + `PagePrefetchPlan` |
| `bcf0f7f` | Manga reader: pager/webtoon, progress, `ChapterReader` routing |
| `11a7ed8` | Fix: project patch had dropped asset/icon references |
| `b1923c5` | Extension host: JSC bridge, bundle contract, store, repo/trust |
| `7423959` | MangaFire shipped as the first extension |
| `007fab2` | Reader as its own full-screen window; source icons; library kind filter |
| `ced3897` | Reader chrome states: focus / control, Liquid Glass controls |
| `8ed3d42` | Fix: tap overlay was eating scroll and swipe gestures |
| `629cb31` | Fix: order chapters by number; manga lists show everything |
| `abc7f23` | Scanlator priority + per-scanlator visibility |
| `6c32ca4` | Browse split into two catalogues |
| `86d0c39` | Version 2.0.0 |
| `3072d5d` | Reader controls polish, Browse refinement (Glur backdrop) |
| `846d553` | Offline chapters, background updates, encrypted library backups |
| `2092e97` | Rewrote this progress tracker as a status ledger |
| `3072d5d` | Reader/Browse UI fixes, shared manga chapter directory, audit, sample source removal |

## Offline library update

- **Downloads:** More → Downloads provides title batches, per-chapter context actions,
  durable queue state, pause/retry/removal, errors, progress, Wi-Fi waiting, and a 200 MB
  free-space guard. Novels save chapter HTML/text; manga saves page files. Both readers
  prefer validated durable files before consulting the network. Chapter folders are
  published with a manifest only after completion and survive cache eviction.
- **Background work:** task identifiers and modes are registered and declared. User
  batches request iOS 26 continued processing; pending work can resume in a scheduled
  processing task. Library app refresh has a requested interval, Wi-Fi preference,
  unread/completed filters, per-entry strategies, optional notifications and new-chapter
  downloads. Manual refresh overrides automatic-only entry restrictions. iOS controls
  when scheduled tasks run.
- **Backup:** More → Backup & restore exports AES-256-GCM `.lnbk` snapshots with a random
  Keychain recovery key. Covers metadata, categories, chapters, reading state/history,
  existing tracker records, preferences, profile, and local imported books. Restore
  merges without replacing existing title details or newer progress. Downloaded media,
  audio, source packages, credentials, and cloud transfer are excluded.
- **Format decision:** the local snapshot uses authenticated `LNRB` envelope version 2
  and a JSON payload with a random recovery key. It is distinct from the plan's proposed
  Argon2/protobuf format. `.tachibk` interoperability remains deferred migration work.
- **Checks:** simulator SDK build, offline-library encryption/restore/policy checks,
  existing schema checks, and page-pipeline checks passed. Interactive verification is
  unavailable: no installed Simulator runtime and the paired iPhone is unavailable.
- See [offline library notes](OFFLINE_LIBRARY.md) for usage, recovery, background behavior,
  current media/format boundaries, and the remaining device acceptance checklist.

## UI update

- **Manga reader:** top controls follow the novel reader's layout. The bottom controls now
  put a custom 44-point page slider and paired chapter buttons in one row, without a
  page-count pill. The slider and chapter buttons share the Liquid Glass capsule style.
  Light Glur backdrop blur replaces the black edge fade when controls are visible. A
  leftward swipe from the right edge dismisses the full-screen reader. The chapter sheet
  now uses the shared reader directory with cover/title metadata, search, jump, filters,
  and 50-chapter pages. It fetches source chapters for titles outside the library and
  applies scanlator rules consistently with adjacent navigation. The scrubber is a bar
  without a circular thumb and seeks both paged and webtoon content.
- **Browse:** uses the standard SwiftUI navigation title, a dedicated Light Novels / Manga
  switcher with `systemGray6`, one spring-sliding white selection, and selection haptics.
  The switcher and search field share a 44-point height, corner radius, and row margins.
  The selected language pill is white with black text; Global Search sits above the tab bar
  on the lower right. Available Light Novel sources default to English.
- **Verification:** iOS Simulator SDK Debug build and page-pipeline/scanlator checks passed.
  No Simulator runtime is installed here. The manga swipe, slider, safe-area layout, and
  Browse animation still need a device interaction check. See [UI audit](UI_AUDIT.md)
  for corrected defects, remaining issues, and the limits of these checks.
- **Sample source:** removed the offline sample manga source, its startup registration,
  and its Xcode project references.

## UX pass

- **Swiping switches kinds.** The Library kind picker and the Browse source switcher both
  looked like tabs but did nothing on swipe. They are now bound to the same `@AppStorage`
  key, with the chrome pinned above the content so a swipe moves only the list. They began as
  page-style `TabView`s; those were replaced with a single rendered page and a
  `horizontalSwipe` modifier (`Extensions/View+Extensions.swift`) because the nested pager
  built every page up front and fought the scroll view. Each Library page has its own empty
  state, so a filter that matches nothing no longer claims the whole library is empty.
  Category chips stay inside the page — they filter the grid, so they are content.
- **Browse's floating search button is an overlay**, not a bottom safe-area inset. The
  inset reserved a strip that nothing painted, which showed as a black bar under the list;
  the list now reserves scroll room with `.contentMargins` instead.
- **Add to Library answers immediately.** It used to require the details request to have
  finished — before that, taps were dropped with no feedback. It now seeds from the browse
  row, shows a spinner and disables itself while writing, and animates to "In Library"
  with a haptic. Details and the chapter list are fetched concurrently instead of in
  series, and the chapter list says "Loading chapters…" instead of "No chapters yet".
- **Launch update is deferred** by two seconds so the first frame and first tap are not
  competing with a library-wide refresh.
- **Risk:** the swipe is disabled while the library is in edit mode so it cannot compete
  with drag-and-drop reordering; check on a device that a long-press drag still starts.

## Open issues

1. **MangaFire captcha.** A `403 {"error":"captcha_required"}` from the API surfaces as an
   error. Upstream solves it with OpenCV.js in a WebView and a `waf_pass` cookie. Needs the
   WebView fetch primitive below.
2. **Reader UI needs device verification.** Shared chapter directory and scanlator
   rules are wired; seeking, gestures, large text, and blur still need interactive checks.
3. **Global search is novel-only.** `GlobalSearchView` iterates `sourceManager.novelSources`;
   hidden on the Manga tab rather than shown broken.
4. **Offline/background features need device acceptance.** Verify airplane-mode reading,
   queue cancellation and relaunch, Files/Keychain recovery, and system task expiration.
5. **Bundle signing.** Repositories pin a signing-key fingerprint, but bundle bytes are not
   verified.

## Next, in order

1. **Check the UI changes interactively.** Confirm manga paging and
   webtoon scrolling still work alongside the edge swipe, and check Browse on a compact phone.
2. **Exercise offline reading and queue recovery** on hardware for both novels and manga.
3. **Exercise background task scheduling/expiration**, notifications, and automatic download rules.
4. **Export and restore `.lnbk` through Files**, including a fresh-device recovery key and local imported book.

Extension WebView fetching, repository UI, and Kotlin/JS shims are on hold at the user's
request. Trackers and migration remain deferred. Cloud and `.tachibk` backup interoperability
are separate from the implemented local `.lnbk` snapshot.

## Verification

| Script | Covers |
|---|---|
| `scripts/typecheck.sh` | Whole app, `-D DEBUG` so DEBUG-only code is checked |
| `scripts/check-v2-schema.sh` | CRUD, cascades, uniqueness, history cascade, download queue |
| `scripts/check-offline-library.sh` | Backup encryption, rejection/merge rules, durable manifests, manual vs automatic update policy |
| `scripts/check-v2-foundation.sh` | Status mapping, identity, filters, dates, HTTP values |
| `scripts/check-v2-chapter-sync.sh` | Chapter parsing (40 Yokai cases), merge, delete guard |
| `scripts/check-v2-page-pipeline.sh` | Cache LRU, loader dedupe, prefetch order, progress |
| `scripts/check-v2-extensions.sh` | Bundle through the real host against a localhost fixture |
| `scripts/check-v2-scanlators.sh` | Dedup/hide rules, hidden-winner fallback |
| `scripts/check-v2-reader-settings.sh` | Per-series reader settings: resolution, persistence, reset, make default |
| `scripts/try-mangafire.sh` | Live MangaFire through the host (network required) |
| `scripts/profile-hotpaths.sh` | Library counts, progress writes, chapter rows and ordering at library scale |

Device builds come from `./scripts/build-ipa.sh` (`release` for a Release build, `--checks`
to typecheck first). It builds, packages and sanity-checks the archive:

```sh
./scripts/build-ipa.sh              # -> ../LNReader-<version>-unsigned.ipa
```

`ENABLE_DEBUG_DYLIB=NO` matters: the default Debug build is a stub launcher plus a dylib,
which is fragile once re-signed.

## Decisions worth remembering

- **`Entry.lastReadAt` is a cached column.** The library sorts by "recently read" and a
  predicate cannot walk chapters → history.
- **`Chapter.isDownloaded` is computed**, not stored, so it cannot drift from the queue.
- **Order by chapter number, never `sourceOrder`.** MangaFire lists newest-first, novel
  sources oldest-first; the index means different things per source.
- **Manga sources report the whole chapter list**, so the detail screen shows all of it.
  Novels keep the windowed preview because their sources paginate.
- **Scanlator rules live in UserDefaults**, keyed by `sourceKey::url`. A schema
  migration for a view preference is not worth it. Hiding and priority are
  **independent**: hiding applies on its own, priority only merges duplicate
  chapter numbers. The stored key for the priority toggle is still `enabled`.
- **The webtoon never uses `scrollPosition(id:)`.** It treats the binding as the position of
  record: when auto scroll, hold-to-scroll or the volume keys move the `UIScrollView` offset
  underneath it, the next re-render pushed the stale id back and the strip snapped to the top
  of the page it was leaving. The current page is read with `onScrollTargetVisibilityChange`
  and jumps are one-shot (`ScrollViewReader`).
- **Tint switches with `AppTheme.controlFill`, not the accent.** The accent is white in dark
  mode, which made every `Toggle` solid white.
- **Settings sheets are partial-height** (`.medium`/`.large` detents), not full-screen modals.
- **Tap zones are a simultaneous gesture, never an overlay.** An overlay above a scroll view
  eats the drag.
- **`JSExtensionHost` is synchronous by design.** The JS thread blocks during `http.get`, so
  bundles are straight-line code and a transpiler can emit plain calls.
- **MangaFire's "token" is upstream code, not a secret.** `VrfSigner.kt` is three
  substitution stages over the sorted query string; ported byte for byte it returns 200.
- **No relationship counts in a `body`.** `Entry.unreadCount` faults every chapter
  row. Read `LibraryChapterCounts` (a cached `fetchCount`) or count off-main.
  Measured at 37 ms per grid cell, 4.8 s for a 120-book library, per body pass.
- **No `save()` from scroll or progress callbacks.** Mutate and let
  `LibraryManager.flushProgress` land it; a save re-runs every `@Query` in the app.

## Gotchas for the next session

- **The type checker gives up before it gives an error.** `ReaderView` and `LibraryView`
  bodies are split into computed properties for that reason; a 25-modifier body fails with
  "unable to type-check in reasonable time".
- **`LNReader.xcodeproj` lists files individually.** New `.swift` files must be added to the
  target or the build silently misses them. XcodeGen is not installed here (brew cannot
  install it in this sandbox), so the project file is patched by script; verify membership
  by counting files on disk against the Sources phase.
- **Never let that patch touch non-Swift references.** An earlier version removed
  `Assets.xcassets` and the app icon, and the build still succeeded.
