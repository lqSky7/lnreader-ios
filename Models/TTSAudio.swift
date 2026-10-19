import Foundation

struct TTSWordTiming: Codable, Equatable, Sendable {
    let paragraphIndex: Int
    let sourceStart: Int
    let sourceEnd: Int
    let start: Double
    let end: Double
}

struct TTSManifest: Codable, Identifiable, Sendable {
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
              modelID == "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
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

    func word(at time: Double) -> TTSWordTiming? {
        guard !words.isEmpty else { return nil }
        var low = 0, high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= time { low = middle + 1 } else { high = middle }
        }
        return words[max(0, low - 1)]
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
}

struct TTSVoice: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let speaker: String
    let nativeLanguage: String
    let description: String
    var preview: TTSRendition?

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
