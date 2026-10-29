// EntryMigration.swift - Move an entry to another source, keeping what the user did.
//
// Three parts. `MigrationMatcher` decides whether a search hit is the same series
// (titles only, because that is all every source gives back from a search).
// `MigrationBackoff` and `MigrationPacer` decide how often a bulk run may ask a
// source the same question before it gives up on it.
// `EntryMigrator` builds the new entry and carries reading state across by
// chapter number, never by URL: the two sources share no URLs.

import Foundation
import SwiftData

// MARK: - Matching

enum MigrationMatcher {

    /// A hit at or above this is picked without asking in a bulk migration.
    static let autoAcceptScore = 0.85

    /// Lowercased, accents and punctuation gone, whitespace collapsed.
    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let letters = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// 0...1. Equal titles score 1; otherwise the shared share of words, so
    /// "Solo Leveling" against "Solo Leveling (Novel)" is high and
    /// "Solo Leveling" against "Solo Max-Level Newbie" is not.
    static func score(_ wanted: String, _ candidate: String) -> Double {
        let lhs = normalize(wanted), rhs = normalize(candidate)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }
        let a = Set(lhs.split(separator: " ")), b = Set(rhs.split(separator: " "))
        let shared = Double(a.intersection(b).count)
        guard shared > 0 else { return 0 }
        // Dice coefficient, capped under 1 so only an equal title is "exact".
        return min(0.99, 2 * shared / Double(a.count + b.count))
    }

    /// Best score across the entry's title and any alternative titles.
    static func score(_ titles: [String], _ candidate: String) -> Double {
        titles.map { score($0, candidate) }.max() ?? 0
    }

    /// The best-scoring result, with its score.
    static func best(for titles: [String], in results: [SourceEntry]) -> (entry: SourceEntry, score: Double)? {
        results
            .map { (entry: $0, score: score(titles, $0.title)) }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }
    }
}

// MARK: - Pacing

/// How long to wait before trying a source again, and when to stop.
///
/// A bulk migration asks one question per entry, so a source that is down or
/// throttling would otherwise be asked dozens of times in a row. The waits grow
/// exponentially (`base`, `2 × base`, `4 × base`, …) and are capped, so a run
/// neither hammers a struggling site nor stalls for minutes on it.
struct MigrationBackoff: Equatable, Sendable {

    /// Wait after the first failure.
    var base: TimeInterval = 1.5
    /// Ceiling for any single wait, including jitter.
    var cap: TimeInterval = 20
    /// Tries per source per entry, the first one included.
    var maxAttempts: Int = 3
    /// How long a source is left alone once it has used up `maxAttempts`.
    /// Later entries skip it instead of each burning three waits of their own.
    var rest: TimeInterval = 45

    /// Wait before the next try. `attempt` is 1-based: the delay after the
    /// first failure is `base`.
    ///
    /// `jitter` is a fraction in `-0.5...0.5` that spreads retries out, so a
    /// bulk run does not send every source its retry at the same instant.
    func delay(afterAttempt attempt: Int, jitter: Double = 0) -> TimeInterval {
        let step = pow(2, Double(max(0, attempt - 1)))
        let grown = min(cap, base * step)
        let spread = grown * (1 + min(0.5, max(-0.5, jitter)))
        return min(cap, max(0, spread))
    }

    /// Whether another try is allowed after `attempt` tries have failed.
    func canRetry(afterAttempt attempt: Int) -> Bool { attempt < maxAttempts }
}

/// Keeps a bulk run polite: one search at a time per source, spaced out, with
/// backoff on failure and a cool-down for a source that will not answer.
///
/// Shared for the whole app, so a burst of searches — a bulk run, or someone
/// typing in the picker's search field — queues behind the same per-source
/// spacing instead of each caller keeping its own schedule.
actor MigrationPacer {

    static let shared = MigrationPacer()

    private let backoff: MigrationBackoff
    /// Minimum gap between two searches sent to the same source.
    private let spacing: TimeInterval

    private var nextSlot: [String: ContinuousClock.Instant] = [:]
    private var failures: [String: Int] = [:]
    private var restingUntil: [String: ContinuousClock.Instant] = [:]

    init(backoff: MigrationBackoff = MigrationBackoff(), spacing: TimeInterval = 1.2) {
        self.backoff = backoff
        self.spacing = spacing
    }

    /// Whether the source may be asked anything right now. False while it is
    /// cooling down, so a caller can skip it without waiting.
    func isAvailable(_ sourceKey: String) -> Bool {
        guard let until = restingUntil[sourceKey] else { return true }
        guard ContinuousClock.now >= until else { return false }
        restingUntil[sourceKey] = nil
        failures[sourceKey] = 0
        return true
    }

    /// Wait for this source's next slot. Slots are reserved on arrival, so
    /// concurrent callers queue up instead of all waking together.
    func begin(_ sourceKey: String) async {
        guard spacing > 0 else { return }
        let now = ContinuousClock.now
        let slot = max(nextSlot[sourceKey] ?? now, now)
        nextSlot[sourceKey] = slot.advanced(by: .seconds(spacing))
        let wait = slot - now
        if wait > .zero { try? await Task.sleep(for: wait) }
    }

    /// Record a failed search.
    ///
    /// - Returns: seconds to wait before trying again, or `nil` when this source
    ///   has used up its tries and should be skipped for a while.
    func failed(_ sourceKey: String) -> TimeInterval? {
        let attempt = (failures[sourceKey] ?? 0) + 1
        failures[sourceKey] = attempt
        guard backoff.canRetry(afterAttempt: attempt) else {
            restingUntil[sourceKey] = ContinuousClock.now.advanced(by: .seconds(backoff.rest))
            failures[sourceKey] = 0
            return nil
        }
        // Real jitter, not a fixed ladder: two entries that failed at the same
        // moment should not retry at the same moment.
        return backoff.delay(afterAttempt: attempt, jitter: Double.random(in: -0.15...0.15))
    }

    /// The source answered, so it starts from a clean slate.
    func succeeded(_ sourceKey: String) {
        failures[sourceKey] = 0
        restingUntil[sourceKey] = nil
    }

    /// Forget every failure, e.g. when the user starts a run by hand again.
    func reset() {
        nextSlot.removeAll()
        failures.removeAll()
        restingUntil.removeAll()
    }
}

