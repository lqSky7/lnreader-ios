// NativeSourceIDs.swift - Which persisted identifiers belong to which native source.
//
// Pure data with no dependencies, so the backup importer and its headless check can use it without
// pulling in the sources themselves.

import CryptoKit
import Foundation

// MARK: - Mihon identity

/// Mihon's source id, so a `.tachibk` backup from Mihon, Yokai or Tachimanga lands on the native port.
///
/// Upstream derives it as the first eight bytes (big endian) of `md5("<lowercased name>/<lang>/<versionId>")`
/// with the sign bit cleared. A few sources pin an id by hand instead (AllManga does).
enum MihonSourceID {

    static func make(name: String, lang: String, versionId: Int = 1) -> Int64 {
        let digest = Insecure.MD5.hash(data: Data("\(name.lowercased())/\(lang)/\(versionId)".utf8))
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Int64(bitPattern: value & 0x7FFF_FFFF_FFFF_FFFF)
    }
}

enum NativeSourceIDs {

    /// Mihon source ids a backup may carry, mapped to the `builtin:` key that replaces them.
    static let mihon: [Int64: String] = [
        MihonSourceID.make(name: "MangaFire", lang: "en"): SourceKey.makeBuiltin(id: "mangafire"),
        // Pinned upstream; it is `make(name: "allanime", lang: "en")`.
        4_709_139_914_729_853_090: SourceKey.makeBuiltin(id: "allmanga"),
        MihonSourceID.make(name: "Manhwa18", lang: "en"): SourceKey.makeBuiltin(id: "manhwa18"),
        MihonSourceID.make(name: "4KHD", lang: "all"): SourceKey.makeBuiltin(id: "fourkhd"),
        // Upstream's versionId is 2 since the site moved to HeanCms.
        MihonSourceID.make(name: "Omega Scans", lang: "en", versionId: 2): SourceKey.makeBuiltin(id: "omegascans"),
    ]

    /// Keys older builds stored, mapped to the native key. Read by `LegacySourceMigration` and
    /// `SourceKey.canonical`; delete with them.
    static let legacy: [String: String] = {
        var keys: [String: String] = [
            "mihon:all.mangafire": SourceKey.makeBuiltin(id: "mangafire"),
            "mihon:all.allmanga": SourceKey.makeBuiltin(id: "allmanga"),
            "ln:novelfire": SourceKey.makeBuiltin(id: "novelfire"),
            "ln:novelphoenix": SourceKey.makeBuiltin(id: "novelphoenix"),
            "ln:ranobes": SourceKey.makeBuiltin(id: "ranobes"),
            "ln:FWN.com": SourceKey.makeBuiltin(id: "freewebnovel"),
        ]
        // A backup restored before these sources existed stored its titles under the bare Mihon id.
        for (id, key) in mihon { keys[SourceKey.make(kind: .manga, id: String(id))] = key }
        return keys
    }()
}

extension SourceKey {
    /// The native key for one an older build stored; any other key comes back unchanged.
    /// Goes with `LegacySourceMigration`: old `.lnbk` snapshots and sync data still carry the old keys.
    static func canonical(_ key: String) -> String { NativeSourceIDs.legacy[key] ?? key }
}
