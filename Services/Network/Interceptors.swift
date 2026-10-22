// Interceptors.swift - Cross-cutting behaviour for every outgoing request.

import Foundation

// MARK: - Context

/// Everything an interceptor needs to know about who is making the request.
struct InterceptorContext: Sendable {
    /// `"ln:<id>"` / `"mihon:<id>"`, or `nil` for app-internal traffic.
    let sourceKey: String?
    /// Host of the request, pre-computed so interceptors don't re-parse URLs.
    let host: String
}

// MARK: - Protocol

/// A hook into the request pipeline.
///
/// `adapt` runs before the request leaves the app and may rewrite it (headers,
/// cookies, retargeting). `retryDelay` runs after a non-2xx response and is the
/// only place that may recover a request, e.g. by solving a Cloudflare
/// challenge and asking for a replay.
protocol HTTPInterceptor: Sendable {

    func adapt(_ request: HTTPRequest, context: InterceptorContext) async throws -> HTTPRequest

    /// - Returns: seconds to wait before replaying the request, or `nil` to let
    ///   the client give up and surface the error.
    func retryDelay(
        for request: HTTPRequest,
        response: HTTPResponse,
        attempt: Int,
        context: InterceptorContext
    ) async -> TimeInterval?
}

extension HTTPInterceptor {
    func adapt(_ request: HTTPRequest, context: InterceptorContext) async throws -> HTTPRequest {
        request
    }

    func retryDelay(
        for request: HTTPRequest,
        response: HTTPResponse,
        attempt: Int,
        context: InterceptorContext
    ) async -> TimeInterval? {
        nil
    }
}

// MARK: - User agent

/// Stamps a browser-like User-Agent on requests that don't carry one.
///
/// Sources routinely 403 a bare `URLSession` UA, and several serve different
/// markup to mobile clients, so the default mirrors Mobile Safari.
struct UserAgentInterceptor: HTTPInterceptor {

    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    var userAgent: String = UserAgentInterceptor.defaultUserAgent

    func adapt(_ request: HTTPRequest, context: InterceptorContext) async throws -> HTTPRequest {
        guard request.header("User-Agent") == nil else { return request }
        var request = request
        request.setHeader("User-Agent", userAgent)
        return request
    }
}

// MARK: - Rate limiting

/// Spaces requests out per source and per host.
///
/// Kept as a separate actor because the state is the point: a source that
/// scrapes 400 chapters in a burst must be throttled across all its concurrent
/// callers, not per call site.
actor RateLimiter {

    private var nextAllowed: [String: ContinuousClock.Instant] = [:]

    /// Reserve a slot for `key`, sleeping until it is ours.
    ///
    /// Slots are reserved in arrival order, so concurrent callers queue up
    /// instead of all waking at the same instant.
    func acquire(key: String, minimumInterval: TimeInterval) async {
        guard minimumInterval > 0 else { return }

        let now = ContinuousClock.now
        let slot = max(nextAllowed[key] ?? now, now)
        nextAllowed[key] = slot.advanced(by: .seconds(minimumInterval))

        let wait = slot - now
        if wait > .zero {
            try? await Task.sleep(for: wait)
        }
    }

    /// Drop the state for a host, e.g. when the user clears source data.
    func reset() {
        nextAllowed.removeAll()
    }
}

/// Applies `RateLimiter` to every request, keyed by source + host.
struct RateLimitInterceptor: HTTPInterceptor {

    let limiter: RateLimiter
    /// Minimum spacing between two requests to the same host for the same source.
    var minimumInterval: TimeInterval

    init(limiter: RateLimiter = RateLimiter(), minimumInterval: TimeInterval = 0.25) {
        self.limiter = limiter
        self.minimumInterval = minimumInterval
    }

    func adapt(_ request: HTTPRequest, context: InterceptorContext) async throws -> HTTPRequest {
        await limiter.acquire(
            key: "\(context.sourceKey ?? "app")|\(context.host)",
            minimumInterval: minimumInterval
        )
        return request
    }
}

// MARK: - Retry

/// Retries idempotent requests on transient failures with exponential backoff.
struct RetryInterceptor: HTTPInterceptor {

    var maxAttempts: Int = 3
    var baseDelay: TimeInterval = 2

    func retryDelay(
        for request: HTTPRequest,
        response: HTTPResponse,
        attempt: Int,
        context: InterceptorContext
    ) async -> TimeInterval? {
        guard attempt < maxAttempts else { return nil }

        // 429 and 503 often tell us exactly how long to wait.
        if let retryAfter = response.header("Retry-After"), let seconds = TimeInterval(retryAfter) {
            return min(seconds, 60)
        }

        let code = response.statusCode
        guard code == 408 || code == 429 || (500..<600).contains(code) else { return nil }
        // 501/505 are permanent.
        guard code != 501, code != 505 else { return nil }

        return baseDelay * pow(2, Double(attempt - 1))
    }
}

// MARK: - Cloudflare

/// Solves a Cloudflare interstitial and hands back the clearance cookies.
///
/// Implemented with a `WKWebView` in `WebKitCloudflareSolver`. Kept behind a
/// protocol so the pipeline can be exercised in tests without a web view.
protocol CloudflareChallengeSolving: Sendable {
    func solve(url: URL) async throws -> [HTTPCookie]
}

/// Detects a challenge, asks the solver for clearance cookies, replays once.
struct CloudflareInterceptor: HTTPInterceptor {

    var solver: (any CloudflareChallengeSolving)?

    func retryDelay(
        for request: HTTPRequest,
        response: HTTPResponse,
        attempt: Int,
        context: InterceptorContext
    ) async -> TimeInterval? {
        // One replay is enough: a second challenge means the solver failed.
        guard attempt == 1, response.looksLikeCloudflareChallenge, let solver else {
            return nil
        }
        guard let cookies = try? await solver.solve(url: request.url), !cookies.isEmpty else {
            return nil
        }
        HTTPCookieStorage.shared.setCookies(cookies, for: request.url, mainDocumentURL: nil)
        return 0.5
    }
}
