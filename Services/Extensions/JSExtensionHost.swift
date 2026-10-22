// JSExtensionHost.swift - Runs a transpiled extension bundle in JavaScriptCore.
//
// The host provides the two things a bundle cannot do for itself: network and
// HTML parsing. Everything else — selectors, URL building, pagination — lives in
// the bundle, which is what lets a transpiler emit it mechanically.

import Foundation
import JavaScriptCore
import SwiftSoup

/// One loaded extension bundle.
///
/// Calls are serialized on a private queue: a `JSContext` must not be touched
/// from two threads, and the JS thread blocks while `http.get` runs.
final class JSExtensionHost: @unchecked Sendable {

    /// Errors surfaced to the app, all carrying the bundle's own message.
    enum HostError: LocalizedError {
        case contextUnavailable
        case missingExtension
        case missingMethod(String)
        case script(String)
        case network(String)
        case parse(String)

        var errorDescription: String? {
            switch self {
            case .contextUnavailable: "Could not start the JavaScript runtime."
            case .missingExtension: "The extension bundle did not define `extension`."
            case .missingMethod(let name): "The extension does not implement `\(name)`."
            case .script(let detail): "Extension error: \(detail)"
            case .network(let detail): "Extension request failed: \(detail)"
            case .parse(let detail): "Extension returned unreadable data: \(detail)"
            }
        }
    }

    private let context: JSContext
    private let queue = DispatchQueue(label: "com.lnreader.extension.host")
    private let client: HTTPClient
    private let sourceKey: String

    /// Parsed nodes, keyed by the handle the bundle was given.
    private var nodes: [Int: Element] = [:]
    private var nextHandle = 1

    init(bundle: String, sourceKey: String, client: HTTPClient = .shared) throws {
        guard let context = JSContext() else { throw HostError.contextUnavailable }
        self.context = context
        self.client = client
        self.sourceKey = sourceKey

        // No `exceptionHandler`: it swallows the exception and leaves
        // `context.exception` empty, which turns a script error into a vague
        // "returned nothing". We read `exception` after each call instead.

        installBridges()
        context.evaluateScript(ExtensionContract.prelude)
        context.evaluateScript(bundle)

        if let exception = context.exception {
            throw HostError.script(exception.toString() ?? "unknown")
        }
        guard let extensionObject = context.objectForKeyedSubscript("extension"),
              !extensionObject.isUndefined
        else {
            throw HostError.missingExtension
        }
    }

    // MARK: - Metadata

    /// `extension.name`, or a fallback when the bundle omits it.
    var name: String {
        queue.sync {
            context.objectForKeyedSubscript("extension")?
                .objectForKeyedSubscript("name")?.toString() ?? "Extension"
        }
    }

    var language: String {
        queue.sync {
            context.objectForKeyedSubscript("extension")?
                .objectForKeyedSubscript("lang")?.toString() ?? ""
        }
    }

    var supportsLatest: Bool {
        queue.sync {
            guard let object = context.objectForKeyedSubscript("extension") else { return false }
            let latest = object.objectForKeyedSubscript("latest")
            return latest != nil && !(latest?.isUndefined ?? true)
        }
    }

    // MARK: - Calls

    /// Invoke a bundle method and decode its JSON result.
    func call(_ method: String, _ arguments: [Any] = []) throws -> Any {
        try queue.sync {
            // Handles are only valid for the duration of one call.
            nodes.removeAll(keepingCapacity: true)
            nextHandle = 1

            guard let object = context.objectForKeyedSubscript("extension") else {
                throw HostError.missingExtension
            }
            let function = object.objectForKeyedSubscript(method)
            guard let function, !function.isUndefined else {
                throw HostError.missingMethod(method)
            }

            let value = function.call(withArguments: arguments)
            if let exception = context.exception {
                context.exception = nil
                throw HostError.script(exception.toString() ?? "unknown")
            }
            guard let value, !value.isUndefined, !value.isNull else {
                throw HostError.parse("\(method) returned nothing")
            }

            // Round-trip through JSON so Swift never has to interpret JSValues.
            guard let stringify = context.objectForKeyedSubscript("JSON")?
                .objectForKeyedSubscript("stringify"),
                  let json = stringify.call(withArguments: [value])?.toString(),
                  let data = json.data(using: .utf8)
            else {
                throw HostError.parse("\(method) returned a value that is not JSON-serialisable")
            }

            do {
                return try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
            } catch {
                throw HostError.parse(String(describing: error))
            }
        }
    }

