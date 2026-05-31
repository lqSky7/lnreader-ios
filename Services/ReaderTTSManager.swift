import AVFoundation
import Combine
import Foundation
import KokoroTTS
import SwiftUI

// MARK: - Model State

enum TTSModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double, status: String)
    case downloaded
    case loading
    case ready
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloaded: Bool {
        switch self {
        case .downloaded, .loading, .ready: return true
        default: return false
        }
    }
}

// MARK: - Model Manager

/// Manages the KokoroTTS model lifecycle: download, cache, load, delete.
@MainActor
final class TTSModelManager: ObservableObject {
    @Published var state: TTSModelState = .notDownloaded

    private var ttsModel: KokoroTTSModel?
    private var downloadTask: Task<Void, Never>?

    static let modelId = KokoroTTSModel.defaultModelId

    init() {
        checkModelStatus()
    }

    /// Check whether the model files are already cached on disk.
    func checkModelStatus() {
        guard !state.isReady else { return }
        if case .downloading = state { return }

        do {
            let cacheDir = try getCacheDirectory()
            if modelFilesExist(in: cacheDir) {
                state = .downloaded
            } else {
                state = .notDownloaded
            }
        } catch {
            state = .notDownloaded
        }
    }

    /// Download the model from HuggingFace with progress tracking.
    func downloadModel() {
        switch state {
        case .notDownloaded, .error:
            break
        default:
            return
        }

        downloadTask?.cancel()
        state = .downloading(progress: 0, status: "Starting download…")

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let model = try await KokoroTTSModel.fromPretrained(
                    progressHandler: { [weak self] progress, status in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if case .downloading = self.state {
                                self.state = .downloading(progress: progress, status: status)
                            }
                        }
                    }
                )
                // Model loaded successfully during download — go straight to ready
                self.ttsModel = model
                self.state = .ready
            } catch is CancellationError {
                self.state = .notDownloaded
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Cancel an in-progress download.
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .notDownloaded
    }

    /// Load an already-downloaded model into memory.
    func loadModel() async throws -> KokoroTTSModel {
        if let ttsModel { return ttsModel }

        state = .loading

        do {
            let model = try await KokoroTTSModel.fromPretrained(offlineMode: true)
            self.ttsModel = model
            state = .ready
            return model
        } catch {
            state = .notDownloaded
            throw error
        }
    }

    /// Delete cached model files to free storage.
    func deleteModel() {
        ttsModel = nil
        do {
            let cacheDir = try getCacheDirectory()
            try FileManager.default.removeItem(at: cacheDir)
        } catch {
            // Deletion failure is non-fatal
        }
        state = .notDownloaded
    }

    /// Dismiss an error and go back to the appropriate state.
    func dismissError() {
        checkModelStatus()
    }

    // MARK: - Private

    private func getCacheDirectory() throws -> URL {
        let fm = FileManager.default
        let cacheBase = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheBase.appendingPathComponent("qwen3-speech/models/\(Self.modelId)")
        return modelDir
    }

    private func modelFilesExist(in directory: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return false }

        // Check for the main CoreML model bundle
        let modelPath = directory.appendingPathComponent("kokoro_5s.mlmodelc")
        return fm.fileExists(atPath: modelPath.path)
    }
}

// MARK: - TTS Manager

struct TTSBatchedBlock {
    let text: String
    let originalIndices: [Int]
}

@MainActor
final class ReaderTTSManager: ObservableObject {
    static private(set) var shared: ReaderTTSManager?

    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentBlockIndex: Int? = nil
    @Published var errorMessage: String? = nil

    private let audioPlayer = TTSAudioPlayer()
    let modelManager: TTSModelManager
    private var readingTask: Task<Void, Never>?
    private var currentChapterName = ""
    private(set) var totalBlocks: Int = 0
    private var activePrefetches: [Int: Task<[Float], Error>] = [:]
    private var highlightTask: Task<Void, Never>?
    private var activeDataTasks: [Int: URLSessionDataTask] = [:]

