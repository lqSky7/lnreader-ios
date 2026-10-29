# Working on LNReader for iOS

What an agent must assume before changing code here. Each point is condensed from `docs/`;
the doc named in brackets has the reasoning. Start with `docs/V2_PROGRESS.md` for status.

## Ground rules

- **v2 is a hard break from v1.** The store is `default.store`, schema `SchemaV1`. The old v1
  data is discarded and there is no v1 migration; do not write one. [V2_PROGRESS]
- **On device only, sideloaded.** No server-side source execution; no App Store, so review rules
  do not apply, code signing does. [MANGA_SUPPORT_PLAN]
- **Built is not verified.** "Built" means it compiles and passes headless checks. "Verified"
  means used on an iPhone. Downloads, update scheduling, backup/restore and narration have
  never run on a device. Do not report a feature as working from a typecheck alone, and do not
  edit the docs to say it is. [V2_PROGRESS]
- **Some areas are on hold by the user's decision:** v1 migration. Do not start it. The JS
  bridge, extension repos and Kotlin/JS transpiler were removed; do not bring them back.
  [V2_PROGRESS]
- `docs/UI_AUDIT.md` and `docs/TTS_REVAMP_PLAN.md` are historical records. Narration is
  Breeze TTS 2, not Qwen. [V2_PROGRESS]

## Build and checks

- `./scripts/typecheck.sh` typechecks the whole app (with `-D DEBUG`). `./scripts/check.sh all`
  runs every headless check; `./scripts/check.sh` lists them. Checks compile a program from
  `tests/` against the app files they touch. There is no Simulator, XCTest or SwiftPM target.
- **New `.swift` files must be added to the target in `LNReader.xcodeproj` by hand.** The
  project lists files individually and a missing file fails silently. XcodeGen is not
  installed, so `project.yml` is not the source of truth. When patching the project, never
  touch non-Swift references: an earlier patch removed `Assets.xcassets` and the app icon and
  the build still passed. Validate with `plutil -lint LNReader.xcodeproj/project.pbxproj`.
- `xcodebuild` needs the sandbox bypassed and the foreground (SPM resolution fails inside it).
- Device builds: `./scripts/build-ipa.sh [release]`. Keep `ENABLE_DEBUG_DYLIB=NO`.
- **The type checker gives up before it gives an error.** Big bodies (`ReaderView`,
  `LibraryView`) are split into computed properties; do the same rather than adding a 25th
  modifier.

## Haptics

- **Every vibration goes through `Haptics.shared` (`Services/Haptics.swift`).** It honours the
  app-wide switch (Settings › General › Haptics), the strength setting and, for scroll cues,
  the scroll-haptics switch. Never create a `UIImpactFeedbackGenerator`, `CHHapticEngine` or
  plain `.sensoryFeedback` in a view: use `Haptics.shared.impact(_:)` / `.selection()` /
  `.notify(_:)` or a named cue, and the `.hapticFeedback(_:trigger:)` view modifier in place of
  `.sensoryFeedback`.
- A new cue gets a named method in `Haptics.swift`. *When* to fire is decided at the call site
  (`ScrollHaptics.swift`, `MangaReaderControls.swift`); `Haptics.swift` only decides how it feels.

## Performance rules [PERFORMANCE, LIBRARY_QUERY_PLAN]

- **Never do expensive work on the main thread if it can hurt the UX.** Walking relationships
  across a library, encoding or decoding large payloads, base64, file I/O and big saves go to a
  background `ModelContext` (pass `PersistentIdentifier`s and `container`, not models) or a
  detached task. Show progress (a spinner) while it runs and hop back only to publish results.
  Sync-now froze the app by building its whole upload on the main actor.
- **Never read a relationship count in a `body`.** Use `LibraryChapterCounts` or a background
  `fetchCount`. `Entry.unreadCount` is only fine in a background pass.
- **Never `save()` from a scroll or progress callback.** Mutate the model and let
  `LibraryManager.flushProgress` write it. Every save re-runs every `@Query` in the app,
  including screens hidden under the reader.
