// TTSAudioCache.swift
// Thread-safe persistent disk cache for TTS audio samples.

import Foundation
import CryptoKit

struct TTSAudioCache {
    static let shared = TTSAudioCache()
    
    private init() {}
    
    private func getCacheDirectory() -> URL {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let ttsCache = caches.appendingPathComponent("tts_audio_cache")
        if !fm.fileExists(atPath: ttsCache.path) {
            try? fm.createDirectory(at: ttsCache, withIntermediateDirectories: true, attributes: nil)
        }
        return ttsCache
    }
    
    private func cacheKey(text: String, voice: String, speed: Float) -> String {
        let speedStr = String(format: "%.2f", speed)
        let combined = "\(text)_\(voice)_\(speedStr)"
        let data = Data(combined.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    nonisolated func get(text: String, voice: String, speed: Float) async -> [Float]? {
        await Task.detached(priority: .userInitiated) {
            let key = self.cacheKey(text: text, voice: voice, speed: speed)
            let fileURL = self.getCacheDirectory().appendingPathComponent("\(key).bin")
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            
            let count = data.count / MemoryLayout<Float>.size
            guard count > 0 else { return nil }
            
            var samples = [Float](repeating: 0, count: count)
            _ = samples.withUnsafeMutableBytes { buffer in
                data.copyBytes(to: buffer)
            }
            return samples
        }.value
    }
    
    nonisolated func set(text: String, voice: String, speed: Float, samples: [Float]) async {
        await Task.detached(priority: .utility) {
            guard !samples.isEmpty else { return }
            let key = self.cacheKey(text: text, voice: voice, speed: speed)
            let fileURL = self.getCacheDirectory().appendingPathComponent("\(key).bin")
            
            let data = samples.withUnsafeBytes { buffer in
                Data(buffer)
            }
            try? data.write(to: fileURL)
        }.value
    }
    
    nonisolated func cleanOldCacheFiles() async {
        await Task.detached(priority: .background) {
            let fm = FileManager.default
            let dir = self.getCacheDirectory()
            guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return }
            
            let limit = Date().addingTimeInterval(-12 * 60 * 60) // 12 hours ago
            
            for url in urls {
                if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modDate = values.contentModificationDate,
                   modDate < limit {
                    try? fm.removeItem(at: url)
                }
            }
        }.value
    }
}