// MARK: - Destination preference

/// The saved destination order for one content kind.
///
/// Shared by every migration of that kind — one entry or a whole source — so a
/// choice made once sticks: sources the user unticked stay unticked next time.
/// Kept here rather than next to the UI so the round-trip can be checked without
/// a source registry.
enum MigrationSourcePreference {

    /// One key per kind: novels and manga are separate catalogues and separate
    /// choices.
    static func key(for kind: ContentKind) -> String { "migration.sources.\(kind.rawValue)" }

    /// `nil` when the user has never chosen, which means "every source".
    static func load(for kind: ContentKind, defaults: UserDefaults = .standard) -> [String]? {
        defaults.stringArray(forKey: key(for: kind))
    }

    /// Store the order whole. An empty list is not a preference, so it is ignored
    /// and the next migration starts from every source again.
    static func save(_ keys: [String], for kind: ContentKind, defaults: UserDefaults = .standard) {
        guard !keys.isEmpty else { return }
        defaults.set(keys, forKey: key(for: kind))
    }
}

// MARK: - Options and outcome

struct MigrationOptions: Equatable {
    var carryProgress = true
    var carryCategories = true
    var carryTracking = true
    /// The old entry always leaves the library; its chapters and history stay on
    /// disk (as with Remove). This also deletes its downloaded chapters.
    var deleteOldDownloads = false
}

struct MigrationOutcome: Equatable {
    /// Chapters in the old entry the user had read or bookmarked.
    var oldWithState = 0
    /// Of those, how many found a chapter in the new source.
    var carried = 0

    var missed: Int { oldWithState - carried }
}

// MARK: - Migrating

@MainActor
enum EntryMigrator {

    /// Copy read state, bookmarks, position and history from `old` to the chapter
    /// of the same number in `new`. A chapter already read in `new` stays read.
    @discardableResult
    static func carryProgress(from old: Entry, to new: Entry, context: ModelContext) -> MigrationOutcome {
        var outcome = MigrationOutcome()
        // A hidden chapter does not exist (AGENTS.md), so it carries nothing.
        let stateful = old.visibleChapters.filter(hasState)
        outcome.oldWithState = stateful.count
        guard !stateful.isEmpty else { return outcome }

        // Numbered chapters match by number; unnumbered ones by name.
        var byNumber: [Double: Chapter] = [:]
        var byName: [String: Chapter] = [:]
        for chapter in stateful {
            if chapter.chapterNumber >= 0 {
                if let held = byNumber[chapter.chapterNumber], !isFurther(chapter, than: held) { continue }
                byNumber[chapter.chapterNumber] = chapter
            } else {
                byName[MigrationMatcher.normalize(chapter.name)] = chapter
            }
        }

        var hit = Set<String>()
        for chapter in new.visibleChapters {
            let key = chapter.chapterNumber >= 0
                ? "n:\(chapter.chapterNumber)"
                : "s:\(MigrationMatcher.normalize(chapter.name))"
            let source = chapter.chapterNumber >= 0
                ? byNumber[chapter.chapterNumber]
                : byName[MigrationMatcher.normalize(chapter.name)]
            guard let source else { continue }
            hit.insert(key)
            copy(source, to: chapter, context: context)
        }
        // A chapter is carried when its number (or name) landed somewhere.
        outcome.carried = stateful.count {
            hit.contains($0.chapterNumber >= 0 ? "n:\($0.chapterNumber)" : "s:\(MigrationMatcher.normalize($0.name))")
        }
        return outcome
    }

    private static func hasState(_ chapter: Chapter) -> Bool {
        chapter.read || chapter.bookmark || chapter.progress > 0 || chapter.history != nil
    }

    /// Of two same-numbered chapters, the one with more to carry.
    private static func isFurther(_ lhs: Chapter, than rhs: Chapter) -> Bool {
        if lhs.read != rhs.read { return lhs.read }
        return lhs.progress > rhs.progress
    }

    private static func copy(_ old: Chapter, to new: Chapter, context: ModelContext) {
        if old.read { new.read = true }
        if old.bookmark { new.bookmark = true }
        if !new.read || old.read {
            new.progress = max(new.progress, old.progress)
            if new.lastPageRead == 0 { new.lastPageRead = old.lastPageRead }
            if new.pagesLeft == 0 { new.pagesLeft = old.pagesLeft }
            if new.paragraphIndex == nil { new.paragraphIndex = old.paragraphIndex }
        }
        if let history = old.history, new.history == nil {
            let carried = History(chapterURL: new.url, lastRead: history.lastRead)
            carried.timeRead = history.timeRead
            carried.chapter = new
            context.insert(carried)
        }
    }

    /// Per-series manga settings live in UserDefaults under the entry's own key.
    static func copyReaderOverrides(from old: Entry, to new: Entry) {
        let defaults = UserDefaults.standard
        let oldKey = "mangareader.\(old.sourceKey)::\(old.url)"
        guard let data = defaults.data(forKey: oldKey) else { return }
        defaults.set(data, forKey: "mangareader.\(new.sourceKey)::\(new.url)")
    }
}
