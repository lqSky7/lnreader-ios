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
        // Pinned upstream for the English source.
        1_459_635_082_044_256_286: SourceKey.makeBuiltin(id: "pornpics"),
        MihonSourceID.make(name: "Metart Hunter", lang: "all"): SourceKey.makeBuiltin(id: "metarthunter"),
    ]
}
