# v2 rewrite — progress

Tracking the implementation of `docs/MANGA_SUPPORT_PLAN.md` on `feat/v2-rewrite-manga`.

Migration (`docs/MIGRATION_TO_V2.md`, plan §1) is **deferred by decision** — it will be
revisited once there is a user base worth migrating. v2 therefore does not build the
bridge build, the `.tachibk` converter or the legacy-data notice yet. The one migration
property that *is* honoured is the cheap one: v2 opens its own store file and never
touches `default.store`, so the old data stays recoverable on disk.

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0a. Bridge build | `LNBackupSchema`, `LegacyBackupConverter`, "Export for v2" | Deferred with migration |
| 0b. v2 foundations | Versioned schema, new store, source protocols, HTTP client, repo/trust | **Landed** |
| 1. Extension spike | `lnreader-source-compat`, Kotlin/JS build, JSC threads, parse benchmarks | **Path chosen: Kotlin/JS.** Spike itself not started |
| 2. Browse + reader MVP | Repo UI, manga browse, entry detail, pager + webtoon, `PageLoader` | **Pager + webtoon landed**; repo UI pending |
| 3. Downloads | Unified manager, CBZ/folder, ComicInfo, background continuation | Not started |
| 4. E2E backup + cloud | `.lnbk`, Keychain key, blob endpoints | Not started |
| 5. AniList | Tracker framework, auto-update, offline queue | Not started |
| 6. Updates & polish | `ChapterSourceSync`, restrictions, BG refresh | **`ChapterSourceSync` + `ChapterRecognition` landed**; scheduling not started |

The Kotlin/JS transpiler route is the chosen one for sources (plan §3.3), so broad
extension coverage stays the goal and `BuiltinSource` is only the emergency fallback.
Nothing in slices 1–2 depends on that choice, which is why they could land first.


## Slice 1 — foundations (landed)

Everything below compiles into the app and is covered by the checks at the bottom.
The UI still runs on the v1 models; porting it is slice 2.

### Data model — `Models/Schema/`

| File | What it is |
|---|---|
| `ContentKind.swift` | `.novel` / `.manga`, plus the `ln` / `mihon` source-key prefixes (on-disk format) |
| `EntryStatus.swift` | Yokai's 0–6 statuses and a lenient parser for the free text LN plugins return |
| `UpdateStrategy.swift` | Always / once / never, Yokai raw values |
| `DownloadState.swift` | Queue states for `DownloadItem` |
| `SchemaV1.swift` | `Entry`, `Chapter`, `History`, `Category`, `Track`, `ExtensionRepo`, `DownloadItem`, `PendingTrackUpdate` |
| `SchemaMigrationPlan.swift` | Empty plan; every future schema change adds a stage here |
| `ModelContainerFactory.swift` | Opens `LNReader-v2.store`; never opens or deletes the v1 store |

Design notes:

- **Namespaced.** The models live in `enum SchemaV1` because the v1 `Novel`, `Chapter`
  and `Category` types are still compiled while the UI is ported. Short type aliases
  (`Entry`, `EntryChapter`, `LibraryCategory`, …) are at the bottom of `SchemaV1.swift`
  for ported code. Once v1 is deleted the aliases become the real names.
- **One `Chapter` model for both kinds**, with `progress` as 0–100 and kind-specific
  columns (`lastPageRead` / `pagesLeft` vs `paragraphIndex`) that the other kind ignores.
- **`History` is a real model** keyed by `chapterURL`, replacing v1's denormalized
  `ReadingHistory`. The unique constraint is on the string, not the relationship,
  because SwiftData cannot express uniqueness across a relationship.
- **Cascade rules follow the delete direction.** `Entry → chapters → history / download
  item` all cascade. `DownloadItem.chapter` deliberately does *not* own a cascade: the
  cascade is declared on `Chapter.downloadItem`, otherwise deleting a queue row would
  delete the chapter it points at. (The schema check caught exactly that bug.)

### Network — `Services/Network/`

