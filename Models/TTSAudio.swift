import Foundation

struct TTSWordTiming: Codable, Equatable, Sendable {
    let paragraphIndex: Int
    let sourceStart: Int
    let sourceEnd: Int
    let start: Double
    let end: Double
}

protocol TTSPlaybackManifest: Sendable {
    var id: String { get }
    var bookId: String { get }
    var chapterId: String { get }
    var bookTitle: String { get }
    var title: String { get }
    var position: Int { get }
    var contentRevision: String { get }
    var voiceId: String { get }
    var voiceName: String { get }
    var blocks: [String] { get }
    var words: [TTSWordTiming] { get }
    var duration: Double { get }
}

struct TTSManifest: Codable, Identifiable, TTSPlaybackManifest {
    let schema: Int
    let id: String
    let bookId: String
    let chapterId: String
    let bookTitle: String
    let title: String
    let position: Int
    let contentRevision: String
    let voiceId: String
    let voiceName: String
    let modelID: String
    let modelRevision: String
    let pipeline: String
    let duration: Double
    let sampleRate: Int
    let audioBytes: Int64
    let audioSHA256: String
    let blocks: [String]
    let words: [TTSWordTiming]
    var audioURL: String?

    func validate() throws {
        guard schema == 1, id.count == 64, id.allSatisfy(\.isHexDigit),
              ["Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice", "Qwen/Qwen3-TTS-12Hz-1.7B-Base"].contains(modelID),
              duration.isFinite, duration > 0, audioBytes > 0,
              audioSHA256.count == 64, audioSHA256.allSatisfy(\.isHexDigit),
              !blocks.isEmpty, !words.isEmpty else { throw TTSError.invalidManifest }
        var previous = 0.0
        for word in words {
            guard blocks.indices.contains(word.paragraphIndex), word.sourceStart >= 0,
                  word.sourceEnd > word.sourceStart,
                  word.sourceEnd <= blocks[word.paragraphIndex].utf16.count,
                  word.start.isFinite, word.end.isFinite,
                  word.start >= previous - 0.02, word.end >= word.start,
                  word.end <= duration + 0.05 else { throw TTSError.invalidManifest }
            previous = word.start
        }
    }

}

extension TTSPlaybackManifest {
    func word(at time: Double) -> TTSWordTiming? {
        guard time.isFinite, !words.isEmpty else { return nil }
        var low = 0, high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= time { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let word = words[low - 1]
        return time < word.end ? word : nil
    }

    func time(paragraph: Int, offset: Int) -> Double? {
        let candidates = words.filter { $0.paragraphIndex == paragraph }
        return candidates.first { $0.sourceStart <= offset && offset < $0.sourceEnd }?.start
            ?? candidates.first { $0.sourceStart >= offset }?.start
            ?? candidates.last?.start
    }
}

struct TTSRendition: Codable, Identifiable, Sendable {
    let id: String
    let voiceId: String
    let status: String
    let bookId: String
    let chapterId: String
    let bookTitle: String
    let title: String
    let position: Int
    let contentRevision: String
    let completedChunks: Int
    let totalChunks: Int
    let error: String?
    let manifestURL: String?
    var computeProvider: String? = nil
}

struct TTSComputeProvider: Decodable, Identifiable {
    let id: String
    let name: String
    let available: Bool
}

struct TTSAudioDeletion: Codable, Equatable {
    let bookId: String
    let chapterId: String
    let voiceId: String
    let backendURL: String
}

struct TTSVoice: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let speaker: String
    let nativeLanguage: String
    let description: String
    var preview: TTSRendition?
    var kind: String? = nil
    var status: String? = nil
    var sampleDuration: Double? = nil
    var referenceText: String? = nil
    var sampleSHA256: String? = nil
    var sampleBytes: Int? = nil
    var isCustom: Bool { kind == "custom" }

    static let presets: [TTSVoice] = [
        .init(id: "qwen-ryan", name: "Ryan", speaker: "Ryan", nativeLanguage: "English", description: "Dynamic, rhythmic male narrator"),
        .init(id: "qwen-aiden", name: "Aiden", speaker: "Aiden", nativeLanguage: "English", description: "Warm, clear American male narrator"),
        .init(id: "qwen-vivian", name: "Vivian", speaker: "Vivian", nativeLanguage: "Chinese", description: "Bright female voice"),
        .init(id: "qwen-serena", name: "Serena", speaker: "Serena", nativeLanguage: "Chinese", description: "Gentle, warm female voice"),
        .init(id: "qwen-uncle-fu", name: "Uncle Fu", speaker: "Uncle_Fu", nativeLanguage: "Chinese", description: "Mellow, seasoned male voice"),
        .init(id: "qwen-dylan", name: "Dylan", speaker: "Dylan", nativeLanguage: "Chinese", description: "Youthful male voice"),
        .init(id: "qwen-eric", name: "Eric", speaker: "Eric", nativeLanguage: "Chinese", description: "Bright, slightly husky male voice"),
        .init(id: "qwen-anna", name: "Anna", speaker: "Ono_Anna", nativeLanguage: "Japanese", description: "Light, expressive female voice"),
        .init(id: "qwen-sohee", name: "Sohee", speaker: "Sohee", nativeLanguage: "Korean", description: "Warm, expressive female voice")
    ]
}

