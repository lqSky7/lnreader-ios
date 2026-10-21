import AVFoundation
import CoreMedia
import CryptoKit
import Foundation

/// Verifies a real downloaded package using the same Swift manifest and Apple
/// audio frameworks as the app, without a network connection or audible output.
@main struct TTSLivePackageChecks {
    static func main() async throws {
        for folder in CommandLine.arguments.dropFirst() {
            let root = URL(fileURLWithPath: folder)
            let manifest = try JSONDecoder().decode(TTSManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            try manifest.validate()
            let audio = root.appendingPathComponent("audio.m4a")
            let bytes = try Data(contentsOf: audio)
            let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            precondition(Int64(bytes.count) == manifest.audioBytes && checksum == manifest.audioSHA256)
            let asset = AVURLAsset(url: audio)
            let duration = try await asset.load(.duration).seconds
            precondition(abs(duration - manifest.duration) < 0.25)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { fatalError("Missing audio track") }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output)
            precondition(reader.startReading())
            var frames = 0
            while let sample = output.copyNextSampleBuffer() { frames += CMSampleBufferGetNumSamples(sample) }
            precondition(reader.status == .completed && frames > 0, "Downloaded AAC must fully decode offline")
            for word in manifest.words {
                precondition(manifest.time(paragraph: word.paragraphIndex, offset: word.sourceStart) != nil)
                precondition(manifest.word(at: word.start + min(0.01, (word.end - word.start) / 2)) != nil)
            }
            print("PASS: \(manifest.title), \(manifest.words.count) source-aligned words, \(frames) decoded offline audio frames, verified SHA-256")
        }
    }
}
