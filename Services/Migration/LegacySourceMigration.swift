// LegacySourceMigration.swift - One-shot move from `ln:` / `mihon:` source keys to `builtin:`.
//
// Sources used to be JS plugins (`ln:<pluginId>`) and JS extension bundles (`mihon:<pkg>`). They are
// native now, so everything persisted under the old key has to follow: the library entries, the
// downloaded-chapter folders (their names are a hash that includes the key) and the per-series
// settings in UserDefaults. Run once at launch; delete this file, its call in `ContentView` and
// `NativeSourceIDs.legacy` after it has run on every install.

import Foundation
import SwiftData

enum LegacySourceMigration {

    private static let doneKey = "migration.nativeSources.done"

    struct Summary {
        var entriesMoved = 0
        /// Entries whose new key already exists with the same url; left on the old key.
        var entriesConflicting = 0
        var downloadsMoved = 0
        var settingsMoved = 0
        /// Titles on sources that were not ported, by old key. They stay in the library, offline-readable.
        var orphaned: [String: Int] = [:]

        var text: String {
            var lines = ["Moved \(entriesMoved) titles to the built-in sources."]
            if downloadsMoved > 0 { lines.append("Kept \(downloadsMoved) downloaded chapters.") }
            if entriesConflicting > 0 { lines.append("\(entriesConflicting) titles already existed and were left as they were.") }
            if !orphaned.isEmpty {
                let total = orphaned.values.reduce(0, +)
                let names = orphaned.keys.sorted().map { SourceKey.identifier(from: $0) }.joined(separator: ", ")
                lines.append("\(total) titles are on sources that are no longer available (\(names)). They stay in the library and downloaded chapters still open.")
            }
            return lines.joined(separator: "\n")
        }
    }

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// Runs the migration the first time; later launches return `nil` immediately.
    @MainActor
    static func runIfNeeded(context: ModelContext) -> Summary? {
        guard !isDone else { return nil }
        let map = NativeSourceIDs.legacy
        var summary = Summary()

        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        var taken = Set(entries.map { "\($0.sourceKey)\u{0}\($0.url)" })
        for entry in entries {
            guard let target = map[entry.sourceKey] else {
                if isLegacy(entry.sourceKey) { summary.orphaned[entry.sourceKey, default: 0] += 1 }
                continue
            }
            let identity = "\(target)\u{0}\(entry.url)"
            if taken.contains(identity) {
                summary.entriesConflicting += 1
                continue
            }
            taken.remove("\(entry.sourceKey)\u{0}\(entry.url)")
            taken.insert(identity)
            entry.sourceKey = target
            summary.entriesMoved += 1
        }
        do { try context.save() } catch {
            // Nothing is marked done, so the next launch tries again.
            print("⚠️ Source migration could not save: \(error)")
            return nil
        }

        summary.downloadsMoved = moveDownloads(map)
        summary.settingsMoved = moveSettings(map)

        UserDefaults.standard.set(true, forKey: doneKey)
        return summary
    }

    private static func isLegacy(_ key: String) -> Bool { SourceKey.isLN(key) || SourceKey.isMihon(key) }

    // MARK: Downloads

    /// Re-home each chapter folder: the folder name hashes the source key, so the key change alone
    /// would orphan every downloaded chapter.
    private static func moveDownloads(_ map: [String: String]) -> Int {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: OfflineChapters.root, includingPropertiesForKeys: nil
        ) else { return 0 }

        var moved = 0
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let old = try? JSONDecoder().decode(OfflineChapters.Manifest.self, from: data),
                  let target = map[old.sourceKey]
            else { continue }

            let destination = OfflineChapters.folder(sourceKey: target, entryURL: old.entryURL, chapterURL: old.chapterURL)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }

            var updated = OfflineChapters.Manifest(
                sourceKey: target, entryURL: old.entryURL, chapterURL: old.chapterURL,
                kind: old.kind, files: old.files
            )
            updated.version = old.version
            guard let encoded = try? JSONEncoder().encode(updated),
                  (try? fileManager.moveItem(at: folder, to: destination)) != nil
            else { continue }
            try? encoded.write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
            moved += 1
        }
        return moved
    }

    // MARK: Settings

    /// Scanlator rules and per-series reader overrides are keyed `<prefix>.<sourceKey>::<url>`.
    private static func moveSettings(_ map: [String: String]) -> Int {
        let defaults = UserDefaults.standard
        var moved = 0
        for (name, value) in defaults.dictionaryRepresentation() {
            for prefix in ["scanlators.", "mangareader."] where name.hasPrefix(prefix) {
                let rest = String(name.dropFirst(prefix.count))
                guard let separator = rest.range(of: "::"),
                      let target = map[String(rest[..<separator.lowerBound])]
                else { continue }
                let renamed = prefix + target + rest[separator.lowerBound...]
                if defaults.object(forKey: renamed) == nil { defaults.set(value, forKey: renamed) }
                defaults.removeObject(forKey: name)
                moved += 1
            }
        }
        return moved
    }
}