    #if os(iOS)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(modelManager: TTSModelManager) {
        self.modelManager = modelManager
        Self.shared = self
    }

    private func startBackgroundTask() {
        #if os(iOS)
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ReaderTTSPlayback") { [weak self] in
            Task { @MainActor in
                print("⚠️ [ReaderTTSManager] Background task expired!")
                self?.stopBackgroundTask()
                self?.stop()
            }
        }
        print("🔊 [ReaderTTSManager] Background task started: \(backgroundTaskID)")
        #endif
    }

    private func stopBackgroundTask() {
        #if os(iOS)
        guard backgroundTaskID != .invalid else { return }
        let id = backgroundTaskID
        UIApplication.shared.endBackgroundTask(id)
        backgroundTaskID = .invalid
        print("🔊 [ReaderTTSManager] Background task ended: \(id)")
        #endif
    }

    nonisolated private var useRemote: Bool {
        UserDefaults.standard.bool(forKey: "tts.useRemote")
    }

    nonisolated private var remoteURL: String {
        UserDefaults.standard.string(forKey: "tts.remoteURL") ?? "https://sky788-tts.hf.space"
    }

    func startReading(
        blocks: [String],
        chapterName: String,
        voice: String,
        speed: Float,
        startBlockIndex: Int = 0
    ) {
        print("🔊 [ReaderTTSManager] startReading called. Blocks: \(blocks.count), chapter: \(chapterName), startBlockIndex: \(startBlockIndex)")
        stop()
        startBackgroundTask()

        guard !blocks.isEmpty else {
            print("⚠️ [ReaderTTSManager] blocks is empty, returning")
            errorMessage = ReaderTTSError.emptyContent.localizedDescription
            return
        }

        let remote = useRemote
        print("🔊 [ReaderTTSManager] useRemote: \(remote)")
        guard remote || modelManager.state.isDownloaded || modelManager.state.isReady else {
            print("⚠️ [ReaderTTSManager] Model is not downloaded/ready. State: \(modelManager.state)")
            errorMessage = "TTS model not downloaded. Open the TTS menu to download it."
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            isSpeaking = true
            isPaused = false
            errorMessage = nil
            currentBlockIndex = nil
        }
        currentChapterName = chapterName
        
        // Group consecutive small paragraphs together up to a character threshold
        // to reduce network overhead / latency and make speech sound more natural.
        // The first batch to be played starts small (up to 100 characters) so that the first
        // request completes extremely fast and starts playback without noticeable latency.
        var batchedBlocks: [TTSBatchedBlock] = []
        var currentText = ""
        var currentIndices: [Int] = []
        
        var hasStartedPlayingBlocks = false
        var isFirstPlayBatch = true
        
        for (index, rawText) in blocks.enumerated() {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            
            if index >= startBlockIndex {
                hasStartedPlayingBlocks = true
            }
            
            let threshold = (hasStartedPlayingBlocks && isFirstPlayBatch) ? 100 : 400
            
            if currentText.isEmpty {
                currentText = text
                currentIndices = [index]
            } else if currentText.count + text.count + 1 <= threshold {
                currentText += "\n" + text
                currentIndices.append(index)
            } else {
                batchedBlocks.append(TTSBatchedBlock(text: currentText, originalIndices: currentIndices))
                currentText = text
                currentIndices = [index]
                if hasStartedPlayingBlocks {
                    isFirstPlayBatch = false
                }
            }
        }
        if !currentText.isEmpty {
            batchedBlocks.append(TTSBatchedBlock(text: currentText, originalIndices: currentIndices))
        }

        guard !batchedBlocks.isEmpty else {
            print("⚠️ [ReaderTTSManager] batchedBlocks is empty, returning")
            errorMessage = ReaderTTSError.emptyContent.localizedDescription
            isSpeaking = false
            return
        }

        totalBlocks = blocks.count
        print("🔊 [ReaderTTSManager] Batched blocks count: \(batchedBlocks.count)")

        // Find which batch contains startBlockIndex
        var startBatchIndex = 0
        if startBlockIndex > 0 {
            if let index = batchedBlocks.firstIndex(where: { $0.originalIndices.contains(startBlockIndex) }) {
                startBatchIndex = index
            }
        }
        print("🔊 [ReaderTTSManager] Starting from batch index: \(startBatchIndex)")

        let voiceId = normalizedVoice(voice)
        let language = languageCode(for: voiceId)
        let player = audioPlayer
        let modelManager = self.modelManager

        readingTask = Task.detached { [weak self] in
            guard let self else { return }

            print("🔊 [ReaderTTSManager] readingTask detached block started. Cleaning cache…")
            // Clean old cache in the background
            await TTSAudioCache.shared.cleanOldCacheFiles()

            do {
                print("🔊 [ReaderTTSManager] Activating audio session…")
                // Activate audio session only when TTS actually starts playing
                await player.activateAudioSession()
                print("🔊 [ReaderTTSManager] Audio session activated.")
                
                var optModel: KokoroTTSModel? = nil
                if !remote {
                    print("🔊 [ReaderTTSManager] Local mode. Loading model…")
                    optModel = try await modelManager.loadModel()
                    print("🔊 [ReaderTTSManager] Local model loaded successfully.")
                }

                for batchIndex in startBatchIndex..<batchedBlocks.count {
                    let batch = batchedBlocks[batchIndex]
                    print("🔊 [ReaderTTSManager] Loop: Playing batch \(batchIndex)/\(batchedBlocks.count). Text preview: \(String(batch.text.prefix(30)))…")
                    try Task.checkCancellation()

                    // Resolve the audio samples: await prefetch if running, or synthesize on the spot if not started
                    let samples: [Float]
                    
                    let prefetchTask = await MainActor.run {
                        self.activePrefetches[batchIndex]
                    }
                    
                    if let task = prefetchTask {
                        print("🔊 [ReaderTTSManager] Batch \(batchIndex): Prefetch task found. Awaiting it…")
                        do {
                            samples = try await task.value
                            print("🔊 [ReaderTTSManager] Batch \(batchIndex): Prefetch task finished successfully. Samples count: \(samples.count)")
                        } catch {
                            print("❌ [ReaderTTSManager] Batch \(batchIndex): Prefetch task failed: \(error)")
                            await MainActor.run {
                                self.activePrefetches.removeValue(forKey: batchIndex)
                            }
                            throw error
                        }
                        await MainActor.run {
                            self.activePrefetches.removeValue(forKey: batchIndex)
                        }
                    } else {
                        print("🔊 [ReaderTTSManager] Batch \(batchIndex): No prefetch task. Resolving samples manually…")
                        // Check cache first
                        if let cached = await TTSAudioCache.shared.get(text: batch.text, voice: voiceId, speed: speed) {
                            print("🔊 [ReaderTTSManager] Batch \(batchIndex): Cache hit.")
                            samples = cached
                        } else {
                            print("🔊 [ReaderTTSManager] Batch \(batchIndex): Cache miss. Synthesizing…")
                            if remote {
                                print("🔊 [ReaderTTSManager] Batch \(batchIndex): Remote synthesizing via remote URL: \(self.remoteURL)...")
                                samples = try await self.synthesizeRemote(index: batchIndex, text: batch.text, voice: voiceId, speed: speed)
                                print("🔊 [ReaderTTSManager] Batch \(batchIndex): Remote synthesis success. Samples: \(samples.count)")
                            } else if let model = optModel {
                                print("🔊 [ReaderTTSManager] Batch \(batchIndex): Local synthesizing…")
                                samples = try model.synthesize(
                                    text: batch.text,
                                    voice: voiceId,
                                    language: language,
                                    speed: speed
                                )
                                print("🔊 [ReaderTTSManager] Batch \(batchIndex): Local synthesis success. Samples: \(samples.count)")
                            } else {
                                print("❌ [ReaderTTSManager] Batch \(batchIndex): Model not found and remote is false.")
                                throw ReaderTTSError.audioBufferFailed
                            }
                            // Save to cache
                            await TTSAudioCache.shared.set(text: batch.text, voice: voiceId, speed: speed, samples: samples)
                        }
                    }

                    // Trigger prefetching for subsequent blocks sequentially now that current block is resolved
                    await self.triggerPrefetches(
                        from: batchIndex,
                        batches: batchedBlocks,
                        voice: voice,
                        speed: speed,
                        remote: remote,
                        optModel: optModel
                    )

                    try Task.checkCancellation()
                    
                    let sampleRate = remote ? 24000.0 : Double(KokoroTTSModel.outputSampleRate)
                    let duration = Double(samples.count) / sampleRate
                    
                    // Highlight updating task based on text length weights in the batch
                    let startIndexInBatch = batch.originalIndices.contains(startBlockIndex) ? startBlockIndex : batch.originalIndices.first ?? 0
                    
                    print("🔊 [ReaderTTSManager] Batch \(batchIndex): Starting highlight task and play.")
                    await self.startHighlightTask(
                        originalIndices: batch.originalIndices,
                        originalTexts: batch.originalIndices.map { blocks[$0] },
                        duration: duration,
                        startIndex: startIndexInBatch
                    )

                    try await player.play(
                        samples: samples,
                        sampleRate: sampleRate
                    )
                    print("🔊 [ReaderTTSManager] Batch \(batchIndex): Finished playing.")
                    
                    await MainActor.run {
                        self.highlightTask?.cancel()
                        self.highlightTask = nil
                    }
                }
            } catch {
                if !(error is CancellationError) {
                    print("❌ [ReaderTTSManager] Error in reading loop: \(error)")
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                    }
                } else {
                    print("🔊 [ReaderTTSManager] Reading loop cancelled.")
                }
            }

            await MainActor.run {
                self.highlightTask?.cancel()
                self.highlightTask = nil
                self.stopBackgroundTask()
            }
            await player.deactivateAudioSession()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isSpeaking = false
                    self.isPaused = false
                    self.currentBlockIndex = nil
                }
            }
        }
    }

    nonisolated private func fetchRemoteData(for index: Int, url: URL) async throws -> (Data, URLResponse) {
        var dataTask: URLSessionDataTask?
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    } else if let data = data, let response = response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: ReaderTTSError.audioBufferFailed)
                    }
                    
                    Task { @MainActor in
                        self.activeDataTasks.removeValue(forKey: index)
                    }
                }
                
                dataTask = task
                Task { @MainActor in
                    self.activeDataTasks[index] = task
                }
                task.resume()
            }
        } onCancel: {
            dataTask?.cancel()
        }
    }



    nonisolated private func synthesizeRemote(index: Int, text: String, voice: String, speed: Float) async throws -> [Float] {
        try Task.checkCancellation()
        
        let baseURLString = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURLString = baseURLString.hasSuffix("/") ? String(baseURLString.dropLast()) : baseURLString
        
        guard let baseURL = URL(string: normalizedURLString),
              var components = URLComponents(url: baseURL.appendingPathComponent("synthesize"), resolvingAgainstBaseURL: false) else {
            throw ReaderTTSError.audioBufferFailed
        }
        
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "voice", value: voice),
            URLQueryItem(name: "speed", value: String(format: "%.2f", speed))
        ]
        
        guard let url = components.url else {
            throw ReaderTTSError.audioBufferFailed
        }
        
        let (data, response) = try await fetchRemoteData(for: index, url: url)
        
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ReaderTTSError.audioEngineFailed
        }
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("remote_tts_\(index).wav")
        if FileManager.default.fileExists(atPath: tempFile.path) {
            try? FileManager.default.removeItem(at: tempFile)
        }
        try data.write(to: tempFile)
        
        let file = try AVAudioFile(forReading: tempFile)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw ReaderTTSError.audioBufferFailed
        }
        
        try file.read(into: buffer)
        
        guard let channelData = buffer.floatChannelData else {
            throw ReaderTTSError.audioBufferFailed
        }
        
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        
        try? FileManager.default.removeItem(at: tempFile)
        return samples
    }

    private func triggerPrefetches(
        from startIndex: Int,
        batches: [TTSBatchedBlock],
        voice: String,
        speed: Float,
        remote: Bool,
        optModel: KokoroTTSModel?
    ) {
        let n = startIndex
        let minWindow = n + 1
        let maxWindow = min(batches.count - 1, n + 3)
        
        // Cancel prefetch tasks outside this window to optimize network/CPU
        let keysToRemove = activePrefetches.keys.filter { $0 < minWindow || $0 > maxWindow }
        for index in keysToRemove {
            activePrefetches[index]?.cancel()
            activePrefetches.removeValue(forKey: index)
        }

        let voiceId = normalizedVoice(voice)
        let language = languageCode(for: voiceId)
        let modelManager = self.modelManager

        guard minWindow <= maxWindow else { return }

        var previousTask: Task<[Float], Error>? = nil
        for index in minWindow...maxWindow {
            let text = batches[index].text

            if let existing = activePrefetches[index] {
                previousTask = existing
                continue
            }

            let capturedPrev = previousTask
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { throw ReaderTTSError.audioBufferFailed }
                
                // Wait for the previous prefetch to finish (or fail) before starting this one.
                // This ensures sequential request order and prevents later requests from hitting the server first.
                if let prev = capturedPrev {
                    _ = try? await prev.value
                }
                
                try Task.checkCancellation()
                
                // Check cache first
                if let cached = await TTSAudioCache.shared.get(text: text, voice: voiceId, speed: speed) {
                    return cached
                }
                
                let samples: [Float]
                if remote {
                    samples = try await self.synthesizeRemote(index: index, text: text, voice: voiceId, speed: speed)
                } else {
                    // Load model in background
                    let model = try await modelManager.loadModel()
                    samples = try model.synthesize(
                        text: text,
                        voice: voiceId,
                        language: language,
                        speed: speed
                    )
                }
                
                // Save to cache
                await TTSAudioCache.shared.set(text: text, voice: voiceId, speed: speed, samples: samples)
                return samples
            }
            activePrefetches[index] = task
            previousTask = task
        }
    }

    private func startHighlightTask(
        originalIndices: [Int],
        originalTexts: [String],
        duration: Double,
        startIndex: Int = 0
    ) {
        highlightTask?.cancel()
        
        let totalChars = originalTexts.map { $0.count }.reduce(0, +)
        
        highlightTask = Task { [weak self] in
            guard let self else { return }
            
            for (offset, origIndex) in originalIndices.enumerated() {
                if origIndex < startIndex { continue }
                try? Task.checkCancellation()
                
                // Update highlight index
                self.currentBlockIndex = origIndex
                
                let charCount = originalTexts[offset].count
                let fraction = totalChars > 0 ? (Double(charCount) / Double(totalChars)) : 1.0
                let estDuration = duration * fraction
                
                // Smooth sleep in 0.1s increments to check for pause states and respond instantly
                var elapsed: Double = 0
                while elapsed < estDuration {
                    try? Task.checkCancellation()
                    if self.isPaused {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    } else {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        elapsed += 0.1
                    }
                }
            }
        }
    }

    func togglePause() {
        guard isSpeaking else { return }
        isPaused.toggle()
        let paused = isPaused
        let player = audioPlayer
        
        Task {
            if paused {
                await player.pause()
            } else {
                await player.resume()
            }
        }
    }

    func stop() {
        readingTask?.cancel()
        readingTask = nil
        
        highlightTask?.cancel()
        highlightTask = nil
        
        // Cancel all ongoing background prefetch tasks
        for task in activePrefetches.values {
            task.cancel()
        }
        activePrefetches.removeAll()
        
        // Cancel and clear all active network tasks immediately
        for task in activeDataTasks.values {
            task.cancel()
        }
        activeDataTasks.removeAll()
        
        let player = audioPlayer
        Task {
            await player.stop()
            await player.deactivateAudioSession()
            await MainActor.run {
                self.stopBackgroundTask()
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            isSpeaking = false
            isPaused = false
            currentBlockIndex = nil
        }
    }

    nonisolated private func normalizedVoice(_ voice: String) -> String {
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? KokoroTTSModel.defaultVoice : trimmed
    }

    nonisolated private func languageCode(for voice: String) -> String {
        guard let prefix = voice.first else { return "en" }
        switch prefix {
        case "a", "b": return "en"
        case "e": return "es"
        case "f": return "fr"
        case "h": return "hi"
        case "i": return "it"
        case "j": return "ja"
        case "k": return "ko"
        case "p": return "pt"
        case "z": return "zh"
        default: return "en"
        }
    }

    private func progress(for index: Int) -> Double {
        guard totalBlocks > 0 else { return 0 }
        return Double(index + 1) / Double(totalBlocks)
    }
}

