// MigrationSearch.swift - Finding an entry's counterpart in other sources.
//
// Every search goes through `MigrationPacer`, so a bulk run spaces its requests
// per source, retries a failure with backoff and skips a source that stops
// answering. A source that did not answer is reported rather than hidden: an
// empty result and a dead source are different things to the user.

import Foundation

/// One search hit that might be the same series.
struct MigrationCandidate: Identifiable, Hashable, Sendable {
    let entry: SourceEntry
    let sourceName: String
    /// `MigrationMatcher.score` against the entry being replaced.
    let score: Double

    var id: String { entry.id }
    var isConfident: Bool { score >= MigrationMatcher.autoAcceptScore }
}

/// Hits from a search, plus the sources that could not be asked.
struct MigrationSearchResult: Sendable {
    var hits: [MigrationCandidate] = []
    /// Display names of sources that failed or were cooling down.
    var failed: [String] = []

    var isEmpty: Bool { hits.isEmpty }
}

/// The best hit for one entry, plus the sources that did not answer.
struct MigrationMatch: Sendable {
    var candidate: MigrationCandidate?
    var failed: [String] = []
}

enum MigrationSearch {

    /// The entry's title and its custom title, if different. The first is searched.
    @MainActor
    static func titles(for entry: Entry) -> [String] {
        var titles = [entry.title]
        if let custom = entry.customTitle, !custom.isEmpty, custom != entry.title { titles.append(custom) }
        return titles
    }

    /// Hits from every source at once, best first.
    ///
    /// Sources are searched concurrently because they are different hosts; the
    /// pacer still serialises two searches of the *same* source.
    static func candidates(
        titles: [String],
        sources: [any CatalogSource],
        query: String? = nil,
        excluding excluded: String? = nil,
        perSource: Int = 5,
        pacer: MigrationPacer = .shared
    ) async -> MigrationSearchResult {
        guard let text = query ?? titles.first, !text.isEmpty else { return MigrationSearchResult() }
        var found: [MigrationCandidate] = []
        var failed: [String] = []
        await withTaskGroup(of: MigrationSearchResult.self) { group in
            for source in sources {
                group.addTask {
                    await searchOne(
                        source, query: text, titles: titles, excluding: excluded,
                        perSource: perSource, pacer: pacer)
                }
            }
            for await result in group {
                found += result.hits
                failed += result.failed
            }
        }
        return MigrationSearchResult(
            hits: found.sorted { $0.score > $1.score },
            failed: failed.sorted())
    }

    /// Sources in priority order: the first one with a confident match wins, so a
    /// preferred source is not overruled by a slightly better title elsewhere.
    /// With no confident match, the best weaker hit is returned for review.
    static func bestInPriority(
        titles: [String],
        sources: [any CatalogSource],
        excluding excluded: String?,
        pacer: MigrationPacer = .shared
    ) async -> MigrationMatch {
        var best: MigrationCandidate?
        var failed: [String] = []
        for source in sources {
            if Task.isCancelled { break }
            let result = await candidates(
                titles: titles, sources: [source], excluding: excluded, pacer: pacer)
            failed += result.failed
            guard let top = result.hits.first else { continue }
            if top.isConfident { return MigrationMatch(candidate: top, failed: failed) }
            if top.score > (best?.score ?? 0) { best = top }
        }
        return MigrationMatch(candidate: best, failed: failed)
    }

    /// Details and the full chapter list for the chosen hit, fetched together.
    ///
    /// Two requests, retried through the pacer like a search: the chapter list is
    /// the expensive half of a migration and the most likely to be throttled.
    static func load(
        _ candidate: MigrationCandidate,
        from source: any CatalogSource,
        pacer: MigrationPacer = .shared
    ) async throws -> (details: SourceEntry, chapters: [SourceChapter]) {
        while true {
            guard await pacer.isAvailable(source.key) else {
                throw MigrationError.sourceCoolingDown(source.name)
            }
            await pacer.begin(source.key)
            do {
                async let details = source.details(candidate.entry)
                async let chapters = source.chapters(candidate.entry)
                let loaded = try await (details, chapters)
                await pacer.succeeded(source.key)
                return loaded
            } catch {
                guard let wait = await pacer.failed(source.key) else { throw error }
                try? await Task.sleep(for: .seconds(wait))
                try Task.checkCancellation()
            }
        }
    }

