# Manga support — architecture decisions

What is left of the original design doc: the decisions that still constrain the code, and the
parts of the extension pipeline that were never built. Everything else it described has
shipped — the reader, downloads, backup and AniList are in the app and
[V2_PROGRESS.md](V2_PROGRESS.md) is the status ledger.

Reference implementation: `yokai/` (Tachiyomi/Mihon fork, Kotlin/Android).

## Ground rules

- **v2 is a hard, breaking release.** No in-place data migration, no compatibility layer.
  Migration is deferred by decision; v2 opens its own store file and leaves v1 data on disk.
- **Everything runs on device.** No server-side source execution, no Suwayomi mode.
- **Distribution is sideloaded or self-built.** Nothing goes to the App Store, so review rules
  don't constrain us. iOS code signing still applies.
- **AniList is the only required tracker.** Every other tracker is good-to-have.

## Source model (as built)

`Services/Sources/CatalogSource.swift` is the spec: `CatalogSource` (browse, search, details,
chapters), `NovelSource` adding `chapterHTML`, `MangaSource` adding `pages`, `imageURL` and
`imageRequest`. Filters come from the source as `[SourceFilter]` and go back as a
`FilterState`.

`SourceManager` handles repos, installs, updates, trust (fingerprint check as in
`TrustExtension.kt`) and per-kind lists. `LNPluginSource` wraps the JSC runtime,
`BundledExtensions` ships first-party ports, and `MihonSource` — the wrapper for transpiled
Kotlin (§1) — does not exist.

## 1. Mihon extensions: transpile Kotlin to JS, run in JavaScriptCore — **on hold**

The keiyoushi/extensions-source Kotlin is compiled with **Kotlin/JS** against
`lnreader-source-compat`, a Kotlin/JS library that re-implements, under the same
fully-qualified names, the APIs extensions import:

- `okhttp3.*` → a synchronous bridge into `HTTPClient`.
- `org.jsoup.*` → SwiftSoup. Coarse-grained calls (`select(css) → [handles]`, bulk
  `attrs`/`texts`) to minimise JS↔Swift crossings.
- `SharedPreferences`/`PreferenceScreen` → a key-value store plus a JSON schema SwiftUI renders.
- `rx.Observable`, `java.text.SimpleDateFormat`/`Calendar`, `Injekt` → minimal shims.
- `eu.kanade.tachiyomi.source.*` is **upstream's** source API, not Yokai's copy, which has
  fallen behind. Compile against upstream's extensions-lib.

**Execution model.** Swift owns all I/O, images and concurrency; JS only builds requests and
parses responses. One `JSVirtualMachine`/`JSContext` per source on its own thread, so sources
run in parallel and calls within a source serialise — which is what Yokai does and what
per-source rate limits want anyway.

### Why not port extensions to native Swift

**Decision: keep the transpiled JS path for site logic; everything else is native Swift.**

1. **Blocking and sequential is not the effect.** Only parsing runs in JS. Page images — the
   bulk of bytes and time — never touch JS: the extension returns a `URLRequest` and Swift
   downloads pages concurrently. Contexts are per source and per thread, so updates and
   downloads across sources run in parallel like Yokai's semaphore of 5.
2. **We get upstream maintenance.** Upstream has ~1,444 extensions and ~548 commits in 30 days
   (§1). Transpiling means a CI rebuild picks up those fixes; hand-ported Swift means owning
   every site breakage forever. This holds for **broad coverage** — for a curated 10–20
   sources, native Swift is simpler and reasonable.
3. **Swift sources can't be distributed as extensions, even sideloaded.** No `dlopen` of
   downloaded unsigned code and no JIT on iOS. Native sources would be compiled into the IPA,
   so every site fix would mean a rebuild and re-sideload. JS bundles update in-app.
4. **Backup interop for free.** The Kotlin code computes source IDs
   (`md5("name/lang/versionId")`, first 8 bytes as a big-endian Long, `& Long.MAX_VALUE`), so
   they match Mihon/Yokai and their `.tachibk` backups resolve to our sources.

**What's true about the objection:** JavaScriptCore runs without JIT and every Jsoup call
crosses the bridge, so selector-heavy sources parse slower than native. The Phase 1 spike
benchmarks chapter-list parse time (Madara, MangaDex) against a 300 ms budget; mitigation is
the bulk Jsoup bridge, and anything that still misses the budget gets a built-in source.

### Escape hatch: built-in native sources

`BuiltinSource: MangaSource` in Swift, for very popular sources with a clean JSON API
(MangaDex, Comick), and as the Phase 1 no-go fallback: a curated set plus the multisrc themes
(Madara, MangaThemesia) as native generic implementations driven by JSON site lists.

### Upstream facts

Snapshot of `keiyoushi/extensions-source` at `ff521c17bb3e`, 2026-10-20. **Re-measure before
relying on the numbers.**