enum ReaderTTSError: LocalizedError {
    case audioBufferFailed
    case audioEngineFailed
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .audioBufferFailed:
            return "Failed to prepare audio buffer."
        case .audioEngineFailed:
            return "Failed to start audio engine."
        case .emptyContent:
            return "No readable text found for TTS."
        }
    }
}

// MARK: - Audio Player

actor TTSAudioPlayer {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let silencePlayerNode = AVAudioPlayerNode()
    private var completion: (() -> Void)?

    init() {
        audioEngine.attach(playerNode)
        audioEngine.attach(silencePlayerNode)
        // Audio session is NOT activated here — deferred to activateAudioSession()
    }

    /// Activate the audio session just before playback begins.
    /// This avoids interrupting background music when the reader opens.
    func activateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Audio session failure is non-fatal; playback will fail gracefully later.
        }
        startSilencePlayer()
        #endif
    }

    /// Deactivate the audio session so other apps can resume their audio.
    func deactivateAudioSession() {
        #if os(iOS)
        stopSilencePlayer()
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation failure is non-fatal.
        }
        #endif
    }

    private func startSilencePlayer() {
        guard let silenceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000.0, channels: 1, interleaved: false) else { return }
        let frameCount = AVAudioFrameCount(2400)
        guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: silenceFormat, frameCapacity: frameCount) else { return }
        silenceBuffer.frameLength = frameCount
        
        // Fill with zeroes
        if let channelData = silenceBuffer.floatChannelData {
            memset(channelData[0], 0, Int(frameCount) * MemoryLayout<Float>.size)
        }
        
        audioEngine.connect(silencePlayerNode, to: audioEngine.mainMixerNode, format: silenceFormat)
        
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine for silence player: \(error)")
            }
        }
        
        silencePlayerNode.scheduleBuffer(silenceBuffer, at: nil, options: .loops, completionHandler: nil)
        silencePlayerNode.play()
    }

    private func stopSilencePlayer() {
        silencePlayerNode.stop()
        audioEngine.disconnectNodeOutput(silencePlayerNode)
    }

    func play(samples: [Float], sampleRate: Double) async throws {
        guard !samples.isEmpty else { return }

        playerNode.stop()
        audioEngine.disconnectNodeOutput(playerNode)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ReaderTTSError.audioBufferFailed
        }

        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw ReaderTTSError.audioBufferFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { pointer in
                if let baseAddress = pointer.baseAddress {
                    channelData[0].update(from: baseAddress, count: samples.count)
                }
            }
        }

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                throw ReaderTTSError.audioEngineFailed
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            completion = {
                continuation.resume(returning: ())
            }

            playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task {
                    await self?.finishPlayback()
                }
            }

            playerNode.play()
        }
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        finishPlayback()
    }

    private func finishPlayback() {
        guard let completion else { return }
        self.completion = nil
        completion()
    }
}
