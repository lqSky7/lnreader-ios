# v2 rewrite — status

**Updated** 2026-10-23 · **Branch** `main` · **Version** 2.0.0 (build 3)
· **Latest update** Library R8–R10 (sorts, per-category display and update scope, badges), manual chapter fetching

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
| Trackers | **AniList implemented; device check pending** | Implicit-flow login (Keychain token, redirect `lnreader://anilist-auth`), search/bind/edit sheet on the detail screen, auto-update on chapter finish (3 s debounce, highest chapter read), offline queue flushed on foreground and network change. Other trackers not started |
| Migration (`.tachibk`, bridge) | **Deferred** | User's call; fresh installs start empty |
| Backup / restore (`.lnbk`) | **Local v2 format implemented; device check pending** | Authenticated encrypted snapshots, recovery key, merge restore; protobuf/cloud interoperability remains deferred |
| Library (R7–R10) | **Implemented; device check pending** | Filters, per-category sort / display / update scope, badges. No category editor yet (see Open issues) |
| Chapter fetching | **Implemented; device check pending** | Opening an entry no longer refetches; last-fetched time and a Refresh button |
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
| R7 | Library filters | **Implemented; device check pending** | — |
| R8 | Library sorts (per category) | **Implemented; device check pending** | R7 |
| R9 | Categories: per-category sort, display, update scope | **Implemented; device check pending** | R7, R8 |
| R10 | Library badges | **Implemented; device check pending** | — |
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
  The sheet has a single `.medium` detent: with `.large` as well, scrolling its list pulled
  the sheet to full height.
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
- **R7 as built.** `LibraryFilter` (`Models/Enums/LibraryFilter.swift`): downloaded, unread,
  started, completed, tracked, each a `TriState`. `LibraryFilterStore` keeps one filter per
  category (keyed by name; `nil` is All) as one JSON value under `library.filters`.
  `LibraryChapterCounts.Counts` gained `downloaded`; the view loads counts for the filter into
  `filterCounts` off-main (only when a count-based rule is on) and entries whose counts have not
  arrived yet pass, so the library never blanks. UI: toolbar button → `LibraryFilterSheet`.
  Checked headless by `scripts/check-library-filters.sh`; typechecks. Source/kind filtering
  is still the existing All/Novels/Manga picker. Device check: filter counts match the cells,
  and a filter set on one category does not leak into another.
- **R8 sorts.** Sort orders exist today (`SortOrder`); add per-category sort + direction,
  and "latest chapter", "last checked", "chapter fetch date". Sorting by unread must use the
  cached counts, never `Entry.unreadCount`.
- **R8 as built.** `LibrarySort` / `LibrarySorter` / `LibrarySortStore`
  (`Models/Enums/LibrarySort.swift`): one sort per category as one JSON value under
  `library.sorts`; a category with no entry follows the global default from Settings. The
  Sort menu is scoped to the selected category and offers "Use default sort" once it has
  an override. Ascending now means smallest first everywhere (A to Z, oldest first); an
  order starts in its natural direction, so a saved Alphabetical + Descending now reads
  Z to A (it used to read A to Z). New orders: **Latest Chapter** (newest `dateUpload`)
  and **Chapter Fetch Date** (newest `dateFetch`; it is the "unseen update" stamp, so it
  empties when Updates are cleared). "Last Updated" is shown as **Last Checked**: it is
  `Entry.lastUpdate`, set on every successful refresh. The two date orders add two
  `fetchLimit 1` queries per entry to the cached count pass, only while one is selected.
  Checked headless by `scripts/check-library-sorts.sh`; typechecks. Device check: each
  category keeps its own sort, and unread/latest-chapter sorts wait for the count pass.
  `LibraryView.hasLoadedCounts` holds the page back until the first pass lands: sorting with
  every count at 0 and then re-sorting visibly reshuffled the library on launch.
  **Sort menu rework.** One "View options" menu (Sort, Display, Import) beside the Filter
  button replaces four toolbar buttons. Sort is an inline picker for the order (a plain
  checkmark, no leading chevron to indent the rows), then a Direction picker worded per order
  ("Fewest first / Most first", "A to Z", "Oldest first / Newest first"), then an
  **Empty ones last** toggle (`LibrarySort.emptyLast`, stored per category, decoded as off for
  older saves). Selecting a count-based order turns it on, so ascending Unread no longer opens
  with every finished title. Empty means 0 unread, 0 chapters, or no date for that order.
