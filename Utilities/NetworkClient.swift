import Foundation

// MARK: - Errors

/// Errors that can occur during network operations.
enum NetworkError: LocalizedError {
    case invalidURL(String)
    case badStatusCode(Int)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "Invalid URL: \(url)"
        case .badStatusCode(let code):
            "Server returned status code \(code)"
        case .decodingFailed(let error):
            "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Network Client

/// A thread-safe async HTTP client for fetching data from the network.
actor NetworkClient {
    /// Shared singleton instance.
    static let shared = NetworkClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpAdditionalHeaders = [
            "User-Agent": "LNReader-iOS/1.0"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Fetch raw data from a URL.
    func fetch(url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.badStatusCode(httpResponse.statusCode)
        }

        return data
    }

    /// Fetch a URL and return the response as a UTF-8 string.
    func fetchString(url: URL) async throws -> String {
        let data = try await fetch(url: url)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NetworkError.decodingFailed(
                NSError(domain: "NetworkClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Response is not valid UTF-8"])
            )
        }
        return string
    }

    /// Fetch a URL and decode the JSON response into the specified `Decodable` type.
    func fetchJSON<T: Decodable>(url: URL) async throws -> T {
        let data = try await fetch(url: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    /// Convenience overload that accepts a URL string.
    func fetch(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        return try await fetch(url: url)
    }

    /// Convenience overload that accepts a URL string.
    func fetchString(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        return try await fetchString(url: url)
    }

    /// Convenience overload that accepts a URL string.
    func fetchJSON<T: Decodable>(urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        return try await fetchJSON(url: url)
    }
}
