# Manga Support — Architecture & Implementation Plan (v2)

Reference implementation: `yokai/` (Tachiyomi/Mihon fork, Kotlin/Android).

The goal is to make manga a first-class content type next to novels. That means porting Yokai's extensions, downloads, tracker sync and backup/restore, and adding end-to-end encryption to backups, which Yokai does not have.

**Ground rules:**
- **v2 is a hard, breaking release.** There is no in-place data migration and no compatibility layer. Users move their data with a backup converter; see §1 and `docs/MIGRATION_TO_V2.md`.
- **Everything runs on device.** There is no server-side source execution and no Suwayomi mode.
- **Distribution is sideloaded or self-built.** Nothing goes to the App Store, so App Store review rules don't constrain us. iOS code signing still applies; see §3.4.
- **AniList is the only required tracker.** Every other tracker is good-to-have.

---

## 0. Today vs. target

| Area | LNReader iOS today | Yokai | v2 target |
|---|---|---|---|
| Content model | SwiftData `Novel`/`Chapter`, denormalized `ReadingHistory`, no schema versioning | SQLDelight `mangas`/`chapters`/`manga_sync`/`history` | Fresh kind-aware schema, versioned from day one |
| Sources | LNReader JS plugins in JavaScriptCore | Kotlin extensions in APKs | Native Swift host; site logic = LN JS plugins + transpiled Kotlin extensions (§3) |
| Network | `URLSession` fetch polyfill, fixed UA, no cookies or Cloudflare | Interceptors: UA, Cloudflare, rate limit, DoH | Native `HTTPClient` with interceptors |
| Reader | WKWebView HTML | Pager + webtoon, tiled decoding | Native image reader for manga; the HTML reader stays for novels |
| Downloads | None for chapters | Queue, folders/CBZ, ComicInfo | One unified manager for both kinds |
| Trackers | None | 9 services | AniList (required); others optional |
| Backup | **No local backup.** Plaintext JSON account sync to the custom backend (`SyncManager`, `PUT/GET /api/sync`) | Gzipped protobuf `.tachibk` | `.tachibk`-compatible backup with E2E-encrypted cloud copy (§6) |

---

## 1. Hard migration (breaking change)

### 1.1 Why no in-place migration
- The current schema has no `VersionedSchema`. Its names are novel-specific, and `ReadingHistory` is denormalized and hash-keyed.
- Migrating it in place would mean shipping and keeping the frozen v1 `@Model` types forever.
- A backup round-trip gives us a clean schema with no legacy model code in v2.

### 1.2 Mechanics
1. **v2 uses a new store file.** It opens `ModelConfiguration("LNReader-v2", …)` and never opens the v1 `default.store`.
2. **v2 never deletes the v1 store automatically.** Users who upgraded without exporting can still recover: install the bridge build over v2 (same bundle id, so the data container persists), export, then reinstall v2.
3. **v2 shows a notice once on first launch** when `default.store` exists:
   - The notice explains the breaking change.
   - It links to the migration doc and offers "Import backup".
   - After a successful import, or on user confirmation, it offers "Delete old data".
   - That check is the *only* v1 awareness in the v2 codebase. It is about 30 lines, in `Features/Onboarding/LegacyDataNotice.swift`.
4. **The plaintext cloud sync is removed.** `PUT/GET /api/sync` stops being used and the backend drops it (§6.3). Accounts carry over. Cloud data does not carry over unless it is converted (§1.3, path B).

### 1.3 The backup converter

The converter is a small SwiftPM package, `Packages/LegacyBackupConverter`. Its only dependency is the shared `LNBackupSchema` package (the SwiftProtobuf `.proto` types from §6.1). It has two front-ends:

| Path | Who | Input | Output | Coverage |
|---|---|---|---|---|
| **A. Bridge build** (recommended) | Anyone still on v1 | Live v1 SwiftData store + UserDefaults | `lnreader_v1-export_<date>.tachibk` via share sheet | Full (below) |
| **B. CLI** `lnr-convert` | Users who only have cloud data, or who already wiped v1 | JSON from `GET /api/sync` (`SyncPayload`) | `.tachibk` | Partial: library, chapters and sources only |

- **Path A** is a final v1.x build (the last commit on the old architecture, tagged `v1-final`) with one added screen, More → "Export for v2". It reads the v1 models directly, so all legacy-reading code lives in the *old* tree and v2 contains none of it.
- **Path B** is for desktop use: `lnr-convert --email <addr> -o backup.tachibk`. v1 sync authenticates with session cookies (better-auth style `/api/auth/*` endpoints), so the CLI signs in itself, then calls `GET /api/sync` and converts the result. `lnr-convert sync.json` converts a JSON file the user already saved. The CLI and bridge share the same mapping code.

