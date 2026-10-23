import CryptoKit
import Foundation

/// Durable files live outside the evictable page cache. A manifest is published last.
enum OfflineChapters {
    struct Manifest: Codable {
        var version = 1
        let sourceKey: String
        let entryURL: String
        let chapterURL: String
        let kind: ContentKind
        let files: [String]
    }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChapterDownloads", isDirectory: true)
    }
    static func folder(sourceKey: String, entryURL: String, chapterURL: String) -> URL {
        let identity = [sourceKey, entryURL, chapterURL].map { "\($0.utf8.count):\($0)" }.joined()
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }
    static func manifest(sourceKey: String, entryURL: String, chapterURL: String) -> (Manifest, URL)? {
        let folder = folder(sourceKey: sourceKey, entryURL: entryURL, chapterURL: chapterURL)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == 1, manifest.sourceKey == sourceKey,
              manifest.entryURL == entryURL, manifest.chapterURL == chapterURL,
              !manifest.files.isEmpty,
              manifest.files.allSatisfy({ name in
                  !name.contains("/") && !name.contains("\\") && name != "." && name != ".." &&
                  ((try? folder.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]))).map {
                      $0.isRegularFile == true && $0.isSymbolicLink != true && ($0.fileSize ?? 0) > 0
                  } == true
              }) else { return nil }
        return (manifest, folder)
    }
    static func novel(sourceKey: String, entryURL: String, chapterURL: String) -> String? {
        guard let (manifest, folder) = manifest(sourceKey: sourceKey, entryURL: entryURL, chapterURL: chapterURL),
              manifest.kind == .novel, let file = manifest.files.first else { return nil }
        return try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }
    static func manga(sourceKey: String, entryURL: String, chapterURL: String) -> [SourcePage]? {
        guard let (manifest, folder) = manifest(sourceKey: sourceKey, entryURL: entryURL, chapterURL: chapterURL),
              manifest.kind == .manga else { return nil }
        return manifest.files.enumerated().map { SourcePage(index: $0.offset, url: folder.appendingPathComponent($0.element).absoluteString) }
    }
}