| Metric | Value |
|---|---|
| Extension modules | 1,444 (en 418, ja 140, all 132, pt 116, es 110, id 85) |
| Shared site templates | 66 under `lib-multisrc/` (Madara, MangaThemesia, Keyoapp, …) |
| Commits, last 30 / 365 days | 548 / 3,723 |
| Most-churned templates, 30 days | pam 27, vinetheme 12, clipstudioreader 12, initmanga 11 |

The breakage our pipeline must absorb, and what the compatibility library needs for each:

| Kind of breakage | What the compat library needs |
|---|---|
| Site redesign, selectors stop matching | Nothing new; pure Kotlin + Jsoup |
| Site moved to a new platform | Usually nothing new |
| Domain changes ("update domains") | Nothing new |
| Anti-bot, rate limits, sessions | Correct OkHttp interceptor and cookie semantics |
| Image protection (AES-GCM blobs, off-screen readers) | `javax.crypto` stand-ins, off-screen WebView bridge — or mark unsupported |
| New sources | Nothing new if built on an existing template |

Most fixes are pure parsing logic, which the transpiler picks up for free. The rest need a
stand-in API added once, which then serves every extension that uses it.

### Compatibility library scope (Phase 1 backlog)

| Area | Contents | Notes |
|---|---|---|
| OkHttp | `OkHttpClient` (+ builder, interceptors, timeouts), `Request`/`Response`, `ResponseBody`, `Headers`, `HttpUrl`, `FormBody`, `RequestBody`, `MediaType`, `CacheControl`, `Call` | `execute()` bridges synchronously to `HTTPClient`; interceptors must run in Kotlin in chain order |
| Jsoup | `Jsoup.parse`, `Document`, `Element(s)`, `TextNode`, `select`/`selectFirst`, `attr`/`absUrl`, `text`/`ownText`/`html`, traversal | Backed by SwiftSoup handles; bulk calls to cut crossings |
| Android | `SharedPreferences`, `androidx.preference.*` (as a JSON schema), `Base64`, `Uri`, `graphics.{Bitmap, Canvas, Rect}` (scramblers), `Application` (stub) | Bitmap/Canvas backed by CoreGraphics |
| JVM stdlib | `SimpleDateFormat`, `Calendar`/`Date`/`Locale`/`TimeZone`, `MessageDigest`, `javax.crypto` | Date parsing is pervasive; crypto maps to CryptoKit/CommonCrypto |
| DI and Rx | `uy.kohesive.injekt.*` stubs, `rx.Observable` (minimal) | — |
| Build | Generator that turns each module's `build.gradle` metadata into a Kotlin/JS build and bundles it into one `.js` exposing a source factory | Output and `index.min.json` deterministic for a given commit |

**CI:** nightly pull of upstream `main` → find modules whose `extVersionCode` was bumped or
whose template/helper dependency changed → compile each to JS (on failure keep the last good
bundle and record the missing symbol, which feeds the backlog) → publish bundles,
`index.min.json` (`apk` pointing at the `.js`) and the signed `repo.json` → the app shows an
"Update" in the extension screen on a higher `code`.

**Known unknowns Phase 1 must answer:** viability (no known project runs Tachiyomi extensions
this way on iOS); whether Kotlin/JS can declare classes in `java.*` (else CI rewrites imports);
what share of the 1,444 modules compiles at all; parse time without JIT; and whether timeouts
and cancellation propagate through a blocking `execute()`.

## 2. Trackers

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

**AniList is built.** GraphQL at `graphql.anilist.co`, implicit-flow login via
`ASWebAuthenticationSession` with our own client ID and `lnreader://anilist-auth`, token in the
Keychain. Search is filtered by kind (`format_in: [MANGA, ONE_SHOT]` / `[NOVEL]`) so novels
track too. Logic ported from `TrackService`/`ChapterTrackSync`: bind sets start/finish dates
from history, planning moves to reading when progress > 0, completed when last == total,
auto-update on finish when the new number is higher, and offline writes queue in
`PendingTrackUpdate`.

Good-to-have, same protocol, any order: MyAnimeList (PKCE + refresh), MangaUpdates, Kitsu,
Shikimori, Bangumi, Komga and Kavita (two-way chapter sync). Suwayomi is out of scope.

## 3. Open decisions

1. **Source scope — undecided, blocks Phase 1.** Broad coverage means the transpiler (§1). A
   curated set of 10–20 sources means built-in Swift and Phase 1 shrinks to writing those
   sources. Decide before starting either.
2. **Transpile viability and interpreter performance.** Phase 1 decides it; the built-in
   escape hatch is the fallback.
3. **Licensing.** Yokai and keiyoushi extensions are Apache-2.0. Keep NOTICE/attribution for
   ported logic (backup schema, chapter recognition, tracker logic) and for transpiled
   bundles.
