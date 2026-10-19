import Foundation

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
        var request = URLRequest(url: try url(path))
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

    func engine() async throws -> TTSEngineState { try await request("/api/tts/engine") }

    func voices() async throws -> [TTSVoice] {
        struct Envelope: Decodable { let voices: [TTSVoice] }
        let result: Envelope = try await request("/api/tts/voices")
        return result.voices
    }
    func prepare(chapter: TTSChapterRequest, voices: [String]) async throws -> [TTSRendition] {
        struct Body: Encodable { let chapter: TTSChapterRequest; let voiceIds: [String] }
        struct Envelope: Decodable { let renditions: [TTSRendition] }
        let result: Envelope = try await request("/api/tts/preparations", method: "POST", body: JSONEncoder().encode(Body(chapter: chapter, voiceIds: voices)))
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
    func action(_ action: String, renditionId: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/api/tts/renditions/\(renditionId)/\(action)", method: "POST", body: Data("{}".utf8))
    }
}
