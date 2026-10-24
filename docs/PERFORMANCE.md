# Performance

**Updated** 2026-10-23 · **Branch** `feat/v2-rewrite-manga`

The app was slow in a specific, measurable way: the library and the reader both
did per-row work that resolved SwiftData relationships, and the reader wrote to
the store on every scroll tick. This documents what was wrong, what changed, and
how to measure the next regression.

## Measure first

```sh
./scripts/profile-hotpaths.sh          # headless, no device, ~45 s
./scripts/profile-device.sh 30         # builds Release, installs, records hitches + Time Profiler
```

`profile-hotpaths.sh` builds a 120-book × 250-chapter store on disk and times the
data work behind the UI. `profile-device.sh` records a Time Profiler trace of a
real device (Animation Hitches plus Time Profiler) so the parts the benchmark cannot see — body evaluation, layout,
WebKit, image decode — are covered too.

## Numbers

From `profile-hotpaths.sh`, 120 entries × 250 chapters (30 000 chapters):

| Path | Before | After | |
|---|---|---|---|
| Library unread + total counts, whole library | 4 776 ms | 1 155 ms | 4.1× |
| One grid cell's badge (3 reads) | 37.3 ms | 10.4 ms | 3.6× |
| Reading progress tick (save vs mutate) | 1.5 ms | 0.1 ms | 10.8× |
| Chapter rows, date formatting (2 000) | 3.2 ms | 0.1 ms | 22.4× |
| Chapter ordering (2 000 rows, 3 body passes) | 0.9 ms | 0.3 ms | 3.8× |

The absolute numbers matter more than the ratios. A 12-cell grid paid
`37.3 × 12 ≈ 450 ms` of relationship faulting **per body pass**, and the reader's
save-per-tick re-ran every `@Query` in the app, which triggered that body pass
again — four times a second, while scrolling.

## What was wrong

### 1. `Entry.unreadCount` walked the whole chapter list, per cell

`Entry.unreadCount` / `totalChapterCount` are `chapters.count { !$0.read }`.
Accessing them faults every `Chapter` row for that entry. `NovelGridCell` read
`unreadCount` twice and `totalChapterCount` once; `LibraryListRow` did the same;
sorting by unread did it for every entry.

Fixed with `LibraryChapterCounts` (`Services/LibraryManager.swift`): a SQL
`COUNT` per entry on a background `ModelContext`, cached by
`PersistentIdentifier` with a 5 s TTL and a generation counter so a count that
started before an invalidation cannot write a stale answer back. Cells read the
cached value synchronously and fill it in a `.task`.

Nothing is denormalised onto the model, so the count cannot drift from the
chapters — it is only ever a cached read of them. That was the reason for not
adding a stored column: a schema migration to cache a number the store can
already answer is a bad trade.

### 2. The reader saved on every scroll tick

`recordReadingPosition` called `context.save()`. The JS scroll listener debounces
at 300 ms, so a scroll wrote to the store ~4×/second. Each save is a WAL write
plus a store-change notification, and the notification re-runs every `@Query` in
the app — including the library's entry query sitting behind the full-screen
reader.

Fixed by coalescing: the model is mutated immediately (the UI stays live) and
written on a 3 s timer, with `flushProgress` called when the reader closes and
when the app backgrounds. `Entry.lastReadAt` and `History.lastRead` are only
refreshed once a minute, because nothing reads them below that granularity and
rewriting them invalidated the library query for no benefit.

### 3. Every chapter load fetched a font from a third-party CDN

`readerHTML` put `<link href="https://fonts.cdnfonts.com/css/open-dyslexic">` in
`<head>` unconditionally. A stylesheet link in the head is render-blocking: the
first line of text waited on a network round trip to a CDN that has nothing to do
with the chapter. Now the link is only emitted when OpenDyslexic is the selected
family, and switching to it from the settings sheet injects the link from script
(which does not block).

### 4. Covers were decoded at full resolution, on the draw path

`CustomAsyncImage` cached `UIImage(data:)` results — lazy-decoded, so the decode
happened on the main thread at first draw — and inserted them into `NSCache`
without a cost, so `totalCostLimit` did nothing and 200 full-resolution covers
could sit in memory at ~8 MB each.

