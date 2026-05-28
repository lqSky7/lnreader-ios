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
            // If offline mode fails, try online (might need to re-download)
            let model = try await KokoroTTSModel.fromPretrained()
            self.ttsModel = model
            state = .ready
            return model
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
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentBlockIndex: Int? = nil
    @Published var errorMessage: String? = nil

    private let audioPlayer = TTSAudioPlayer()
    private let liveActivity = ReaderTTSLiveActivity()
    let modelManager: TTSModelManager
    private var readingTask: Task<Void, Never>?
    private var currentChapterName = ""
    private var totalBlocks: Int = 0
    private var activePrefetches: [Int: Task<[Float], Error>] = [:]
    private var highlightTask: Task<Void, Never>?
    private var activeDataTasks: [Int: URLSessionDataTask] = [:]

    init(modelManager: TTSModelManager) {
        self.modelManager = modelManager
    }

    private var useRemote: Bool {
        UserDefaults.standard.bool(forKey: "tts.useRemote")
    }

    private var remoteURL: String {
        UserDefaults.standard.string(forKey: "tts.remoteURL") ?? "https://sky788-tts.hf.space"
    }

    func startReading(
        blocks: [String],
        chapterName: String,
        novelName: String?,
        voice: String,
        speed: Float,
        startBlockIndex: Int = 0
    ) {
        stop()

        guard !blocks.isEmpty else {
            errorMessage = ReaderTTSError.emptyContent.localizedDescription
            return
        }

        let remote = useRemote
        guard remote || modelManager.state.isDownloaded || modelManager.state.isReady else {
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
            errorMessage = ReaderTTSError.emptyContent.localizedDescription
            isSpeaking = false
            return
        }

        totalBlocks = blocks.count

        // Find which batch contains startBlockIndex
        var startBatchIndex = 0
        if startBlockIndex > 0 {
            if let index = batchedBlocks.firstIndex(where: { $0.originalIndices.contains(startBlockIndex) }) {
                startBatchIndex = index
            }
        }

        readingTask = Task { [weak self] in
            guard let self else { return }

            // Clean old cache in the background
            await TTSAudioCache.shared.cleanOldCacheFiles()

            do {
                let voiceId = self.normalizedVoice(voice)
                let language = self.languageCode(for: voiceId)

                // Activate audio session only when TTS actually starts playing
                self.audioPlayer.activateAudioSession()

                await self.liveActivity.start(chapterName: chapterName, novelName: novelName)
                
                var optModel: KokoroTTSModel? = nil
                if !remote {
                    optModel = try await self.modelManager.loadModel()
                }

                for batchIndex in startBatchIndex..<batchedBlocks.count {
                    let batch = batchedBlocks[batchIndex]
                    try Task.checkCancellation()

                    // Trigger prefetching for subsequent blocks in parallel
                    self.triggerPrefetches(
                        from: batchIndex,
                        batches: batchedBlocks,
                        voice: voice,
                        speed: speed,
                        remote: remote,
                        optModel: optModel
                    )

                    // Resolve the audio samples: await prefetch if running, or synthesize on the spot if not started
                    let samples: [Float]
                    if let task = self.activePrefetches[batchIndex] {
                        do {
                            samples = try await task.value
                        } catch {
                            self.activePrefetches.removeValue(forKey: batchIndex)
                            throw error
                        }
                        self.activePrefetches.removeValue(forKey: batchIndex)
                    } else {
                        // Check cache first
                        if let cached = await TTSAudioCache.shared.get(text: batch.text, voice: voiceId, speed: speed) {
                            samples = cached
                        } else {
                            if remote {
                                samples = try await self.synthesizeRemote(index: batchIndex, text: batch.text, voice: voiceId, speed: speed)
                            } else if let model = optModel {
                                samples = try model.synthesize(
                                    text: batch.text,
                                    voice: voiceId,
                                    language: language,
                                    speed: speed
                                )
                            } else {
                                throw ReaderTTSError.audioBufferFailed
                            }
                            // Save to cache
                            await TTSAudioCache.shared.set(text: batch.text, voice: voiceId, speed: speed, samples: samples)
                        }
                    }

                    try Task.checkCancellation()
                    
                    let sampleRate = remote ? 24000.0 : Double(KokoroTTSModel.outputSampleRate)
                    let duration = Double(samples.count) / sampleRate
                    
                    // Highlight updating task based on text length weights in the batch
                    let startIndexInBatch = batch.originalIndices.contains(startBlockIndex) ? startBlockIndex : batch.originalIndices.first ?? 0
                    
                    self.startHighlightTask(
                        originalIndices: batch.originalIndices,
                        originalTexts: batch.originalIndices.map { blocks[$0] },
                        duration: duration,
                        chapterName: chapterName,
                        startIndex: startIndexInBatch
                    )

                    try await self.audioPlayer.play(
                        samples: samples,
                        sampleRate: sampleRate
                    )
                    
                    self.highlightTask?.cancel()
                    self.highlightTask = nil
                }
            } catch {
                if !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
            }

            self.highlightTask?.cancel()
            self.highlightTask = nil
            await self.liveActivity.stop()
            self.audioPlayer.deactivateAudioSession()
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isSpeaking = false
                self.isPaused = false
                self.currentBlockIndex = nil
            }
        }
    }

    private func fetchRemoteData(for index: Int, url: URL) async throws -> (Data, URLResponse) {
        var dataTask: URLSessionDataTask?
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    Task { @MainActor in
                        self.activeDataTasks.removeValue(forKey: index)
                        
                        if let error = error {
                            if (error as NSError).code == NSURLErrorCancelled {
                                continuation.resume(throwing: CancellationError())
                            } else {
                                continuation.resume(throwing: error)
                            }
                            return
                        }
                        
                        guard let data = data, let response = response else {
                            continuation.resume(throwing: ReaderTTSError.audioBufferFailed)
                            return
                        }
                        
                        continuation.resume(returning: (data, response))
                    }
                }
                
                dataTask = task
                self.activeDataTasks[index] = task
                task.resume()
            }
        } onCancel: {
            dataTask?.cancel()
        }
    }

    private func synthesizeRemote(index: Int, text: String, voice: String, speed: Float) async throws -> [Float] {
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

        for index in minWindow...maxWindow {
            let text = batches[index].text

            if activePrefetches[index] == nil {
                activePrefetches[index] = Task { [weak self] in
                    guard let self else { throw ReaderTTSError.audioBufferFailed }
                    // Check cache first
                    if let cached = await TTSAudioCache.shared.get(text: text, voice: voiceId, speed: speed) {
                        return cached
                    }
                    
                    let samples: [Float]
                    if remote {
                        samples = try await self.synthesizeRemote(index: index, text: text, voice: voiceId, speed: speed)
                    } else if let model = optModel {
                        samples = try await Task.detached(priority: .userInitiated) {
                            try model.synthesize(
                                text: text,
                                voice: voiceId,
                                language: language,
                                speed: speed
                            )
                        }.value
                    } else {
                        throw ReaderTTSError.audioBufferFailed
                    }
                    
                    // Save to cache
                    await TTSAudioCache.shared.set(text: text, voice: voiceId, speed: speed, samples: samples)
                    return samples
                }
            }
        }
    }

    private func startHighlightTask(
        originalIndices: [Int],
        originalTexts: [String],
        duration: Double,
        chapterName: String,
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
                
                // Update live activity progress dynamically
                await self.liveActivity.update(
                    chapterName: chapterName,
                    progress: self.progress(for: origIndex),
                    isPaused: self.isPaused
                )
                
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
        if isPaused {
            audioPlayer.resume()
        } else {
            audioPlayer.pause()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            isPaused.toggle()
        }
        Task {
            await liveActivity.update(
                chapterName: currentChapterName,
                progress: progress(for: currentBlockIndex ?? 0),
                isPaused: isPaused
            )
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
        
        audioPlayer.stop()
        audioPlayer.deactivateAudioSession()
        withAnimation(.easeInOut(duration: 0.3)) {
            isSpeaking = false
            isPaused = false
            currentBlockIndex = nil
        }
        Task {
            await liveActivity.stop()
        }
    }

    private func normalizedVoice(_ voice: String) -> String {
        let trimmed = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? KokoroTTSModel.defaultVoice : trimmed
    }

    private func languageCode(for voice: String) -> String {
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

final class TTSAudioPlayer {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var completion: (() -> Void)?

    init() {
        audioEngine.attach(playerNode)
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
        #endif
    }

    /// Deactivate the audio session so other apps can resume their audio.
    func deactivateAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation failure is non-fatal.
        }
        #endif
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
                DispatchQueue.main.async {
                    self?.finishPlayback()
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
