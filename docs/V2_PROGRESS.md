# v2 rewrite — status

**Updated** 2026-10-22 · **Branch** `feat/v2-rewrite-manga` · **Version** 2.0.0 (build 3)
· **Latest update** Reader and Browse UI corrections, chapter directory reuse, and UI audit

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
| Extension repo UI | Not started | `ExtensionRepoService` works; nothing calls it yet |
| WebView fetch primitive | Not started | Blocks captcha-gated sources (MangaFire included) |
| Kotlin/JS transpiler | Blocked | No JDK/Kotlin/Gradle in this environment |
| Downloads | Not started | Plan §5 |
| Update scheduling | Not started | Plan §8 (`BGAppRefreshTask`, restrictions) |
| Trackers | **Deferred** | User's call |
| Migration (`.tachibk`, bridge) | **Deferred** | User's call; fresh installs start empty |
| Backup / restore (`.lnbk`) | Not started | Plan §6 |

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
| `2092e97` | Rewrote this progress tracker as a status ledger |

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

## Open issues

1. **MangaFire captcha.** A `403 {"error":"captcha_required"}` from the API surfaces as an
   error. Upstream solves it with OpenCV.js in a WebView and a `waf_pass` cookie. Needs the
   WebView fetch primitive below.
2. **Reader UI needs device verification.** Shared chapter directory and scanlator
   rules are wired; seeking, gestures, large text, and blur still need interactive checks.
3. **Global search is novel-only.** `GlobalSearchView` iterates `sourceManager.novelSources`;
   hidden on the Manga tab rather than shown broken.
4. **Downloads / scheduling absent.** No offline manga, no background refresh.
5. **Bundle signing.** Repositories pin a signing-key fingerprint, but bundle bytes are not
   verified.

## Next, in order

1. **Check the UI changes interactively.** Confirm manga paging and
   webtoon scrolling still work alongside the edge swipe, and check Browse on a compact phone.
2. **WebView fetch primitive** (`webview.fetch(url, waitForSelector)`) — unblocks captcha
   sources and gives MangaFire its solver path. Testable only on device.
3. **Repository browser** — `ExtensionRepoService.fetchIndex/install` already exist; needs a
   screen (add repo, list available extensions, install/uninstall).
4. **Kotlin/JS shims** — `HttpSource`, `ParsedHttpSource`, `SManga`, `SChapter`, `Page`,
   `Request`, `Response` + OkHttp/Jsoup in Kotlin/JS, so extensions compile unchanged. Needs
   a machine with a JDK; nothing here can build it.
5. **Downloads** — reuse `PageLoader` + `ChapterCache`, add CBZ/folder output.
6. **Update scheduling** — `BGAppRefreshTask`, per-entry restrictions, background actor.
7. **`.lnbk` backup** — the schema is stable enough now.

## Verification

| Script | Covers |
|---|---|
| `scripts/typecheck.sh` | Whole app, `-D DEBUG` so DEBUG-only code is checked |
| `scripts/check-v2-schema.sh` | CRUD, cascades, uniqueness, history cascade, download queue |
| `scripts/check-v2-foundation.sh` | Status mapping, identity, filters, dates, HTTP values |
| `scripts/check-v2-chapter-sync.sh` | Chapter parsing (40 Yokai cases), merge, delete guard |
| `scripts/check-v2-page-pipeline.sh` | Cache LRU, loader dedupe, prefetch order, progress |
| `scripts/check-v2-extensions.sh` | Bundle through the real host against a localhost fixture |
| `scripts/check-v2-scanlators.sh` | Dedup/hide rules, hidden-winner fallback |
| `scripts/try-mangafire.sh` | Live MangaFire through the host (network required) |

Device builds are produced with:

```sh
xcodebuild -project LNReader.xcodeproj -scheme LNReader -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' -disableAutomaticPackageResolution \
  ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

then `Payload/LNReader.app` zipped. `ENABLE_DEBUG_DYLIB=NO` matters: the default Debug build
is a stub launcher plus a dylib, which is fragile once re-signed.

## Decisions worth remembering

- **`Entry.lastReadAt` is a cached column.** The library sorts by "recently read" and a
  predicate cannot walk chapters → history.
- **`Chapter.isDownloaded` is computed**, not stored, so it cannot drift from the queue.
- **Order by chapter number, never `sourceOrder`.** MangaFire lists newest-first, novel
  sources oldest-first; the index means different things per source.
- **Manga sources report the whole chapter list**, so the detail screen shows all of it.
  Novels keep the windowed preview because their sources paginate.
- **Scanlator preferences live in UserDefaults**, keyed by `sourceKey::url`. A schema
  migration for a view preference is not worth it.
- **Tap zones are a simultaneous gesture, never an overlay.** An overlay above a scroll view
  eats the drag.
- **`JSExtensionHost` is synchronous by design.** The JS thread blocks during `http.get`, so
  bundles are straight-line code and a transpiler can emit plain calls.
- **MangaFire's "token" is upstream code, not a secret.** `VrfSigner.kt` is three
  substitution stages over the sorted query string; ported byte for byte it returns 200.

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