    /// How many of the old entry's read or bookmarked chapters have a counterpart
    /// among `chapters`, for the confirmation screen.
    @MainActor
    static func previewCarry(from old: Entry, into chapters: [SourceChapter], title: String) -> MigrationOutcome {
        let incomingNumbers = Set(chapters.compactMap { chapter -> Double? in
            let number = chapter.chapterNumber > -1
                ? chapter.chapterNumber
                : ChapterRecognition.parseChapterNumber(chapter.name, mangaTitle: title)
            return number >= 0 ? number : nil
        })
        let incomingNames = Set(chapters.map { MigrationMatcher.normalize($0.name) })
        var outcome = MigrationOutcome()
        // Hidden chapters are not part of the entry, so they carry nothing.
        for chapter in old.visibleChapters where chapter.read || chapter.bookmark || chapter.progress > 0 {
            outcome.oldWithState += 1
            let hit = chapter.chapterNumber >= 0
                ? incomingNumbers.contains(chapter.chapterNumber)
                : incomingNames.contains(MigrationMatcher.normalize(chapter.name))
            if hit { outcome.carried += 1 }
        }
        return outcome
    }

    // MARK: - One source

    private static func searchOne(
        _ source: any CatalogSource,
        query: String,
        titles: [String],
        excluding excluded: String?,
        perSource: Int,
        pacer: MigrationPacer
    ) async -> MigrationSearchResult {
        while true {
            if Task.isCancelled { return MigrationSearchResult() }
            guard await pacer.isAvailable(source.key) else {
                return MigrationSearchResult(failed: [source.name])
            }
            await pacer.begin(source.key)
            do {
                let page = try await source.search(query: query, page: 1, filters: FilterState())
                await pacer.succeeded(source.key)
                let hits = page.entries.prefix(perSource).compactMap { hit -> MigrationCandidate? in
                    guard hit.id != excluded else { return nil }
                    return MigrationCandidate(
                        entry: hit,
                        sourceName: source.name,
                        score: MigrationMatcher.score(titles, hit.title))
                }
                return MigrationSearchResult(hits: hits)
            } catch {
                guard let wait = await pacer.failed(source.key) else {
                    return MigrationSearchResult(failed: [source.name])
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }
}

/// Why a migration could not be prepared.
enum MigrationError: LocalizedError {
    case sourceCoolingDown(String)
    case sourceMissing

    var errorDescription: String? {
        switch self {
        case .sourceCoolingDown(let name):
            "\(name) is not answering. Try again in a minute."
        case .sourceMissing:
            "That source is not installed."
        }
    }
}

/// The destination sources, in the order they are tried.
///
/// One preference per content kind, shared by every migration: "try MangaFire,
/// then AllManga" is a fact about the user's sources, not about one book, so a
/// choice made once applies to the next entry and the next bulk run. The list is
/// stored whole — which source a given migration may search is decided per run by
/// `destinations(for:in:excluding:)`, so editing the order while moving away from
/// a source cannot quietly drop that source from the preference.
enum MigrationSources {

    /// Saved order, falling back to every source of the kind. Sources that no
    /// longer exist are dropped.
    @MainActor
    static func ordered(for kind: ContentKind, in manager: SourceManager) -> [any CatalogSource] {
        let all = manager.sources(of: kind)
        guard let keys = MigrationSourcePreference.load(for: kind) else { return all }
        let saved = keys.compactMap { manager.source(forKey: $0) }
        return saved.isEmpty ? all : saved
    }

    /// What one migration may search: the saved order without the source it is
    /// moving away from, which can never be its own destination.
    @MainActor
    static func destinations(
        for kind: ContentKind,
        in manager: SourceManager,
        excluding sourceKey: String?
    ) -> [any CatalogSource] {
        ordered(for: kind, in: manager).filter { $0.key != sourceKey }
    }

    static func save(_ keys: [String], for kind: ContentKind) {
        MigrationSourcePreference.save(keys, for: kind)
    }
}
