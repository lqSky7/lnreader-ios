// HTTPClient.swift - The single HTTP entry point for every source.
//
// LN JS plugins, Mihon extensions, image loaders and the backup uploader all go
// through here, so UA spoofing, cookies, rate limiting and Cloudflare handling
// are implemented once instead of per source.

import Foundation

/// An interceptor-driven HTTP client.
///
/// An actor rather than a class: the interceptor list is mutable (the Cloudflare
/// solver is installed after launch) and the request path is shared by every
/// source thread.
actor HTTPClient {

    // MARK: Configuration

    struct Configuration: Sendable {
        /// Per-request timeout, unless the request overrides it.
        var timeout: TimeInterval = 30
        /// Ceiling for a whole transfer, including retries of large bodies.
        var resourceTimeout: TimeInterval = 120
        /// Total tries per request, including the first one.
        var maxAttempts: Int = 3
        /// Connections to one host. Sources are serialized per source anyway.
        var maxConnectionsPerHost: Int = 6
        /// Disk/memory cache for covers and plugin JS.
        var memoryCacheBytes: Int = 8 * 1024 * 1024
        var diskCacheBytes: Int = 64 * 1024 * 1024

        static let `default` = Configuration()
    }

    // MARK: State

    static let shared = HTTPClient()

    private let configuration: Configuration
    private let session: URLSession
    private var interceptors: [any HTTPInterceptor]

    init(
        configuration: Configuration = .default,
        interceptors: [any HTTPInterceptor]? = nil
    ) {
        self.configuration = configuration
        self.interceptors = interceptors ?? HTTPClient.makeDefaultInterceptors()

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
        sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
        sessionConfiguration.httpMaximumConnectionsPerHost = configuration.maxConnectionsPerHost
        sessionConfiguration.httpShouldSetCookies = true
        sessionConfiguration.httpCookieAcceptPolicy = .always
        // One cookie jar for the whole app; the WKWebView login flows write into
        // the same `HTTPCookieStorage.shared`.
        sessionConfiguration.httpCookieStorage = .shared
        sessionConfiguration.urlCache = URLCache(
            memoryCapacity: configuration.memoryCacheBytes,
            diskCapacity: configuration.diskCacheBytes
        )
        sessionConfiguration.requestCachePolicy = .reloadRevalidatingCacheData
        sessionConfiguration.waitsForConnectivity = true
        self.session = URLSession(configuration: sessionConfiguration)
    }

    private static func makeDefaultInterceptors() -> [any HTTPInterceptor] {
        [
            UserAgentInterceptor(),
            RateLimitInterceptor(),
            CloudflareInterceptor(),
            RetryInterceptor(),
        ]
    }

    // MARK: Interceptor management

    /// Install the web-view backed Cloudflare solver.
    ///
    /// Called once at launch, from the main actor, because the solver owns a
    /// `WKWebView`.
    func setCloudflareSolver(_ solver: any CloudflareChallengeSolving) {
        interceptors = interceptors.map { interceptor in
            guard var cloudflare = interceptor as? CloudflareInterceptor else {
                return interceptor
            }
            cloudflare.solver = solver
            return cloudflare
        }
    }

    // MARK: Requests

    /// Send a request through the interceptor chain.
    ///
    /// - Parameter sourceKey: `"ln:<id>"` / `"mihon:<id>"`, used for per-source
    ///   rate limits. Pass `nil` for app-internal traffic.
    func send(_ request: HTTPRequest, sourceKey: String? = nil) async throws -> HTTPResponse {
        let context = InterceptorContext(sourceKey: sourceKey, host: request.host)
        var attempt = 0

        while true {
            attempt += 1
            let adapted = try await adapt(request, context: context)

            switch await perform(adapted) {
            case .success(let response) where response.isSuccess:
                return response

            case .success(let response):
                if attempt < configuration.maxAttempts,
                   let delay = await retryDelay(
                       request: adapted, response: response, attempt: attempt, context: context
                   ) {
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw HTTPError.badStatus(
                    code: response.statusCode,
                    url: adapted.url.absoluteString
                )

            case .failure(let error):
                guard error.isRetryable, attempt < configuration.maxAttempts else {
                    throw error
                }
                // Transport failures get a plain exponential backoff; there is
                // no server response to ask for a Retry-After.
                try? await Task.sleep(for: .seconds(pow(2, Double(attempt - 1))))
            }
        }
    }

    /// Convenience for the common "GET a page as text" call.
    func getString(
        _ urlString: String,
        headers: [String: String] = [:],
        sourceKey: String? = nil
    ) async throws -> String {
        try await send(
            HTTPRequest(urlString: urlString, headers: headers),
            sourceKey: sourceKey
        ).text
    }

    func get(
        _ urlString: String,
        headers: [String: String] = [:],
        sourceKey: String? = nil
    ) async throws -> HTTPResponse {
        try await send(
            HTTPRequest(urlString: urlString, headers: headers),
            sourceKey: sourceKey
        )
    }

    func getJSON<T: Decodable>(
        _ urlString: String,
        headers: [String: String] = [:],
        sourceKey: String? = nil
    ) async throws -> T {
        try await get(urlString, headers: headers, sourceKey: sourceKey).decoded(T.self)
    }

    // MARK: Pipeline stages

    private func adapt(
        _ request: HTTPRequest,
        context: InterceptorContext
    ) async throws -> HTTPRequest {
        var adapted = request
        for interceptor in interceptors {
            adapted = try await interceptor.adapt(adapted, context: context)
        }
        return adapted
    }

    /// First interceptor that knows how to recover wins.
    private func retryDelay(
        request: HTTPRequest,
        response: HTTPResponse,
        attempt: Int,
        context: InterceptorContext
    ) async -> TimeInterval? {
        for interceptor in interceptors {
            if let delay = await interceptor.retryDelay(
                for: request, response: response, attempt: attempt, context: context
            ) {
                return delay
            }
        }
        return nil
    }

    private func perform(_ request: HTTPRequest) async -> Result<HTTPResponse, HTTPError> {
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: request.timeout ?? configuration.timeout
        )
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transport("Response was not HTTP"))
            }
            var headers: [String: String] = [:]
            headers.reserveCapacity(http.allHeaderFields.count)
            for (name, value) in http.allHeaderFields {
                headers["\(name)"] = "\(value)"
            }
            return .success(
                HTTPResponse(
                    request: request,
                    url: http.url ?? request.url,
                    statusCode: http.statusCode,
                    headers: headers,
                    data: data
                )
            )
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}