- Nothing render-blocking in the reader's `<head>`; chapters paint from local bytes.
- Cache decoded images, not compressed data, and always with a cost.
- Derived lists (chapter ordering, navigable chapters) are state rebuilt on change, not
  computed properties read several times per body.
- The library rewrite (snapshots, a single writer, typed change events) is proposed, not
  started. Do not add a "pause while the reader is open" switch; it was rejected.

## Data model

- `Entry.lastReadAt` is a cached column (predicates cannot walk chapters → history).
  `Entry.lastReadAt` and `History.lastRead` refresh at most once a minute.
- `Chapter.isDownloaded` is computed, never stored.
- **Order chapters by number, never `sourceOrder`.** Sources disagree on what the index means.
- Manga sources return the whole chapter list; novels keep the windowed preview.
- Scanlator rules live in UserDefaults keyed `sourceKey::url`. Hiding and priority are
  independent.
- Per-series manga settings are optional overrides (`MangaReaderOverrides`) stored under
  `mangareader.<sourceKey>::<url>`, so a new setting never breaks saved data.
- Opening an entry does not refetch. Only a browse result or an entry with no `lastUpdate`
  fetches on its own.

## UI invariants [V2_PROGRESS]

- **Behave consistently.** The same kind of surface acts the same everywhere. Novel and manga
  reader settings are sheets with `.medium` and `.large` detents, opening at `.large`;
  change one, change both. Other settings sheets stay partial-height.
- **Swipe right from the left edge goes back.** Full-screen surfaces that hide the back button
  must add `EdgeSwipeDismiss` and ignore it while a sheet is open.
- **On the detail screen a control lives with what it acts on.** Hero: one primary button.
  `EntryActionBar`: up to four stateful entry tiles. Toolbar: a visible Refresh button (no pull
  to refresh; pulling down goes back), then a `…` menu for occasional actions such as migrate.
  Chapter header: search and one sort/filter menu. [DETAIL_SCREEN]
- **Chapter lists select by holding.** No context menu on chapter rows; it shares the long press.
- Settings screens use `.settingsScreen(_:)` for their sentence-case title.
- **Grey means secondary, never tappable.** The `AccentColor` asset is primary, so buttons and
  links read as primary text; only metadata is `.secondary`. Switches get the `controlFill`
  track from `AppToggleStyle` at the root; never add a root `.tint` (it beats button roles, so
  destructive swipes turn white) or tint toggles one by one. Use `AppTheme` tokens
  (`hairline`, `surface`, `warning`), `.primaryActionStyle()` for a filled call to action, and
  `foregroundStyle`, never `foregroundColor` or `Color.gray.opacity(…)`.
- Text uses `Typography` tokens, which scale with Dynamic Type. Animations go through
  `AppMotion`, which returns nil under Reduce Motion.
- Reader tap zones are simultaneous gestures, never an overlay above the scroll view.
- **The webtoon never uses `scrollPosition(id:)`.** Read the page with
  `onScrollTargetVisibilityChange`; jumps are one-shot through `ScrollViewReader`.

## Sources and extensions [MANGA_SUPPORT_PLAN]

- Every source is a `CatalogSource` (`NovelSource` / `MangaSource`) in
  `Services/Sources/CatalogSource.swift`; `SourceManager` is the registry.
- Sources are native Swift in `Services/Sources/Native/`, keyed `builtin:<id>`. A new one is a
  file there, an entry in `NativeSources.all()`, and (manga) its Mihon id in `NativeSourceIDs`.
  `scripts/try-native.sh` runs it against the live site.
- Entry and chapter urls are persisted, so a source keeps returning the shape it always did.
- The source returns a `URLRequest` for each page image and Swift downloads it.
- MangaFire's "token" is upstream code ported byte for byte, not a secret.
- **A multisrc family is one class, not one class per site.** `MasonrySource` (keiyoushi's
  `lib-multisrc/masonry`) is configured per site: `MasonrySource(id:name:baseURL:)` in
  `NativeSources.all()`, one line each. Do not copy the file per domain.