- **R9 categories.** Per-category display mode, sort, filter and update scope. The category
  chip row already exists; this adds the per-category state behind it.
- **R9 as built.** Sort (R8) and filter (R7) were already per category; R9 adds the other two.
  *Display mode* is a `LibraryDisplayStore` (`Models/Enums/CategorySettings.swift`), one JSON
  value under `library.displays`; the toolbar Display menu now edits the selected category,
  falls back to the Settings default, and offers "Use default display" (it used to overwrite
  that Settings default). *Update scope* is the `CategoryFlags.excludedFromUpdates` bit of
  `Category.flags` (already carried by `.lnbk`): long-press a chip (a popover with a gap from the chip) → "Include in library
  updates"; excluded chips show a pause glyph. `LibraryUpdateScope` decides who updates:
  automatic, background and library-wide runs skip a title if **any** of its categories is
  excluded (exclusion wins, as in Mihon); `updateLibrary(category:)` updates exactly that
  category's titles and ignores its exclusion. Pull-to-refresh inside a category, and the
  chip menu's "Update this category", use it. Checked headless by
  `scripts/check-library-categories.sh`; typechecks. **Gap:** there is still no UI to
  create, rename, reorder, delete or assign categories (they only arrive from a Mihon
  restore), so this is only reachable after an import until a category editor exists.
  Device check: a category's display mode stays with it, an excluded category is skipped
  by Updates and the background refresh, and a category refresh updates only its titles.
- **R10 badges.** Unread, downloaded, source/language, "new". Compute off-main and cache;
  badges are the main per-cell cost in the grid.

- **R10 as built.** Four toggles under Settings → General → Library badges:
  unread (the old toggle, same key, on by default), new chapters, downloaded count and
  source language; the last three are off by default so the grid looks as it did.
  `LibraryBadges.resolve` (`Models/Enums/LibraryBadges.swift`) decides what a cell shows
  from the cached counts, and `LanguageLabel` turns a source's tag ("pt-BR") or name
  ("English") into "EN" / "PT-BR" / "MULTI" / "LOCAL". "New" is unread chapters whose
  `dateFetch` is still set, so it clears with Updates, and is never more than unread.
  Counts stay off-main: `LibraryChapterCounts.counts(for:container:extras:)` takes `.newCount`
  or `.dates`, each costing extra queries only when asked, and remembers every extra any
  caller wanted so the sort pass and the cells do not evict each other (they stay on for
  the session once requested). Grid cells draw `LibraryCoverBadges` as an overlay on the
  cover (state top right, facts top left); list rows add symbols to the caption line.
  Checked headless by `scripts/check-library-badges.sh`; typechecks. Device check: badges
  do not move cell heights, toggling a badge updates cells without a relaunch, and the grid
  scrolls as smoothly as before with all four on.

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

## Chapter fetching is manual

Opening an entry no longer refetches it. `NovelDetailView.fetchDetails` fetches on its own only
when there is nothing stored to show: a browse result, or a library entry with no `lastUpdate`.
A stored entry shows "Last fetched …" (from `Entry.lastUpdate`, or this screen's own fetch time
for a browse result) with a **Refresh** button; a failed refresh raises an alert and leaves the
page up. `addToLibrary` stamps `lastUpdate` when chapters came with the add, so a title just added
from Browse does not refetch on first open. Library-wide updates (pull to refresh, background)
are unchanged. Device check: opening a library entry makes no network request, Refresh updates
the time and the chapter list, and a title added from Browse before its fetch finishes still
gets its chapters.

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
| `d42d6b0` | R8: per-category library sorts; Latest Chapter and Chapter Fetch Date orders |
| `b59fe75` | R9: per-category display mode; exclude categories from updates; refresh one category |
| `e656c82` | R10: library badges (new chapters, downloaded count, source language) |
| `fd0ccac` | Chapters are no longer refetched on open; last fetched time and manual Refresh |
| `e02deda` | Fix: category chip actions open from a long press gesture |
| `b4ee552` | Fix: anchor the category actions to the pressed chip |

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

