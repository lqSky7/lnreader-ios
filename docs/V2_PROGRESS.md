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
| 0b. v2 foundations | Versioned schema, new store, source protocols, HTTP client, repo/trust | **In progress — slice 1 landed** |
| 1. Extension spike | `lnreader-source-compat`, Kotlin/JS build, JSC threads, parse benchmarks | Not started (go/no-go gate) |
| 2. Browse + reader MVP | Repo UI, manga browse, entry detail, pager + webtoon, `PageLoader` | Not started |
| 3. Downloads | Unified manager, CBZ/folder, ComicInfo, background continuation | Not started |
| 4. E2E backup + cloud | `.lnbk`, Keychain key, blob endpoints | Not started |
| 5. AniList | Tracker framework, auto-update, offline queue | Not started |
| 6. Updates & polish | `ChapterSourceSync`, restrictions, BG refresh | Not started |

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

## Slice 2 — next

Ordered so each step is independently shippable:

1. **Port the read path to `Entry`.** Library, Updates, History, entry detail, chapter
   list. Old models and new coexist until this lands; then delete `Novel`,
   `ReadingHistory` and the `PluginNovel*` aliases.
2. **Browse on `SourceManager`.** Replace `PluginManager` reads in Browse/Search with
   `CatalogSource`, including filters via `FilterState`.
3. **`ChapterSourceSync`** (plan §8) so updates write through the new models.
4. **Extension repos + trust.** `ExtensionRepo` rows, `index.min.json` fetch, signing
   fingerprint pinning. This is also the entry point for the Mihon path.
5. **Manga reader** (plan §4) with a stub `MangaSource` so the pager and webtoon viewers
   can be built and tested before the transpiler exists.
6. **Downloads** (plan §5).

Phase 1 (the transpiler spike) stays a separate go/no-go: it decides whether sources come
from Kotlin/JS or from a curated set of built-in Swift sources. Nothing in slice 1 depends
on that answer, which is why it was safe to build first.
