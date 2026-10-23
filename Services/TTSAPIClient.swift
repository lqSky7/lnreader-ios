import Foundation

struct TTSVoiceCatalogue: Decodable, Sendable {
    struct DefaultVoice: Decodable, Sendable { let voiceId: String; let revision: String }
    let voices: [TTSVoice]
    let defaultVoice: DefaultVoice?
}

struct TTSAPIClient: Sendable {
    let baseURL: URL
    init(backendURL: String? = nil) {
        let configured = backendURL ?? UserDefaults.standard.string(forKey: "sync.backendURL") ?? "https://lnreader.traverses.dpdns.org"
        baseURL = URL(string: configured.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "https://lnreader.traverses.dpdns.org")!
    }

    func url(_ path: String) throws -> URL {
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              resolved.host == baseURL.host, resolved.scheme == baseURL.scheme,
              resolved.port == baseURL.port else { throw TTSError.request("Invalid audio download URL") }
        return resolved
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        var request = URLRequest(url: try url(path), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw TTSError.request(message ?? "The audio server is unavailable. Downloaded chapters still play offline.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    var selectedProvider: String { UserDefaults.standard.string(forKey: "tts.provider") == "colab" ? "colab" : "kaggle" }
    func engine() async throws -> TTSEngineState { try await request("/api/tts/engine?provider=\(selectedProvider)") }
    func providers() async throws -> [TTSComputeProvider] {
        struct Envelope: Decodable { let providers: [TTSComputeProvider] }
        let result: Envelope = try await request("/api/tts/providers")
        return result.providers
    }

    func voices() async throws -> [TTSVoice] {
        try await voiceCatalogue().voices
    }
    func voiceCatalogue() async throws -> TTSVoiceCatalogue { try await request("/api/tts/voices") }
    func createVoice(name: String, audio: Data, transcript: String) async throws -> TTSVoice {
        struct Body: Encodable { let name: String; let audioBase64: String; let transcript: String; let provider: String }
        struct Response: Decodable { let voice: TTSVoice }
        let result: Response = try await request("/api/tts/voices/custom", method: "POST", body: JSONEncoder().encode(Body(name: name, audioBase64: audio.base64EncodedString(), transcript: transcript, provider: selectedProvider)))
        return result.voice
    }
    func deleteVoice(_ id: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/api/tts/voices/\(id)", method: "DELETE")
    }
    func restoreVoice(_ id: String, audio: Data) async throws {
        struct Body: Encodable { let audioBase64: String }
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/api/tts/voices/\(id)/reference", method: "PUT", body: JSONEncoder().encode(Body(audioBase64: audio.base64EncodedString())))
    }
    func deletePreparations(_ scopes: [TTSAudioDeletion]) async throws {
        struct Body: Encodable { let scopes: [TTSAudioDeletion] }
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/api/tts/deletions", method: "POST", body: JSONEncoder().encode(Body(scopes: scopes)))
    }
    func voiceReference(_ id: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url("/api/tts/voices/\(id)/reference"))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 6_000_000 else { throw TTSError.request("Could not save the voice reference on this phone. Try refreshing voices.") }
        return data
    }
    func prepare(chapter: TTSChapterRequest, voices: [String]) async throws -> [TTSRendition] {
        struct Body: Encodable { let chapter: TTSChapterRequest; let voiceIds: [String]; let provider: String }
        struct Envelope: Decodable { let renditions: [TTSRendition] }
        let result: Envelope = try await request("/api/tts/preparations", method: "POST", body: JSONEncoder().encode(Body(chapter: chapter, voiceIds: voices, provider: selectedProvider)))
        return result.renditions
    }
    func renditions(bookId: String, chapterId: String? = nil) async throws -> [TTSRendition] {
        struct Envelope: Decodable { let renditions: [TTSRendition] }
        var components = URLComponents()
        components.path = "/api/tts/renditions"
        components.queryItems = [URLQueryItem(name: "bookId", value: bookId)]
        if let chapterId { components.queryItems?.append(URLQueryItem(name: "chapterId", value: chapterId)) }
        let result: Envelope = try await request(components.string!)
        return result.renditions
    }
    func manifest(_ rendition: TTSRendition) async throws -> TTSManifest {
        let result: TTSManifest = try await request("/api/tts/renditions/\(rendition.id)/manifest")
        try result.validate()
        guard result.id == rendition.id, result.voiceId == rendition.voiceId,
              result.contentRevision == rendition.contentRevision else { throw TTSError.invalidManifest }
        return result
    }
    func stream(_ rendition: TTSRendition) async throws -> TTSStreamingManifest {
        let result: TTSStreamingManifest = try await request("/api/tts/renditions/\(rendition.id)/stream")
        try result.validate()
        guard result.id == rendition.id, result.voiceId == rendition.voiceId,
              result.contentRevision == rendition.contentRevision else { throw TTSError.invalidManifest }
        return result
    }
    func action(_ action: String, renditionId: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let body = action == "retry" ? try JSONSerialization.data(withJSONObject: ["provider": selectedProvider]) : Data("{}".utf8)
        let _: Response = try await request("/api/tts/renditions/\(renditionId)/\(action)", method: "POST", body: body)
    }
}