0. **Check the library features on a device** (R7–R10 and manual fetching): each category keeps its
   own sort and display mode; an excluded category is skipped by Updates and the background refresh;
   a chip's long-press popover opens beside that chip and its category refresh updates only its
   titles; badges do not change cell heights; opening a library entry makes no request and Refresh
   works. Each feature's "device check" note above has the detail.

1. **Check the UI changes interactively.** Confirm manga paging and
   webtoon scrolling still work alongside the edge swipe, and check Browse on a compact phone.
2. **Exercise offline reading and queue recovery** on hardware for both novels and manga.
3. **Exercise background task scheduling/expiration**, notifications, and automatic download rules.
4. **Export and restore `.lnbk` through Files**, including a fresh-device recovery key and local imported book.

Extension WebView fetching, repository UI, and Kotlin/JS shims are on hold at the user's
request. Migration remains deferred; AniList tracking is in (see the Trackers row). Cloud and `.tachibk` backup interoperability
are separate from the implemented local `.lnbk` snapshot.

## Library follow-ups

- **No category editor.** Categories only arrive from a Mihon restore: nothing in the app creates,
  renames, reorders, deletes or assigns them, so R9's per-category settings are only reachable after
  an import. A category editor (plus assigning from the detail screen) is the missing piece.
- **Planned next:** R11 duplicate detection, R12 migrate source, R13 incognito, R14 download UI.

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
| `scripts/check-library-sorts.sh` | Every sort order and direction, nil dates, tie-breaks, per-category store |
| `scripts/check-library-categories.sh` | Per-category display store, exclude-from-updates flag, update scope |
| `scripts/check-library-badges.sh` | Badge settings, count clamping, new-vs-unread, language labels |
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

- **Invariant: behave consistently.** The same kind of surface must act the same way across
  the app. Reader settings (novel and manga) are a half-height sheet with a single `.medium`
  detent; scrolling never grows it. Change one, change the other.
- **Swipe right from the left edge goes back.** Pushed screens get the system gesture; the
  full-screen readers (manga and novel) use `EdgeSwipeDismiss` (screen-edge recognizer, so it
  never competes with scrolling or paging) and ignore it while a sheet is open. The manga
  reader also keeps its leftward swipe from the right edge. New full-screen surfaces that hide
  the back button must add it.
- **Chapter lists select by holding.** Hold a row to start selecting; tap rows to toggle, hold
  another row to take everything between it and the last pick. `ChapterSelection` (in
  `ChapterRow.swift`) is owned by the screen (`NovelDetailView`, `ChapterDirectoryView`) so
  `ChapterSelectionBar` pins to the screen: Read, Unread, Download, and a More menu (select all
  below, select all, invert, mark previous as read, bookmark, delete download, chapter audio).
  Rows have no context menu any more, since it shared the long press; its two actions moved
  into the bar. Only library entries select: a browse result has no stored chapters to change.
  The reader's chapter picker (`onSelect`) does not select. Device check pending.
- **Settings screens use `.settingsScreen(_:)`** (`Design/Theme.swift`): large sentence-case
  title plus the `AppTheme.controlFill` tint, applied once to the Form. Do not tint toggles
  one by one, and do not title-case labels ("Reader settings", "Sort order").
- **Now-playing cover survives `stop()`.** `attachCover` runs before `playAvailable`, which
  stops the player first; `stop(clearingArtwork: false)` keeps the artwork. The cover fetch
  uses the same browser User-Agent as `CustomAsyncImage` and reads `ImageCache` first.

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
