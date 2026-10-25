# Adding a source

A source is one Swift file in `Services/Sources/Native/`. There is no install step and no JS: the
site's logic is compiled into the app, so fixing a site means editing the file and reinstalling.

## 1. Write the source

Copy a small one as a starting point: `FourKHDSource.swift` (manga, JSON API) or
`NovelFireSource.swift` (novel, HTML). Conform to `MangaSource` or `NovelSource`
(`Services/Sources/CatalogSource.swift`).

- **Identity:** `key = SourceKey.makeBuiltin(id: "<id>")`, `kind`, `name`, `lang`. The key is
  stored on every library entry, so never change it once shipped.
- **Network:** build a `SiteClient(sourceKey:baseURL:)`. It goes through the shared `HTTPClient`,
  so rate limits, cookies and Cloudflare handling are not per source. Parse with SwiftSoup or
  `Codable`. Mind the `Element` helpers in `NativeSupport.swift`.
- **Browsing:** `popular`, `latest` (set `supportsLatest`), `search`, `filters()`. Filters are
  definitions (`SourceFilter`); the user's choices arrive as `FilterState`.
- **Reading:** manga returns `pages(_:)` and, if the CDN needs headers, a `URLRequest` from
  `imageRequest(_:)` (`SourcePage.headers` is the easy route). Novels return HTML from
  `chapterHTML(_:)`.
- **Urls are persisted.** Entry and chapter `url` values are stored in the library, in downloads
  and in backups. Keep them in the shape upstream uses (for a port, exactly what the Mihon
  extension stores), or old data stops resolving.
- Order chapters however the site does; the app orders by chapter number. Return `-1` when the
  site gives no number and `ChapterRecognition` fills it.
- `isAdult = true` shows the red 18+ chip in Browse.
- Keep the type `Sendable`: a final class with `let` properties, or a struct. Shared mutable
  state (a throttle, a cache) goes in a private actor.

## 2. Register it

1. Add `YourSource()` to `NativeSources.all()` in `NativeSupport.swift`.
2. **Manga ported from Mihon/Tachiyomi:** add its id to `NativeSourceIDs.mihon` so `.tachibk`
   backups land on it. The id is `MihonSourceID.make(name:lang:versionId:)`: the lowercased
   name, the language and upstream's `versionId` (default 1; some sources pin an id by hand,
   as AllManga does). Check it against a real backup if you have one.
3. **Add the file to the Xcode target by hand.** The project lists files individually and a
   missing file fails silently. Validate with `plutil -lint LNReader.xcodeproj/project.pbxproj`.
4. **Icon (optional):** add `Assets.xcassets/<Name>Icon.imageset` with a PNG and set
   `iconAsset = "<Name>Icon"`.

## 3. Check it

```sh
SOURCES=<id> ./scripts/try-native.sh     # live site: popular, latest, search, details,
                                         # chapters, then pages + one image (manga) or
                                         # chapter HTML (novel)
./scripts/typecheck.sh
./scripts/check.sh all
```

`try-native.sh` compiles only the app files listed in the script plus `Services/Sources/Native/`,
so a source that needs another app file takes it via `EXTRA="path/One.swift ..."`. It needs the
network and is not part of `check.sh all`. A PASS there is not "verified": open the source on an
iPhone, read a chapter and download one before calling it working.

Sites behind Cloudflare time out in the headless runner, which has no WebKit solver. That is
a runner limit; confirm those in the app.
