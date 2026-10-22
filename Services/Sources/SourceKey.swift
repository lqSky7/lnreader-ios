// SourceKey.swift - Parsing and building the persisted source identifiers.

import Foundation

/// Helpers for the `sourceKey` strings stored on `Entry`.
///
/// The format is `<prefix>:<id>` (`"ln:readnovelfull"`, `"mihon:1234"`) and is
/// persisted in the store and in backups, so parsing lives in one place.
enum SourceKey {

    /// Reserved key for books imported from the Files app.
    static let local = "local"

    static func make(kind: ContentKind, id: String) -> String {
        "\(kind.sourceKeyPrefix):\(id)"
    }

    /// The id part of a key. Returns the key unchanged when it has no prefix,
    /// which keeps old call sites working with bare plugin ids.
    static func identifier(from key: String) -> String {
        guard let separator = key.firstIndex(of: ":") else { return key }
        return String(key[key.index(after: separator)...])
    }

    static func isLN(_ key: String) -> Bool {
        key.hasPrefix("\(ContentKind.novel.sourceKeyPrefix):")
    }

    static func isMihon(_ key: String) -> Bool {
        key.hasPrefix("\(ContentKind.manga.sourceKeyPrefix):")
    }
}