**v1 → v2 field mapping** (novels go into the LN extension fields of the backup, §6.1):

| v1 | v2 backup | Notes |
|---|---|---|
| `Novel` `path`, `pluginId`, `name`, `cover`, `summary`, `author`, `artist`, `status`, `genres` (comma string), `inLibrary`, `dateAdded`, `libraryPosition` | `BackupNovel` url, sourceKey, title, thumbnailUrl, description, author, artist, status, genre[] (split), favorite, dateAdded, libraryOrder | — |
| `Chapter` `path`, `name`, `releaseTime`, `bookmark`, `unread`, `chapterNumber`, `position`, `progress`, `lastReadParagraphIndex`, `readTime` | `BackupChapter` url, name, dateUpload, bookmark, read = !unread, chapterNumber, sourceOrder, + LN fields progress / paragraphIndex | — |
| `Category` `name`, `sort` + memberships | `BackupCategory` name, order + per-entry category indices | Not covered by path B |
| `ReadingHistory` | `BackupHistory` url = chapterPath, lastRead = lastReadAt | Deduped per chapter. Not covered by path B |
| Installed plugins (UserDefaults metadata) / `SyncSourcePayload` | LN source list (id, url, version) | v2 reinstalls them on restore |
| `general.*`, `reader.*`, `tts.*` `@AppStorage` keys | `BackupPreference` with the same key strings | Only keys v2 still recognizes are applied. Not covered by path B |

**Not carried over** (listed in the migration doc):
- Downloaded TTS audio (`ApplicationSupport/LNReaderAudio`)
- Imported local EPUB/PDF files (users re-import them)
- `UserProfile` avatar
- NovelFire login cookies and the comments cache
- `isDownloaded` state

---

## 2. v2 data model (SwiftData, versioned from day one)

