// LNPluginSource.swift - Adapts the JavaScriptCore plugin runtime to CatalogSource.
//
// The LN JS plugins stay exactly as they are: this adapter is the seam that
// lets the v2 source protocol drive them, so the whole app can move to the new
// source API before any manga source exists.

import Foundation

/// Wraps one installed LN JS plugin.
///
/// `@unchecked Sendable` is deliberate: `JSSourcePlugin` owns a `JSContext`,
/// which is not `Sendable`, but it serializes every call onto its own queue, so
/// concurrent callers are safe. This adapter adds no mutable state beyond a
/// lock-guarded cache.
final class LNPluginSource: NovelSource, @unchecked Sendable {

    private let plugin: any SourcePlugin

    /// `parseNovel` returns details *and* the chapter list, so a browse → detail
    /// → chapter-list sequence would otherwise fetch the same page twice.
    private let cacheLock = NSLock()
    private var detailCache: [String: (novel: PluginNovel, fetchedAt: Date)] = [:]
    private static let detailCacheTTL: TimeInterval = 120

    init(plugin: any SourcePlugin) {
        self.plugin = plugin
    }

    // MARK: CatalogSource

    var key: String { "ln:\(plugin.id)" }
    var kind: ContentKind { .novel }
    var name: String { plugin.name }
    var lang: String { plugin.language }
    var iconURL: String? { plugin.iconURL.isEmpty ? nil : plugin.iconURL }
    var supportsLatest: Bool { true }

    func filters() async throws -> [SourceFilter] {
        plugin.filters.map(Self.convert)
    }

    func popular(page: Int, filters: FilterState) async throws -> EntriesPage {
        let novels = try await plugin.popularNovels(
            page: page,
            showLatest: false,
            filterValues: Self.filterValues(from: filters, definitions: plugin.filters)
        )
        return EntriesPage(entries: novels.map(entry(from:)), hasNextPage: !novels.isEmpty)
    }

    func latest(page: Int, filters: FilterState) async throws -> EntriesPage {
        let novels = try await plugin.popularNovels(
            page: page,
            showLatest: true,
            filterValues: Self.filterValues(from: filters, definitions: plugin.filters)
        )
        return EntriesPage(entries: novels.map(entry(from:)), hasNextPage: !novels.isEmpty)
    }

    func search(query: String, page: Int, filters: FilterState) async throws -> EntriesPage {
        let novels = try await plugin.searchNovels(query: query, page: page)
        return EntriesPage(entries: novels.map(entry(from:)), hasNextPage: !novels.isEmpty)
    }

    func details(_ entry: SourceEntry) async throws -> SourceEntry {
        let novel = try await novel(at: entry.url)
        return self.entry(from: novel)
    }

    func chapters(_ entry: SourceEntry) async throws -> [SourceChapter] {
        let novel = try await novel(at: entry.url)
        return novel.chapters.enumerated().map { index, chapter in
            self.chapter(from: chapter, fallbackOrder: index)
        }
    }

    // MARK: NovelSource

    func chapterHTML(_ chapter: SourceChapter) async throws -> String {
        try await plugin.parseChapter(path: chapter.url)
    }

    // MARK: Detail cache

    private func novel(at url: String) async throws -> PluginNovel {
        if let cached = cachedNovel(at: url) {
            return cached
        }
        let novel = try await plugin.parseNovel(path: url)
        store(novel, at: url)
        return novel
    }

    private func cachedNovel(at url: String) -> PluginNovel? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let cached = detailCache[url],
              Date.now.timeIntervalSince(cached.fetchedAt) < Self.detailCacheTTL
        else {
            return nil
        }
        return cached.novel
    }

    private func store(_ novel: PluginNovel, at url: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        detailCache[url] = (novel, .now)
        // The cache only ever needs the entries the user just looked at.
        if detailCache.count > 8 {
            let oldest = detailCache.min { $0.value.fetchedAt < $1.value.fetchedAt }?.key
            if let oldest { detailCache.removeValue(forKey: oldest) }
        }
    }
}

// MARK: - Mapping

extension LNPluginSource {

    private func entry(from novel: PluginNovelRef) -> SourceEntry {
        SourceEntry(
            sourceKey: key,
            kind: .novel,
            url: novel.path,
            title: novel.name,
            thumbnailURL: novel.cover
        )
    }

    private func entry(from novel: PluginNovel) -> SourceEntry {
        SourceEntry(
            sourceKey: key,
            kind: .novel,
            url: novel.path,
            title: novel.name,
            thumbnailURL: novel.cover,
            author: novel.author,
            artist: novel.artist,
            description: novel.summary,
            genres: Self.splitGenres(novel.genres),
            status: EntryStatus.parse(novel.status)
        )
    }

    private func chapter(from chapter: PluginChapter, fallbackOrder: Int) -> SourceChapter {
        SourceChapter(
            url: chapter.path,
            name: chapter.name,
            chapterNumber: chapter.chapterNumber ?? -1,
            scanlator: nil,
            dateUpload: DateParsing.parse(chapter.releaseTime)
        )
    }

    /// LN plugins store genres as one comma-separated string.
    static func splitGenres(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: Filters

    /// Maps the plugin's filter model onto the app's.
    static func convert(_ filter: PluginFilter) -> SourceFilter {
        switch filter {
        case .textInput(let key, let label, let defaultValue):
            return .text(id: key, name: label, hint: nil, defaultValue: defaultValue)

        case .picker(let key, let label, let defaultValue, let options):
            return .select(
                id: key,
                name: label,
                options: options.map { FilterOption(id: $0.value, name: $0.label) },
                defaultOption: defaultValue.isEmpty ? nil : defaultValue
            )

        case .checkboxGroup(let key, let label, let defaultValues, let options):
            return .multiSelect(
                id: key,
                name: label,
                options: options.map { FilterOption(id: $0.value, name: $0.label) },
                defaultSelection: defaultValues
            )

        case .switchFilter(let key, let label, let defaultValue):
            return .checkbox(id: key, name: label, defaultValue: defaultValue)

        case .excludableCheckboxGroup(let key, let label, let include, let exclude, let options):
            return .excludable(
                id: key,
                name: label,
                options: options.map { FilterOption(id: $0.value, name: $0.label) },
                defaultIncluded: include,
                defaultExcluded: exclude
            )
        }
    }

    /// Builds the plugin's filter payload from the user's selections.
    ///
    /// Filters the user never touched are omitted rather than sent with their
    /// defaults: plugins treat an absent key as "use my default", and some of
    /// them reject a value they did not produce.
    static func filterValues(
        from state: FilterState,
        definitions: [PluginFilter]
    ) -> FilterValues {
        var values: FilterValues = [:]
        for definition in definitions {
            guard let selection = state[definition.key] else { continue }
            switch selection {
            case .text(let text):
                values[definition.key] = .text(text)
            case .option(let option):
                values[definition.key] = .picker(option)
            case .checkbox(let checked):
                values[definition.key] = .switchVal(checked)
            case .options(let selected):
                values[definition.key] = .checkbox(Array(selected))
            case .exclude(let included, let excluded):
                values[definition.key] = .excludable(
                    include: Array(included),
                    exclude: Array(excluded)
                )
            case .triState(let included, let excluded):
                values[definition.key] = .excludable(
                    include: included ? [definition.key] : [],
                    exclude: excluded ? [definition.key] : []
                )
            case .sort:
                // LN plugins have no sort filter; nothing to send.
                continue
            }
        }
        return values
    }
}