struct TTSChapterRequest: Codable, Sendable {
    let bookId: String
    let bookTitle: String
    let chapterId: String
    let title: String
    let position: Int
    let blocks: [String]
}

enum TTSError: LocalizedError {
    case invalidManifest, corruptDownload, missingAudio, request(String)
    var errorDescription: String? {
        switch self {
        case .invalidManifest: "The audio timing manifest is invalid. Download this chapter again."
        case .corruptDownload: "The audio download failed verification. Your other downloads are safe."
        case .missingAudio: "Download this chapter in your selected voice before listening."
        case .request(let message): message
        }
    }
}

struct TTSDownloadRecord: Codable, Identifiable, Sendable {
    let id: String
    var rendition: TTSRendition
    var state: String
    var error: String?
    var bytesReceived: Int64 = 0
    var bytesExpected: Int64 = 0
    var isPreview: Bool = false
    var backendURL: String
    var manifest: TTSManifest?
    var transferID: String?
    var updatedAt = Date()

    var isAvailable: Bool { state == "downloaded" }
    var progress: Double {
        if isAvailable { return 1 }
        if state == "downloading", bytesExpected > 0 { return Double(bytesReceived) / Double(bytesExpected) }
        return rendition.totalChunks > 0 ? Double(rendition.completedChunks) / Double(rendition.totalChunks) : 0
    }
}

struct TTSListeningPosition: Codable {
    let renditionId: String
    let paragraph: Int
    let offset: Int
    let time: Double
}

struct TTSChapterText: Codable {
    let bookId: String
    let chapterId: String
    let contentRevision: String
    let title: String
    let position: Int
    let blocks: [String]
}

struct TTSEngineState: Decodable, Sendable {
    let status: String
    let message: String
    let updatedAt: String
    let retryAt: String?
    var needsAttention: Bool { ["paused", "unavailable", "retrying"].contains(status) }
}

struct TTSStreamPart: Codable, Sendable {
    let index: Int
    let start: Double
    let audioDuration: Double
    let pauseAfter: Double
    let bytes: Int64
    let sha256: String
    var audioURL: String?
    let format: String
    var end: Double { start + audioDuration + pauseAfter }
}

struct TTSStreamingManifest: Codable, TTSPlaybackManifest {
    let schema: Int
    let id: String
    let bookId: String
    let chapterId: String
    let bookTitle: String
    let title: String
    let position: Int
    let contentRevision: String
    let voiceId: String
    let voiceName: String
    let blocks: [String]
    let words: [TTSWordTiming]
    let duration: Double
    var parts: [TTSStreamPart]
    let totalChunks: Int
    let completedChunks: Int
    let complete: Bool
    let status: String
    let error: String?

    func validate() throws {
        guard schema == 1, id.count == 64, id.allSatisfy(\.isHexDigit), !blocks.isEmpty,
              duration.isFinite, duration >= 0, totalChunks > 0, completedChunks <= totalChunks else { throw TTSError.invalidManifest }
        var end = 0.0
        for (index, part) in parts.enumerated() {
            guard part.index == index, part.start.isFinite, abs(part.start - end) < 0.01,
                  part.audioDuration.isFinite, part.audioDuration > 0,
                  part.pauseAfter.isFinite, (0...2).contains(part.pauseAfter), part.bytes > 0,
                  ["flac", "m4a"].contains(part.format), part.sha256.count == 64, part.sha256.allSatisfy(\.isHexDigit) else { throw TTSError.invalidManifest }
            end = part.end
        }
        guard abs(end - duration) < 0.01 else { throw TTSError.invalidManifest }
        var previous = 0.0
        for word in words {
            guard blocks.indices.contains(word.paragraphIndex), word.sourceStart >= 0,
                  word.sourceEnd > word.sourceStart, word.sourceEnd <= blocks[word.paragraphIndex].utf16.count,
                  word.start.isFinite, word.end.isFinite, word.start >= previous, word.end > word.start,
                  word.end <= duration + 0.05 else { throw TTSError.invalidManifest }
            previous = word.start
        }
    }
}