The schema is written fresh as `Models/Schema/SchemaV1.swift` (v2's own V1) with a `SchemaMigrationPlan`, so future changes migrate properly.

| Model | Key fields | Notes |
|---|---|---|
| `Entry` | `kind: ContentKind` (.novel/.manga), `sourceKey: String`, `url`, `title`, `author`, `artist`, `summary`, `genres: [String]`, `status: EntryStatus` (Yokai's 0–6), `thumbnailURL`, `inLibrary`, `dateAdded`, `lastUpdate`, `libraryOrder`, `viewerFlags: Int` (manga, Yokai bit layout), `updateStrategy`, `memo: String = "{}"`, custom overrides | Unique on (`sourceKey`, `url`). `sourceKey` is `"ln:<pluginId>"` or `"mihon:<Int64>"` |
| `Chapter` | `url`, `name`, `scanlator`, `chapterNumber: Double`, `sourceOrder`, `dateUpload`, `dateFetch`, `read`, `bookmark`, `progress` (0–100, kind-agnostic), `lastPageRead`, `pagesLeft` (manga), `paragraphIndex` (novel), `memo` | Relationship to `Entry`, cascade delete |
| `History` | → `Chapter` (unique), `lastRead`, `timeRead` | The Yokai model replaces the denormalized `ReadingHistory`. The History view queries through relationships |
| `Category` / membership | `name` (unique), `order`, `flags` | Shared across both kinds |
| `Track` | → `Entry`, `syncId`, `remoteId: Int64`, `libraryId`, `title`, `lastChapterRead: Double`, `totalChapters`, `status`, `score`, `remoteURL`, `startDate`, `finishDate` | Unique on (entry, syncId) |
| `ExtensionRepo` | `baseURL` (unique), `name`, `shortName`, `website`, `signingKeyFingerprint` | Replaces `Repository` and the hardcoded `registryURL`. Used for both LN plugin and manga repos (`kind`) |
| `DownloadItem` | → `Chapter`, `order`, `state`, `error` | Persisted queue |
| `PendingTrackUpdate` | `entry`, `syncId`, `chapterNumber` | Offline tracker queue |

**Design notes:**
- Chapter merges during library updates go through a background `@ModelActor` with batched saves, because manga can have thousands of chapters.
- Indexes: (entry, read) and (entry, sourceOrder).

---

## 3. Sources and extensions

### 3.1 Protocols (native Swift)

```swift
protocol CatalogSource: Identifiable, Sendable {
    var key: String { get }               // "ln:<id>" | "mihon:<id>"
    var kind: ContentKind { get }
    var name: String { get }; var lang: String { get }; var supportsLatest: Bool { get }
    func filters() async throws -> [SourceFilter]
    func popular(page: Int) async throws -> EntriesPage
    func latest(page: Int) async throws -> EntriesPage
    func search(query: String, page: Int, filters: [SourceFilter]) async throws -> EntriesPage
    func details(_ e: SourceEntry) async throws -> SourceEntry
    func chapters(_ e: SourceEntry) async throws -> [SourceChapter]
}
protocol NovelSource: CatalogSource { func chapterHTML(_ c: SourceChapter) async throws -> String }
protocol MangaSource: CatalogSource {
    func pages(_ c: SourceChapter) async throws -> [SourcePage]
    func imageURL(_ p: SourcePage) async throws -> String
    func imageRequest(_ p: SourcePage) async throws -> URLRequest
}
```

- **Implementations:** `LNPluginSource` (the existing JSC runtime), `MihonSource` (transpiled extensions, §3.3) and, optionally, `BuiltinSource` (hand-written Swift, §3.5).
- **`SourceFilter`** mirrors Yokai's `Filter`: Header, Separator, Select, Text, CheckBox, TriState, Group, Sort.
- **`SourceManager`** replaces `PluginManager`. It handles repos, installs, updates, trust (fingerprint check as in `TrustExtension.kt`) and per-kind lists.

### 3.2 Network (`Services/Network/HTTPClient`)
- **Interceptors:**
  - UserAgent.
  - Cookie: one store, kept in sync with `WKWebsiteDataStore`.
  - Cloudflare: solve the challenge in a `WKWebView`, harvest `cf_clearance`, retry.
  - RateLimit: per source and per host.
- **WebView screen:** an "Open in WebView" screen for each source.
- **Shared:** LN plugins and Mihon sources both go through this client.

### 3.3 Mihon extensions: transpile Kotlin to JS, run in JavaScriptCore

The Kotlin source of keiyoushi/extensions-source (Apache-2.0) is compiled with **Kotlin/JS** against `lnreader-source-compat`. That is a Kotlin/JS library that re-implements, under the same fully-qualified names, the APIs extensions import:

- `okhttp3.*` maps to a synchronous bridge into `HTTPClient`.
- `org.jsoup.*` maps to SwiftSoup. Coarse-grained calls are exposed (`select(css) → [handles]`, `attrs/texts` in bulk) to minimize JS↔Swift crossings.
- `SharedPreferences`/`PreferenceScreen` maps to a key-value store plus a JSON schema that SwiftUI renders.
- `rx.Observable` gets a minimal shim.
- `java.text.SimpleDateFormat`/`Calendar` gets a date shim.
- `Injekt` gets stubs.
- `eu.kanade.tachiyomi.source.*` is **upstream's** source API (the keiyoushi extensions-lib version), compiled for JS. It is not Yokai's copy, which has fallen behind; see §3.6.
- `keiyoushi.network.*` / `keiyoushi.utils.*` are upstream's own helper libraries. They live as source in the same repo and compile along with the extensions.

**Build and distribution:**
- CI emits one `.js` bundle per extension and a repo in the Yokai/keiyoushi `index.min.json` shape, with `apk` pointing at the bundle, plus `repo.json` carrying the signing fingerprint.
- Source IDs are computed by the original Kotlin code: `md5("name/lang/versionId")`, first 8 bytes as a big-endian Long, `& Long.MAX_VALUE`. They are therefore identical to Mihon/Yokai, so their `.tachibk` backups resolve to our sources.

**Execution model:**
- **Swift owns all I/O, images and concurrency.** Images are fetched, cached, decoded and downloaded in Swift. JS only builds requests and parses responses.
- **One `JSVirtualMachine` and `JSContext` per source, each on its own thread.** Sources therefore run truly in parallel. Within a source, calls are serialized, which is what Yokai does too (`execute()` on JVM threads) and what per-source rate limits want anyway.
- If a heavy source needs it, a small pool of contexts per source is possible.

**Hard cases:**
- **Scramble interceptors** (`android.graphics.Bitmap`/`Canvas`): a CoreGraphics-backed facade subset.
- **WebView-dependent sources:** hidden `WKWebView` evaluator, or marked unsupported.
- **Reflection, `java.io`, Android `Context`:** these fail to compile, and CI marks the source unsupported.
- **`java.*` package declarations:** Kotlin may forbid declaring them in the facade. If so, a CI source-rewrite step changes `import java.text.` to `import compat.java.text.`.

### 3.4 Why not port the extensions to native Swift instead?

**Decision: keep the transpiled JS path for site logic. Everything else is native Swift.**

The objection was "we win nothing from JS, and everything becomes blocking and sequential". Neither part holds up:

1. **Blocking and sequential is not the effect.**
   - Only parsing runs in JS. Page images (the bulk of the bytes and time) never touch JS: the extension returns a `URLRequest` and Swift downloads 2+ pages concurrently.
   - Contexts are per source and per thread, so library updates and downloads across sources run in parallel, the same as Yokai's semaphore of 5.
   - Per-source serialization is what the rate limiters enforce anyway.
2. **We get upstream maintenance.** Upstream has 1,444 extensions and 548 commits in the last 30 days; the numbers and examples are in §3.6. Transpiling means a CI rebuild picks up those fixes. Hand-ported Swift means we own every site breakage forever, for every source we port, which is most of the long-term cost of a manga reader.
   - This argument only holds for **broad coverage**. For a curated set of roughly 10–20 sources, hand-written Swift (§3.5) is reasonable and is the simpler choice. This scope decision is open; see §10.
3. **Swift sources can't be distributed as extensions, even sideloaded.** Not being on the App Store doesn't lift iOS code signing: there is no `dlopen` of downloaded unsigned code and no JIT. Native Swift sources would have to be compiled into the IPA, so every site fix would mean a rebuild and re-sideload. JS bundles update in-app from the repo, as LN plugins already do.
4. **Backup interop for free.** Because the Kotlin code computes the IDs and URL formats, `.tachibk` imports from Mihon and Yokai match without per-source mapping.

**What's true about the concern:**
- Third-party JavaScriptCore runs without JIT (interpreter only), and every Jsoup call crosses the bridge.
- Selector-heavy sources will parse more slowly than native code would.
- The Phase 1 spike benchmarks this: chapter-list parse time on Madara and MangaDex, with a budget of under 300 ms for a typical list.
- Mitigation is the coarse-grained bulk Jsoup bridge. For any source that still misses the budget, use §3.5.

### 3.5 Escape hatch: built-in native sources

`BuiltinSource: MangaSource` implementations, written in Swift and compiled into the app, cover two cases:
- Very popular sources where performance matters and the site has a clean JSON API (MangaDex, Comick).
- The Phase 1 no-go fallback. If transpiling proves unworkable, v2 ships a curated set of built-in sources plus the multisrc themes (Madara, MangaThemesia) as native generic implementations configured with JSON site lists.

### 3.6 Extension pipeline: facts and implementation details

Reference material for whoever implements Phase 1. The facts below come from a snapshot of `https://github.com/keiyoushi/extensions-source`, commit `ff521c17bb3e`, dated 2026-10-20. **Re-measure before relying on the numbers.**

#### Upstream at a glance

| Metric | Value | How it was measured |
|---|---|---|
| Extension modules | **1,444** | Directories at `src/<lang>/<name>/` |
| Largest languages | en 418, ja 140, all 132, pt 116, es 110, id 85 | Per-language directory counts |
| Shared site templates | **66** | Directories under `lib-multisrc/` (Madara, MangaThemesia, Keyoapp, …) |
| Commits, last 30 days | **548** | `git log --since='30 days ago'` |
| Commits, last 365 days | **3,723** | Roughly 10 merged changes per day |
| Extension or template folders touched, last 30 days | **953** | Distinct `src/<lang>/<name>` or `lib-multisrc/<theme>` paths in commits. Inflated by bulk commits (e.g. "update domains") |
| Most-churned templates, last 30 days | pam 27, vinetheme 12, clipstudioreader 12, initmanga 11, madaralegacy 10, keyoapp 9 | Commits touching `lib-multisrc/<theme>` |

Repo layout:
- **Site modules:** `src/<lang>/<name>/build.gradle` plus Kotlin sources.
- **Template subclasses:** a site built on a template is often a ~20-line subclass that sets `baseUrl` and overrides a few selectors. Its `build.gradle` declares `themePkg`.
- **Shared code:** `lib-multisrc/<theme>/` holds the templates; `keiyoushi.*` holds helper libraries.
- **Module metadata:** each `build.gradle` declares `extName`, `extClass`, `extVersionCode`, and optionally `themePkg`, `isNsfw` and `baseUrl`.

#### What the churn looks like

These are real commit subjects from two weeks before the snapshot. They are the categories of breakage our pipeline must absorb:

| Kind of breakage | Examples | What the compatibility library needs |
|---|---|---|
| Site redesign, selectors stop matching | "Tr Manga: update selectors for site redesign", "AnimeSama: fix catalogue and details after site redesign", "Toonkotsu: match the site's chapter list, details and search" | Nothing new; pure Kotlin + Jsoup |
| Site moved to a new platform | "SunsetManga: rewrite for new platform", "Milftoon: rewrite for Vue SPA redesign" | Usually nothing new |
| Domain changes | "update domains" | Nothing new |
| Anti-bot, rate limits, sessions | "Comic Asura: fix 429 error", "HDoujin: route all API calls through clearanceRequest", "MangaHub.fr: fix empty images by starting chapters from a fresh session" | Correct OkHttp interceptor and cookie semantics |
| Image protection | "Manga TV: decrypt ReaderBlob AES-GCM for chapter images", "Pam: read reader v2 pages in an off-screen WebView" | Crypto stand-ins (`javax.crypto`); off-screen WebView bridge, or mark unsupported |
| New sources | "Add Manga Rw", "Add Nora Scans", "Add Lovesjane Scans" | Nothing new if built on an existing template |

Most fixes are pure parsing logic, which the transpiler picks up for free. The rest need a stand-in API added once, which then serves every extension that uses it.

#### How "transpiling" works (and what it is not)

- **It is an ordinary compiler.** Kotlin/JS is an official JetBrains compiler backend. The same Kotlin source that Android compiles to JVM bytecode can be compiled to JavaScript by a standard Gradle build: deterministic, and not an AI or regex rewrite.
- **There is no Kotlin-to-Swift.** Kotlin/Native can produce an iOS framework that Swift calls, but that is compiled native code. It would have to be built into the IPA and could not be downloaded as an extension.
- **The compiler handles the language, not the libraries.** Extensions call JVM-only libraries such as OkHttp, Jsoup, `android.*` and `java.text`. Compilation fails wherever such a class is referenced, unless a class with the same name and signature exists for the JS target.
- **`lnreader-source-compat` provides those classes.** We write it by hand: same package names, same signatures, implemented in Kotlin/JS and calling into Swift. Extension code stays untouched. For example:

```kotlin
// lnreader-source-compat — written by us, compiled for JS
package okhttp3

class Request(val url: HttpUrl, val method: String, val headers: Headers, val body: RequestBody?)

class Call(private val request: Request) {
    fun execute(): Response = nativeHttp(request)   // synchronous call into Swift's HTTPClient
}

@JsName("__lnr_http") external fun nativeHttp(req: Request): Response  // implemented in Swift via JSContext
```

```kotlin
package org.jsoup.nodes

class Element internal constructor(private val handle: Int) {   // handle to a SwiftSoup node
    fun select(css: String): Elements = Elements(nativeSelect(handle, css))
    fun text(): String = nativeText(handle)
    fun attr(name: String): String = nativeAttr(handle, name)
    // …and the rest of the Jsoup surface extensions actually use
}
```

#### Worked example: the Madara template

`lib-multisrc/madara/src/eu/kanade/tachiyomi/multisrc/madara/Madara.kt` is 157 lines long. Its complete import list:

| Import | Status on Kotlin/JS |
|---|---|
| `eu.kanade.tachiyomi.source.model.{Filter, FilterList, MangasPage, SManga}` | Portable Kotlin; compiles as-is |
| `kotlinx.serialization.json.JsonElement` | Multiplatform; supported |
| `keiyoushi.network.{get, post}`, `keiyoushi.utils.{asJsoup, firstInstanceOrNull}` | Upstream helpers compiled from source. Their transitive OkHttp/Jsoup calls need stand-ins |
| `okhttp3.FormBody` | Needs a stand-in |

It overrides `getFilterList(data: JsonElement?)`. That signature is **not** in Yokai's `Source` interface (`yokai/source/api/...`), which confirms upstream's source API has moved past Yokai's copy. **Compile against upstream's extensions-lib, not `yokai/source/api`.**

#### Compatibility library scope (Phase 1 backlog)

| Area | Contents | Notes |
|---|---|---|
| OkHttp | `OkHttpClient` (+ `newBuilder`, interceptors, timeouts), `Request`/`Builder`, `Response`, `ResponseBody`, `Headers`, `HttpUrl` (+ builder), `FormBody`, `RequestBody`, `MediaType`, `Interceptor`/`Chain`, `CacheControl`, `Call` | `execute()` bridges synchronously to `HTTPClient`. Interceptors must run in Kotlin in the correct chain order |
| Jsoup | `Jsoup.parse`, `Document`, `Element`, `Elements`, `TextNode`, `select`/`selectFirst`, `attr`/`absUrl`, `text`/`ownText`/`html`, traversal | Backed by SwiftSoup through handles. Provide bulk calls to cut bridge crossings |
| Android | `SharedPreferences` (+ `Editor`), `androidx.preference.*` (as a JSON schema), `android.util.Base64`, `android.net.Uri`, `android.graphics.{Bitmap, BitmapFactory, Canvas, Rect}` (scramblers), `android.app.Application` (stub) | `Bitmap`/`Canvas` backed by CoreGraphics |
| JVM stdlib | `java.text.SimpleDateFormat`, `java.util.{Calendar, Date, Locale, TimeZone}`, `java.security.MessageDigest`, `javax.crypto.{Cipher, spec.*}` | Date parsing is pervasive. Crypto maps to CryptoKit/CommonCrypto |
| DI and Rx | `uy.kohesive.injekt.*` (stubs returning the client and `Json`), `rx.Observable` (minimal) | — |
| Build | Generator that turns each module's `build.gradle` metadata into a Kotlin/JS build and bundles every extension into a single `.js` exposing a source factory | Output and `index.min.json` are deterministic given the same commit |

#### CI pipeline

1. A scheduled job (nightly) pulls upstream `main`.
2. It finds changed modules: `extVersionCode` was bumped, or a dependency changed (template, `keiyoushi.*`, or our compatibility library).
3. Each changed module is compiled to JS. On failure, the last good bundle is kept and the failure is recorded with the missing symbol (`Unresolved reference: X`), which feeds the compatibility-library backlog.
4. The job publishes the bundles, `index.min.json` (with `apk` pointing at the `.js`) and the signed `repo.json`.
5. In the app, a higher `code` shows up as "Update" in the extension screen.

#### Known unknowns (Phase 1 must answer)

1. **Viability is unproven.** No known project runs Tachiyomi/Mihon extensions this way on iOS.
2. **`java.*` packages.** Can Kotlin/JS declare classes in `java.*`? If not, CI adds an import-rewrite step (`java.text.` → `compat.java.text.`) before compiling.
3. **Compile rate.** What share of the 1,444 modules compiles against a reasonable compatibility library? Run the whole repo through CI and rank the unresolved symbols by frequency.
4. **Performance.** Parse time under JavaScriptCore with no JIT. The budget is under 300 ms for a typical chapter list (§3.4).
5. **Synchronous bridge behaviour.** Long-running `execute()` calls block the source's JS thread. Confirm that timeouts and cancellation propagate.

---

## 4. Manga reader (`Features/MangaReader/`)

- **`ReaderRouter`** sends `.novel` to the existing WKWebView reader (TTS and comments stay there) and `.manga` to `MangaReaderView`.
- **Viewers** are `UICollectionView`-based:
  - `PagerViewer`: L2R, R2L, vertical. Page layouts: single, double, automatic, split-wide.
  - `WebtoonViewer`: continuous strip.
  - Mode and orientation come from the entry's `viewerFlags`, falling back to the global default.
- **`PageLoader` actor:**
  - Priority queue: the current page first, then preload the next 6.
  - Resolves `imageURL` lazily.
  - `ChapterCache` is an LRU disk cache keyed by md5(imageUrl).
  - Separate loaders for downloads, CBZ and archives (reusing `MiniZIP`).
- **Decoding:**
  - Downsample with ImageIO.
  - Pages taller than ~4× the screen are tiled into strips.
  - Animated images via `CGAnimateImageAtURLWithBlock`.
  - `UIScrollView` zoom.
- **Chapter transitions:**
  - Prev/next transition cells between chapters.
  - Missing-chapter gap warning.
  - Preload the next chapter within the last 5 pages.
- **Progress:**
  - On every page change, set `lastPageRead`, `pagesLeft` and `progress`.
  - On the last page, mark the chapter read, which triggers the AniList update, delete-after-read and auto-download of the next chapters (past 20%).
  - `History.timeRead` accumulates.
  - Incognito mode skips all of this.
- **UI:**
  - Library: one shared library with a Novels / Manga / All filter and shared categories.
  - Browse: grouped by kind, plus an Extensions tab.
  - Entry detail: one view, with kind-specific sections.

---

## 5. Downloads (`Services/Downloads/`), unified

- **`DownloadManager`** (`@Observable`) owns the queue, persisted as `DownloadItem`. **`Downloader`** (an actor) does the work.
- **Concurrency:** 5 sources in parallel, 1 chapter per source, 2 pages per chapter, plus per-source rate limits.
- **Manga pipeline:**
  1. `pages()`, then write each image to `<dir>_tmp/%03d.<ext>` (extension sniffed from magic bytes).
  2. Write as `.tmp`, then rename.
  3. Retry 3× with 2/4/8 s backoff. Reuse images already in `ChapterCache`.
  4. Optionally split tall images.
  5. Write `ComicInfo.xml`, then rename the folder or zip it to `.cbz`.
- **Novel pipeline:** `chapterHTML()` goes to `chapter.html` plus sidecar images.
- **Layout:** `Application Support/Downloads/<Source (LANG)>/<title>/<scanlator_chapter>/`. This is the same as Yokai, so Yokai download folders can be imported through the Files app. The folder is excluded from device backup.
- **Background:**
  - User-started batches use `BGContinuedProcessingTask` (iOS 26), with system progress.
  - Images download through a background `URLSession`.
  - 200 MB free-space guard; Wi-Fi-only via `NetworkMonitor`.

---

## 6. Backup & restore with E2E encryption

### 6.1 Format (`Packages/LNBackupSchema`, SwiftProtobuf)
- **Yokai field numbers, mirrored exactly:**
  - `Backup`: 1 manga, 2 categories, 101 sources, 104 prefs, 105 source prefs.
  - `BackupManga`: 1–9, 13, 14, 16–18, 100–105, 108, 112, 602, 800–805.
  - `BackupChapter`: 1–10, 13, 800.
  - `BackupTracking`: 1–11, 100.
  - `BackupHistory`: 1–3.
  - `BackupCategory`: 1, 2, 100, 800.
  - `BackupSource`: 1, 2.
- **LN data in reserved fields ≥ 5000:**
  - `Backup.5000 novels: [BackupNovel]` (string `sourceKey`, same chapter, history and tracking sub-messages).
  - `Backup.5001 lnSources`.
  - `BackupChapter.5000 progress`, `.5001 paragraphIndex`.
- **Compatibility:** Yokai and Mihon ignore unknown fields. A single file restores fully in LNReader and restores the manga portion in Yokai/Mihon. Mihon/Yokai `.tachibk` files import directly.
- **File handling:** written gzipped; files whose first bytes are the gzip magic (`1f 8b`) are gunzipped on import. The filename is `lnreader_yyyy-MM-dd_HH-mm.tachibk`.
- **Restore merge rules** (from `BackupRestorer`):
  - Categories match by name; entries by (source, url); existing entries keep their DB details.
  - Chapters match by url: read = OR, bookmark = OR, and keep the DB's lastPageRead/progress when the backup's is 0.
  - History takes max(lastRead) and max(timeRead).
  - Tracks match by syncId, taking max(lastChapterRead).
  - Missing sources are offered for install.

### 6.2 Encryption envelope (`.lnbk`)
```
"LNRB" | u8 version | u8 kdf (1 = Argon2id) | kdf params | 16B salt | 12B nonce | AES-256-GCM(gzipped protobuf) | 16B tag
```
- **Key derivation:** Argon2id via `swift-sodium`. The derived key is kept in the Keychain, with optional iCloud Keychain sync. A recovery key is shown once, at setup.
- **Local export:** encrypted `.lnbk` (default) or plaintext `.tachibk` (for interop, with a warning).

### 6.3 Cloud
- The backend becomes a blob store: `PUT /api/backup` (with `If-Match: <etag>`) and `GET /api/backup`.
- **The server never sees plaintext.** `/api/sync` is removed; this is part of the breaking change.
- The client uploads automatically on app background, throttled to once per N hours.
- Restores **merge** using the rules in §6.1, so multiple devices converge even though the blob itself is last-writer-wins.

---

## 7. Trackers (`Services/Tracking/`)

```swift
protocol TrackerService: Identifiable {
    var syncId: Int { get }                       // Yokai IDs: MAL=1, AniList=2, Kitsu=3, … for backup compat
    var supportsReadingDates: Bool { get }
    var statuses: [TrackStatus] { get }; var scores: [String] { get }
    func login() async throws
    func search(_ q: String, kind: ContentKind) async throws -> [TrackSearchResult]
    func bind(_ t: Track, entry: Entry) async throws -> Track
    func update(_ t: Track, setToRead: Bool) async throws -> Track
    func refresh(_ t: Track) async throws -> Track
    func remove(_ t: Track) async throws
}
```

### Required: AniList
- **Login:** OAuth implicit flow via `ASWebAuthenticationSession`, with **our own client ID** and an `lnreader://anilist-auth` redirect. Yokai's ID is bound to `yokai://`. The token goes in the Keychain.
- **API:** GraphQL at `graphql.anilist.co`. Search is filtered by kind: `format_in: [MANGA, ONE_SHOT]` for manga, `[NOVEL]` for novels, so novels get tracking too.
- **Logic ported from `TrackService` / `ChapterTrackSync`:**
  - Bind sets start/finish dates from history and initial progress from chapter state.
  - Status: planning moves to reading when progress > 0; completed when last == total.
  - Auto-update on chapter finish when the new chapterNumber > lastChapterRead.
  - Manual mark-as-read is debounced by 3 s.
  - Offline updates go to `PendingTrackUpdate`, which flushes when the network returns or on `BGAppRefreshTask`.

### Good-to-have (same protocol, any order)
- MyAnimeList (PKCE + refresh)
- MangaUpdates
- Kitsu
- Shikimori
- Bangumi
- Komga and Kavita (two-way chapter sync)

Suwayomi is out of scope.

---

## 8. Library updates
- **Port `ChapterSourceSync`** (used for both kinds):
  - Dedupe by url; `sourceOrder` = list index.
  - Parse `chapterNumber` with a Swift port of `ChapterRecognition`.
  - Add new, update changed, delete missing.
  - `dateFetch = now + descending counter`.
  - Re-added chapters inherit read/bookmark state.
  - Returns (added, removed).
- **Execution:** grouped by source, a task group capped at 5 sources, sequential within each source.
- **Restrictions:** skip completed, skip entries with unread chapters, skip never-read, skip `updateStrategy != always`; Wi-Fi/charging device restrictions.
- **Scheduling:** `BGAppRefreshTask`. New chapters feed Updates, optional auto-download and a local notification.

---

## 9. Roadmap

| Phase | Scope | Exit criteria |
|---|---|---|
| **0a. Bridge build** (`v1-final` branch) | `LNBackupSchema` package; `LegacyBackupConverter` (mapping + `lnr-convert` CLI); "Export for v2" screen in v1 | v1 export → `.tachibk` validated with a round-trip test; CLI converts a real `/api/sync` JSON |
| **0b. v2 foundations** | New versioned schema (§2), new store file, legacy-data notice; `CatalogSource`/`NovelSource`/`MangaSource`; `LNPluginSource` adapter; `HTTPClient` + interceptors; `ExtensionRepo`; backup import/export (unencrypted) | Bridge export imports into v2 with library, chapters, categories, history and settings intact; novel reading works end to end |
| **1. Extension spike** | `lnreader-source-compat`; Kotlin/JS build of Madara + MangaDex + 3 standalone; per-source JSC threads; bulk SwiftSoup bridge; CI compile-rate report; parse benchmarks | ≥4/5 sources browse → pages on device within the parse budget; compile rate measured. **Go/no-go:** if no-go, switch to §3.5 built-ins |
| **2. Browse + reader MVP** | Repo add/trust/install/update UI; manga browse/search/filters; entry detail; pager + webtoon; `PageLoader`, `ChapterCache`; progress + history | Full chapter read online in both modes; Continue and History correct |
| **3. Downloads** | Unified manager, CBZ/folder, ComicInfo, background continuation, delete-after-read, auto-download | Queue survives app kill; offline reading works |
| **4. E2E backup + cloud** | `.lnbk` envelope, Keychain key + recovery key, blob endpoints (backend), auto-backup, Mihon/Yokai `.tachibk` import | Encrypted restore on a fresh device; Yokai backup imports with tracks |
| **5. AniList** | Tracker framework + AniList, auto-update, offline queue, tracker sheet | Finishing a manga or novel chapter updates AniList |
| **6. Updates & polish** | `ChapterSourceSync`, restrictions, BG refresh, notifications; double-page/split; scramble `Bitmap` facade; local CBZ import; optional trackers | Background update finds new chapters and notifies |

Phases 3, 4 and 5 are independent once Phase 2 lands. Phase 0a must ship before any v2 build reaches users.

---

## 10. Risks & open items
1. **Open decision: source scope.** Broad coverage (a large slice of the 1,444 upstream extensions) means the transpiler path (§3.3, §3.6). A curated set of roughly 10–20 sources means built-in Swift (§3.5), and Phase 1 shrinks to writing those sources. Decide this before Phase 1 starts.
2. **Transpile viability and JSC interpreter performance.** Phase 1 decides it, using the known unknowns in §3.6. §3.5 is the fallback.
3. **Bridge adoption.** Users who skip the bridge build fall back to path B (partial data) or reinstall the bridge build over v2. That only works because v2 never deletes the v1 store on its own.
4. **Backend work.** Blob endpoints and removal of `/api/sync`. Decide what happens to existing plaintext rows: delete them at v2 launch, after a fixed window for CLI conversion.
5. **SwiftData at scale.** Use a background `@ModelActor` with batching; profile in Phase 2.
6. **Licensing.** Yokai and keiyoushi extensions are Apache-2.0. Keep NOTICE/attribution for ported logic (backup schema, chapter recognition, tracker logic) and for transpiled bundles.
