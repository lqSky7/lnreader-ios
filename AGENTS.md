# Working on LNReader for iOS

What an agent must assume before changing code here. Each point is condensed from `docs/`;
the doc named in brackets has the reasoning. Start with `docs/V2_PROGRESS.md` for status.

## Ground rules

- **v2 is a hard break.** It opens its own store (`LNReader-v2.store`), never touches v1's
  `default.store`, and has no migration. Do not write one or a migration doc. [V2_PROGRESS]
- **On device only, sideloaded.** No server-side source execution; no App Store, so review rules
  do not apply, code signing does. [MANGA_SUPPORT_PLAN]
- **Built is not verified.** "Built" means it compiles and passes headless checks. "Verified"
  means used on an iPhone. Downloads, update scheduling, backup/restore and narration have
  never run on a device. Do not report a feature as working from a typecheck alone, and do not
  edit the docs to say it is. [V2_PROGRESS]
- **Some areas are on hold by the user's decision:** the extension repo UI, the Kotlin/JS
  transpiler, v1 migration. Do not start them. [V2_PROGRESS]
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
  reader settings are half-height sheets with one `.medium` detent; change one, change both.
  Settings sheets are partial-height, never full-screen.
- **Swipe right from the left edge goes back.** Full-screen surfaces that hide the back button
  must add `EdgeSwipeDismiss` and ignore it while a sheet is open.
- **Chapter lists select by holding.** No context menu on chapter rows; it shares the long press.
- Settings screens use `.settingsScreen(_:)`: sentence-case titles, tint applied once to the Form.
- Tint controls with `AppTheme.controlFill`, never the accent (the accent is white in dark mode).
- Text uses `Typography` tokens, which scale with Dynamic Type. Animations go through
  `AppMotion`, which returns nil under Reduce Motion.
- Reader tap zones are simultaneous gestures, never an overlay above the scroll view.
- **The webtoon never uses `scrollPosition(id:)`.** Read the page with
  `onScrollTargetVisibilityChange`; jumps are one-shot through `ScrollViewReader`.

## Sources and extensions [MANGA_SUPPORT_PLAN]

- Every source is a `CatalogSource` (`NovelSource` / `MangaSource`) in
  `Services/Sources/CatalogSource.swift`; `SourceManager` is the registry.
- `JSExtensionHost` is synchronous by design: the JS thread blocks during `http.get` and
  `webview.capture`. Do not make the bridge async.
- Page images never go through JS; the source returns a `URLRequest` and Swift downloads.
- MangaFire's "token" is upstream code ported byte for byte, not a secret.