| File | What it is |
|---|---|
| `HTTPTypes.swift` | `HTTPRequest` / `HTTPResponse` / `HTTPError`, Cloudflare-interstitial detection |
| `HTTPClient.swift` | Actor with an interceptor chain, retries, one `URLSession` and one cookie jar |
| `Interceptors.swift` | `UserAgent`, `RateLimit` (per source *and* host), `Retry`, `Cloudflare` |
| `CloudflareSolver.swift` | Solves a challenge in an off-screen `WKWebView`, returns clearance cookies |
| `CookieJar.swift` | Bridges `URLSession`'s cookie store and WebKit's, both directions |

The point of the interceptor design is that image downloads, chapter scrapes and repo
fetches share one pipeline: UA spoofing, per-source rate limits and challenge recovery
are implemented once instead of per call site. `HTTPClient.shared` is wired at launch
with the Cloudflare solver installed.

### Sources — `Services/Sources/`

| File | What it is |
|---|---|
| `CatalogSource.swift` | `CatalogSource`, `NovelSource`, `MangaSource` protocols |
| `SourceModels.swift` | `SourceEntry`, `EntriesPage`, `SourceChapter`, `SourcePage`, `SourceError` |
| `SourceFilters.swift` | Filter definitions (`SourceFilter`) and selections (`FilterState`) |
| `LNPluginSource.swift` | Adapter from the existing JavaScriptCore plugins to `NovelSource` |
| `SourceManager.swift` | `@Observable` registry, novels and manga, populated from `PluginManager` |

Notes:

