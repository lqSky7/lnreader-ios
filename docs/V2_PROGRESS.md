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
| 2. Browse + reader MVP | Repo UI, manga browse, entry detail, pager + webtoon, `PageLoader` | **Browse + detail on v2**; manga reader not started |
| 3. Downloads | Unified manager, CBZ/folder, ComicInfo, background continuation | Not started |
| 4. E2E backup + cloud | `.lnbk`, Keychain key, blob endpoints | Not started |
| 5. AniList | Tracker framework, auto-update, offline queue | Not started |
| 6. Updates & polish | `ChapterSourceSync`, restrictions, BG refresh | Partially: update merge runs on v2 models |

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

## Slice 4 — next

1. **`ChapterSourceSync`** (plan §8): dedupe, `chapterNumber` parsing via a port of
   `ChapterRecognition`, delete-missing, and a background `@ModelActor` for batching.
   Today `LibraryManager.applyUpdate` adds and updates but never removes.
2. **Extension repos + trust.** `ExtensionRepo` rows, `index.min.json` fetch, signing
   fingerprint pinning. This is the entry point for the Mihon path.
3. **Manga reader** (plan §4) with a stub `MangaSource` so the pager and webtoon viewers
   can be built before the transpiler exists.
4. **Downloads** (plan §5).
5. **Filter UI** on browse, now that `FilterState` exists.