Now `CoverDecode` downsamples with ImageIO to a 700 px long edge and forces the
decode at creation, and the cache is byte-accounted. `NovelCoverView` also lost
its per-cell `GeometryReader`, which was a layout pass per cell.

Manga pages keep full resolution (they are read, not glanced at) but are decoded
with `preparingForDisplay()` off the main actor and kept in `PageImageCache`, so
scrolling back over a page no longer decodes it again.

### 5. The chapter list recomputed ordering on every body pass

`NovelDetailView.orderedChapters` was a computed property: a scanlator pass plus
a full `localizedStandardCompare` sort, read two to three times per body
evaluation. It is now state, rebuilt when the chapters or the scanlator
preference change. `ChapterDisplay` also formatted a release date per chapter in
its initializer — 2 000 formatter runs to display ten rows — and now keeps the
`Date` and formats on access.

`MangaReaderView.navigableChapters` had the same shape (rebuilt twice per body
via `hasChapter`) and is now state too.

### 6. Statistics pulled the whole store into a view

`@Query private var chapters: [Chapter]` loaded every chapter in the database as
a SwiftUI dependency, and the "downloaded" tile faulted each chapter's
`downloadItem`. Replaced with one background pass of `fetchCount` plus the
history dates the charts actually need.

History and Updates grouped rows by a fully formatted timestamp string, which put
every row in its own section and rebuilt a format style per row. They now group
by `startOfDay` with one shared formatter.

### 7. The manga reader (second pass)

Found by reading the code, not by a trace — verify on a Release device build.

- **Every page turn saved.** `scheduleProgressSave` writes immediately after 3 s idle, which
  is every turn when reading page by page, and each save re-runs every `@Query` on the main
  thread. Manga progress is now `deferred` (30 s) and lands on close, chapter change and
  backgrounding.
- **Decoded pages were never released.** Each `MangaPageView` held its bitmap in `@State`, so
  a long chapter kept every page alive. Pages now drop the bitmap in `onDisappear`; the
  byte-accounted `PageImageCache` (160 MB) serves a quick scroll back, and the aspect ratio is
  remembered per page so the slot keeps its height instead of collapsing to a spinner.
- **Decoding ignored scrolling.** `Task.detached` was not cancelled when a page scrolled
  away and there was no limit on parallel decodes. Decoding is now `@concurrent`, cancellable,
  and gated to two at a time (`PageDecodeGate`).
- **Pages were drawn 3× oversized.** The bitmap was decoded at pixel width but tagged scale 1,
  so the GPU minified it every frame. It is now tagged with the display scale.
- **A drag gesture covered the whole strip** for the right-edge dismiss swipe. It is now a
  `UIScreenEdgePanGestureRecognizer` that only exists at the edge.
- **Not done:** `ChapterCache.data` still rewrites the file's modification date on every read.
  Throttling it breaks the cache's LRU contract (checked by `check-v2-page-pipeline.sh`), so it
  stays unless a trace shows it matters.

## Still to look at

Ordered by expected payoff on device, not yet measured:

1. **`ReaderView` re-evaluates on TTS state.** `ttsManager` is an
   `@ObservedObject` on the reader body, and `elapsed` updates continuously.
   While listening, the whole reader body (including the `ReaderContent` diff)
   runs at that rate. Splitting the transport controls into their own view would
   contain it.
2. **`ChapterRow.audioCount`** filters the whole TTS record list per row, and
   every row observes `TTSOfflineLibrary`.
3. **`updateLibrary` holds the main actor** while merging results, one entry at a
   time. The network part is already off-main; the merge is not.
4. **`SourceManager` / plugin restore at launch** runs on the main actor in
   `ContentView.task`, ahead of the first frame's work.
5. **MangaFire `vrf`** is recomputed per request; check whether the extension
   caches it.

## Rules that came out of this

- **Never read a relationship count in a `body`.** Use `LibraryChapterCounts` or a
  `fetchCount` off-main. `Entry.unreadCount` is fine inside a background pass that
  has already faulted the chapters; it is not fine per cell.
- **Never `save()` from a scroll or progress callback.** Mutate and let
  `LibraryManager.flushProgress` land it.
- **Nothing render-blocking in the reader's `<head>`.** The chapter should paint
  from local bytes only.
- **Cache decoded images, not compressed data, and always with a cost.**