- **Filters are split into definitions and state.** The plan's signature took
  `[SourceFilter]` with values baked in (Yokai's mutable filter objects). SwiftUI binds
  better to `FilterState`, and the LN plugin mapping is lossless either way.
- **`LNPluginSource` is the seam that unblocks everything else.** The JS runtime did not
  change at all; the app can move to `CatalogSource` before any manga source exists.
- **Legacy types were renamed** to free the canonical names: `SourceChapter` →
  `PluginChapter`, `SourcePage` → `PluginChapterPage`, `SourceNovel` → `PluginNovel`,
  `PartialNovel` → `PluginNovelRef`, `FilterOption` → `PluginFilterOption`. The v1 plugin
  layer now reads as what it is — one implementation behind the protocol.

### Verification

```sh
./scripts/typecheck.sh            # whole app, no Xcode needed
./scripts/check-v2-schema.sh      # in-memory container: CRUD, relationships, cascades, uniqueness
./scripts/check-v2-foundation.sh  # status mapping, identity, filters, dates, HTTP values
```

`typecheck.sh` drives `swiftc` directly because Xcode's package resolution and macro
plugin server need nested sandboxes. It expects SwiftSoup/Glur `.swiftmodule` files in
`/tmp/lnr-mod` (see the script header).

## Slice 2 — read path on v2 (landed)

The app now runs on `SchemaV1`. The v1 models (`Novel`, `Chapter`, `ReadingHistory`,
`Category`, `Repository`, `NovelStatus`) are deleted; `ModelContainerFactory.makeV2()`
is the only store the app opens.

### What changed

| Area | Change |
|---|---|
| Store | `LNReaderApp` opens `LNReader-v2.store` through `ModelContainerFactory`; `UserProfile` moved into `SchemaV1.models` |
| Models | Aliases promoted to real names: `Entry`, `Chapter`, `History`, `Category` |
| Library | `LibraryView` / grid / list / drop delegate query `Entry`; sorting uses `libraryOrder`, `lastUpdate`, `unreadCount`, `totalChapterCount` |
| Detail | `NovelDetailView` takes `entry:` or `sourceEntry:` and fetches through `NovelSource` instead of `PluginManager` |
| Chapter list | `ChapterDisplay` bridges `Chapter` and `SourceChapter`; `releaseTime` is now formatted from `dateUpload` |
| Reader | `ReaderView` takes `sourceKey` + `entryURL`, resolves the source from `SourceManager`, reads local books via `sourceKey == "local"` |
| History | Queries `History.lastRead` and walks `chapter → entry` for titles and covers |
| Updates | Queries `Chapter.dateFetch` instead of `updatedAt` |
| Stats | Category counts use `Category.entries`; source counts use `entry.sourceKey` |
| Sync | Wire format unchanged (`/api/sync` still speaks v1 `path`/`pluginId`); only the mapping changed |
| Local books | Imported EPUB/PDF become `Entry(sourceKey: "local")`, with `isLocal` computed |

### Design notes

- **`Entry.lastReadAt` is a cached column.** The library sorts by "recently read" and a
  `#Predicate` cannot walk chapters → history, so the reader writes the timestamp on
  `Entry` as well. `History` remains the source of truth for the History screen.
- **`Chapter.isDownloaded` is computed** from the download queue (or from the entry being
  local), replacing the stored v1 flag that could drift from reality.
- **`SourceKey`** owns the `"ln:<id>"` / `"mihon:<id>"` / `"local"` grammar. Anything that
  needs the bare plugin id (TTS book ids, comment-site lookup) goes through it, which is
  what keeps existing audio downloads and NovelFire comments working.
- **Type-checker pressure is real.** Two views had to be split into smaller computed
  properties (`ReaderView.presentation` / `.readerStack`, `LibraryView.libraryContent`);
  a 25-modifier body is past what Swift will infer in reasonable time.

### Verification

```sh
./scripts/typecheck.sh            # whole app
./scripts/check-v2-schema.sh      # schema CRUD, cascades, uniqueness
./scripts/check-v2-foundation.sh  # status mapping, identity, filters, dates, HTTP values
```

## Slice 3 — browse on the source layer (landed)

The UI no longer knows what a JS plugin is. `Services/Plugins/` is now referenced only
by `LNPluginSource` (the adapter) and by `PluginManager` (install/uninstall), which is
what the plan wants: one implementation behind `CatalogSource`.

| File | Change |
|---|---|
| `SourceDetailView` | Takes a registry entry only to derive the source key; popular/search/pagination go through `NovelSource` and `EntriesPage` |
| `GlobalSearchView` | Iterates `sourceManager.novelSources` and calls `search(query:page:filters:)` |
| `BrowseEntryCell` | Renders `SourceEntry` instead of `PluginNovelRef` |
| `NovelDetailView` | Opened with `sourceEntry:` straight from search results |

Notes:

- **Filters are plumbed but not surfaced.** Calls pass `FilterState()` (empty), which the
  adapter turns into "no filter values" — the same behaviour v1 had with `nil`. A filter
  sheet can now be added without touching the call sites.
- **Browse is still the extension manager.** `BrowseView` keeps `PluginManager` because
  installing and uninstalling is a registry concern; it will move to `ExtensionRepo` when
  the repo/trust work lands.

## Slice 4 — chapter list sync (landed)

| File | What it is |
|---|---|
| `Services/Sources/ChapterRecognition.swift` | Port of Yokai's `ChapterRecognition` (Apache-2.0): `Ch.4.a` → 4.1, `404 extravol002` → 404.99, `The 1st Night` → 1, `Foo` → -1 |
| `Services/Sources/ChapterSourceSync.swift` | Merges a fetched chapter list into an entry: match by URL, `sourceOrder` from the list index, `dateFetch` on new chapters, returns `(added, updated, removed)` |
| `LibraryManager.applyUpdate` | Now delegates the chapter merge to `ChapterSourceSync` instead of duplicating it |

Decisions worth knowing:

- **Delete-missing is guarded.** A chapter the source stopped listing is deleted only
  when the user has no stake in it — unread, unbookmarked, no history. Tachiyomi deletes
  unconditionally and loses the state of a chapter the site merely renamed; keeping the
  row means a re-added chapter comes back still read. The plan asks for "delete missing",
  and this satisfies it for the case it was meant for (junk chapters) without the data loss.
- **Numbers are parsed, not trusted.** A source number `> -1` wins; otherwise the title is
  parsed once at insert and again if a stored chapter still has `-1`. Both kinds need this:
  manga sorting and the AniList update both compare numbers.
- **Reference tests are ported, not invented.** `tests/V2ChapterSyncChecks.swift` carries
  Yokai's `ChapterRecognitionTest` cases verbatim (40 of them) plus merge behaviour against
  an in-memory store, so the port can be diffed against upstream.

## Slice 5 — manga page pipeline (landed)

The headless half of the manga reader: the cache every page goes through, and the
ordering the viewers will ask it for. No UI yet — that comes with the viewers.

| File | What it is |
|---|---|
| `Services/Images/ChapterCache.swift` | Actor-backed LRU disk cache keyed by MD5(imageURL), 512 MB default, self-trimming to 90% of the limit |
| `Features/MangaReader/PagePrefetchPlan.swift` | Pure ordering: current page first, then 6 ahead, 1 behind; plus the "5 pages from the end" next-chapter trigger |

Notes:

- **LRU order is each file's modification date**, touched on every read. That survives
  restarts without a separate index file that could drift from the directory contents.
- **Writes are write-then-rename**, so a crash mid-download cannot leave a half image the
  reader would decode into a corrupt page.
- **The cache is excluded from backups by location** (`Application Support/ChapterCache`):
  it is re-downloadable, and carrying hundreds of megabytes into iCloud is waste.
- The check caught a real accounting bug: the size was measured *after* writing the new
  file, so every store double-counted and the cache trimmed one file too early.

## Slice 6 — manga reader (landed)

| File | What it is |
|---|---|
| `Features/MangaReader/MangaReaderView.swift` | Paged or continuous reader, page indicator, chapter navigation, tap-to-hide controls |
| `Features/MangaReader/MangaPageView.swift` | One page: own load task, own failure state, retry, off-main decoding |
| `Features/MangaReader/MangaReadingMode.swift` | Paged / webtoon, plus LTR / RTL for paged mode |
| `Features/MangaReader/MangaProgress.swift` | Page index → progress / pagesLeft / finished, pure |
| `Features/Reader/ChapterReader.swift` | Routes a chapter to the novel reader or the manga reader by kind |
| `Services/Images/PageLoader.swift` | Cache → in-flight de-duplication → fetch; `file://` pages read from disk |
| `Services/Sources/SampleMangaSource.swift` | DEBUG-only built-in source with generated pages, so the reader is testable offline |

### How to try it on device

1. Build and run (Debug).
2. **Browse → Built-in Sources → Sample Manga (offline) → Aurora Drift.**
3. Tap **Add to Library** on the detail screen, then open a chapter.
4. Tap the page to show/hide controls; the menu switches **Paged / Webtoon** and, in
   paged mode, **Left to right / Right to left**.
5. Progress is saved per page; finishing the last page marks the chapter read, and
   History / Updates show it.

The sample source is compiled out of Release builds. It exists so the reader, cache and
progress can be exercised before the Kotlin/JS extensions land; the same code paths run
against a real `MangaSource` once one is installed.

### Design notes

- **SwiftUI paging, not `UICollectionView` — for now.** `TabView(.page)` plus a
  `LazyVStack` covers both layouts with a fraction of the code. The plan calls for
  `UICollectionView` viewers because double-page spreads, split-wide pages and tiled
  decoding of very tall images need it; that swap is contained to `MangaReaderView` and
  `MangaPageView`, and `PagePrefetchPlan` already gives the order either one needs.
- **Decoding is off the main actor.** A page is a few megabytes compressed; decoding it
  inline stalls scrolling.
- **RTL is `layoutDirection`.** SwiftUI's page view reverses its swipe handling from the
  environment, so no index arithmetic is needed.
- **`file://` pages skip the network entirely**, which is how local books, CBZ archives
  and the sample source are served by the same loader.

### Project file

`LNReader.xcodeproj` lists sources individually, so the new files were added to the target
directly (verified: 112 files on disk, 112 compiled, no stale references). `project.yml`
remains the source of truth — `xcodegen generate` reproduces the same membership.

## Slice 7 — next

1. **Extension repos + trust.** `ExtensionRepo` rows, `index.min.json` fetch, signing
   fingerprint pinning — the entry point for the Mihon path.
2. **`UICollectionView` viewers** with double-page/split-wide layouts and tiled decoding
   for very tall pages, replacing the SwiftUI pager.
3. **Downloads** (plan §5), reusing `PageLoader` and `ChapterCache`.
4. **Library update scheduling** (plan §8): `BGAppRefreshTask`, per-entry restrictions,
   batching through a background `@ModelActor`.
5. **Filter UI** on browse, now that `FilterState` exists.