    // MARK: - Native bridges

    private func installBridges() {
        let get: @convention(block) (String, String?) -> String = { [weak self] url, headers in
            self?.performRequest(url: url, method: "GET", body: nil, headersJSON: headers)
                ?? Self.failure("host deallocated")
        }
        let post: @convention(block) (String, String?, String?) -> String = { [weak self] url, body, headers in
            self?.performRequest(url: url, method: "POST", body: body, headersJSON: headers)
                ?? Self.failure("host deallocated")
        }

        let parse: @convention(block) (String) -> Int = { [weak self] html in
            self?.parseDocument(html) ?? 0
        }
        let select: @convention(block) (Int, String) -> String = { [weak self] handle, selector in
            self?.select(handle: handle, selector: selector) ?? "[]"
        }
        let text: @convention(block) (Int) -> String = { [weak self] handle in
            self?.text(handle: handle) ?? ""
        }
        let html: @convention(block) (Int) -> String = { [weak self] handle in
            self?.html(handle: handle) ?? ""
        }
        let attr: @convention(block) (Int, String) -> String = { [weak self] handle, name in
            self?.attribute(handle: handle, name: name) ?? ""
        }

        context.setObject(get, forKeyedSubscript: "__nativeGet" as NSString)
        context.setObject(post, forKeyedSubscript: "__nativePost" as NSString)
        context.setObject(parse, forKeyedSubscript: "__nativeParse" as NSString)
        context.setObject(select, forKeyedSubscript: "__nativeSelect" as NSString)
        context.setObject(text, forKeyedSubscript: "__nativeText" as NSString)
        context.setObject(html, forKeyedSubscript: "__nativeHTML" as NSString)
        context.setObject(attr, forKeyedSubscript: "__nativeAttr" as NSString)
    }

    /// Blocking HTTP for the JS thread.
    ///
    /// Runs on the host's private queue, not the cooperative pool, so blocking
    /// here cannot starve Swift concurrency.
    private func performRequest(
        url: String,
        method: String,
        body: String?,
        headersJSON: String?
    ) -> String {
        var headers: [String: String] = [:]
        if let headersJSON,
           let data = headersJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            headers = decoded
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()

        Task.detached(priority: .userInitiated) { [client, sourceKey] in
            defer { semaphore.signal() }
            do {
                let request = try HTTPRequest(
                    urlString: url,
                    method: method,
                    headers: headers,
                    body: body?.data(using: .utf8)
                )
                let response = try await client.send(request, sourceKey: sourceKey)
                box.value = [
                    "status": response.statusCode,
                    "url": response.url.absoluteString,
                    "body": response.text,
                ]
            } catch {
                box.value = ["error": error.localizedDescription]
            }
        }

        if semaphore.wait(timeout: .now() + 45) == .timedOut {
            return Self.failure("request timed out")
        }
        return Self.encode(box.value ?? ["error": "no response"])
    }

    // MARK: - DOM

    private func parseDocument(_ html: String) -> Int {
        do {
            let document = try SwiftSoup.parse(html)
            return store(document)
        } catch {
            return 0
        }
    }

    private func select(handle: Int, selector: String) -> String {
        guard let element = nodes[handle] else { return "[]" }
        do {
            let matches = try element.select(selector)
            let handles = matches.array().map { store($0) }
            return Self.encode(handles)
        } catch {
            return "[]"
        }
    }

    private func text(handle: Int) -> String {
        (try? nodes[handle]?.text()) ?? ""
    }

    private func html(handle: Int) -> String {
        (try? nodes[handle]?.html()) ?? ""
    }

    private func attribute(handle: Int, name: String) -> String {
        (try? nodes[handle]?.attr(name)) ?? ""
    }

    private func store(_ element: Element) -> Int {
        let handle = nextHandle
        nextHandle += 1
        nodes[handle] = element
        return handle
    }

    // MARK: - Encoding

    private static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else {
            return failure("unserialisable response")
        }
        return string
    }

    private static func failure(_ message: String) -> String {
        "{\"error\":\"\(message.replacingOccurrences(of: "\"", with: "'"))\"}"
    }
}

/// Carries the response between the detached task and the waiting JS thread.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any]?

    var value: [String: Any]? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
