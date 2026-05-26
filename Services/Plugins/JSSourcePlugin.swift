import Foundation
import JavaScriptCore

// MARK: - Errors

/// Errors specific to JavaScript plugin execution.
enum PluginError: LocalizedError {
    case contextCreationFailed
    case jsEvaluationFailed(String)
    case functionNotFound(String)
    case invalidResult(String)
    case jsException(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            "Failed to create JavaScript context"
        case .jsEvaluationFailed(let detail):
            "JavaScript evaluation failed: \(detail)"
        case .functionNotFound(let name):
            "Plugin function '\(name)' not found"
        case .invalidResult(let detail):
            "Invalid result from plugin: \(detail)"
        case .jsException(let message):
            "JavaScript exception: \(message)"
        case .fetchFailed(let reason):
            "Fetch failed in JS context: \(reason)"
        }
    }
}

// MARK: - JSSourcePlugin

/// A source plugin backed by a JavaScript file executed via JavaScriptCore.
///
/// The JS plugins use CommonJS `module.exports` pattern. This class sets up
/// the JSContext with the required environment (module, require, fetch) and
/// bridges calls to the plugin's functions.
final class JSSourcePlugin: SourcePlugin {
    let id: String
    let name: String
    let iconURL: String
    let siteURL: String
    let language: String
    let version: String

    /// Serial queue ensuring all JS execution is single-threaded.
    private let jsQueue: DispatchQueue
    /// The JavaScriptCore context.
    private let context: JSContext
    /// The plugin object extracted from `module.exports`.
    private let pluginObject: JSValue

    init(
        id: String,
        name: String,
        iconURL: String,
        siteURL: String,
        language: String,
        version: String,
        jsCode: String
    ) throws {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.siteURL = siteURL
        self.language = language
        self.version = version
        self.jsQueue = DispatchQueue(label: "com.lnreader.plugin.\(id)", qos: .userInitiated)

        guard let ctx = JSContext() else {
            throw PluginError.contextCreationFailed
        }
        self.context = ctx

        // Set up the JS environment and evaluate the plugin code
        self.pluginObject = try Self.setupContext(ctx, jsCode: jsCode, pluginID: id, queue: self.jsQueue)
    }

    // MARK: - Context Setup

    /// Configure the JSContext with CommonJS environment and evaluate the plugin.
    private static func setupContext(
        _ context: JSContext,
        jsCode: String,
        pluginID: String,
        queue: DispatchQueue
    ) throws -> JSValue {
        // Install exception handler
        var lastException: String?
        context.exceptionHandler = { _, exception in
            lastException = exception?.toString()
        }

        // Set up console.log for debugging
        let consoleLog: @convention(block) (String) -> Void = { message in
            print("🔌 [\(pluginID)] \(message)")
        }
        let console = JSValue(newObjectIn: context)!
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        console.setObject(consoleLog, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        // Set up `module` and `exports`
        let module = JSValue(newObjectIn: context)!
        let exports = JSValue(newObjectIn: context)!
        module.setObject(exports, forKeyedSubscript: "exports" as NSString)
        context.setObject(module, forKeyedSubscript: "module" as NSString)
        context.setObject(exports, forKeyedSubscript: "exports" as NSString)

        // Native Storage Bridges linked to UserDefaults
        let storeSet: @convention(block) (String, String) -> Void = { key, value in
            UserDefaults.standard.set(value, forKey: "plugin_db_\(key)")
        }
        let storeGet: @convention(block) (String) -> String? = { key in
            UserDefaults.standard.string(forKey: "plugin_db_\(key)")
        }
        let storeRemove: @convention(block) (String) -> Void = { key in
            UserDefaults.standard.removeObject(forKey: "plugin_db_\(key)")
        }
        let storeGetAllKeys: @convention(block) () -> [String] = {
            let keys = UserDefaults.standard.dictionaryRepresentation().keys
            let prefix = "plugin_db_"
            return keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        
        context.setObject(storeSet, forKeyedSubscript: "_nativeStoreSet" as NSString)
        context.setObject(storeGet, forKeyedSubscript: "_nativeStoreGet" as NSString)
        context.setObject(storeRemove, forKeyedSubscript: "_nativeStoreRemove" as NSString)
        context.setObject(storeGetAllKeys, forKeyedSubscript: "_nativeStoreGetAllKeys" as NSString)

        // Native Timer Bridges
        var activeTimers = [String: DispatchWorkItem]()
        
        let setTimeout: @convention(block) (JSValue, Double) -> String = { callback, ms in
            let timerID = UUID().uuidString
            let delay = max(0, ms) / 1000.0
            
            let workItem = DispatchWorkItem { [weak callback] in
                guard let callback else { return }
                queue.async {
                    activeTimers.removeValue(forKey: timerID)
                }
                callback.call(withArguments: [])
            }
            
            queue.async {
                activeTimers[timerID] = workItem
            }
            queue.asyncAfter(deadline: .now() + delay, execute: workItem)
            
            return timerID
        }
        
        let clearTimeout: @convention(block) (String) -> Void = { timerID in
            queue.async {
                if let workItem = activeTimers[timerID] {
                    workItem.cancel()
                    activeTimers.removeValue(forKey: timerID)
                }
            }
        }
        
        context.setObject(setTimeout, forKeyedSubscript: "_nativeSetTimeout" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "_nativeClearTimeout" as NSString)

        // Expose pluginID to the JS shims context
        context.setObject(pluginID, forKeyedSubscript: "pluginID" as NSString)
        
        // Set up `fetch` — bridges to URLSession
        setupFetch(in: context, pluginID: pluginID)
        
        // Evaluate the JS library shims (Cheerio, htmlparser2, dayjs, urlencode, and libs shims)
        context.evaluateScript(PluginShims.jsCode, withSourceURL: URL(string: "plugin://shims"))
        if let exception = lastException {
            print("⚠️ [\(pluginID)] Shims setup exception: \(exception)")
            lastException = nil
        }

        // Evaluate the plugin JavaScript
        context.evaluateScript(jsCode, withSourceURL: URL(string: "plugin://\(pluginID)"))

        if let exception = lastException {
            throw PluginError.jsEvaluationFailed(exception)
        }

        // Extract the plugin from module.exports (prefer default export)
        guard let exportsObj = module.forProperty("exports"),
              !exportsObj.isUndefined,
              !exportsObj.isNull else {
            throw PluginError.jsEvaluationFailed("module.exports is empty")
        }

        if let defaultProp = exportsObj.forProperty("default"), !defaultProp.isUndefined, !defaultProp.isNull {
            return defaultProp
        }
        return exportsObj
    }

    /// Set up a synchronous `fetch` polyfill that blocks the JS thread while
    /// URLSession performs the request. This is necessary because JavaScriptCore
    /// doesn't support async/await natively.
    private static func setupFetch(in context: JSContext, pluginID: String) {
        // Create a fetch function that returns a "Response-like" promise
        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { urlString, options in
            let promiseConstructor = context.objectForKeyedSubscript("Promise")!
            let promise = promiseConstructor.construct(withArguments: [
                // executor: (resolve, reject) -> Void
                unsafeBitCast(
                    { (resolve: JSValue, reject: JSValue) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let url = URL(string: urlString) else {
                                reject.call(withArguments: ["Invalid URL: \(urlString)"])
                                return
                            }

                            var request = URLRequest(url: url)
                            request.timeoutInterval = 30

                            // Set default headers to resemble standard mobile Safari requests
                            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                            request.setValue("*/*", forHTTPHeaderField: "Accept")
                            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

                            // Apply options (method, headers, body)
                            if let opts = options, !opts.isUndefined {
                                if let method = opts.forProperty("method"), !method.isUndefined {
                                    request.httpMethod = method.toString()
                                }
                                if let headers = opts.forProperty("headers"), !headers.isUndefined {
                                    if let headerDict = headers.toDictionary() as? [String: String] {
                                        for (key, value) in headerDict {
                                            request.setValue(value, forHTTPHeaderField: key)
                                        }
                                    }
                                }
                                if let body = opts.forProperty("body"), !body.isUndefined {
                                    request.httpBody = body.toString().data(using: .utf8)
                                }
                            }

                            let semaphore = DispatchSemaphore(value: 0)
                            var responseData: Data?
                            var responseError: Error?

                            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                                responseData = data
                                responseError = error
                                semaphore.signal()
                            }
                            task.resume()
                            semaphore.wait()

                            if let error = responseError {
                                reject.call(withArguments: [error.localizedDescription])
                                return
                            }

                            // Create a Response-like object
                            let responseObj = JSValue(newObjectIn: context)!
                            let text = String(data: responseData ?? Data(), encoding: .utf8) ?? ""

                            let textFn: @convention(block) () -> JSValue = {
                                let p = context.objectForKeyedSubscript("Promise")!
                                return p.construct(withArguments: [
                                    unsafeBitCast(
                                        { (res: JSValue, _: JSValue) in
                                            res.call(withArguments: [text])
                                        } as @convention(block) (JSValue, JSValue) -> Void,
                                        to: AnyObject.self
                                    )
                                ])!
                            }

                            let jsonFn: @convention(block) () -> JSValue = {
                                let p = context.objectForKeyedSubscript("Promise")!
                                return p.construct(withArguments: [
                                    unsafeBitCast(
                                        { (res: JSValue, rej: JSValue) in
                                            context.evaluateScript("JSON.parse")?.call(
                                                withArguments: [text]
                                            ).map { res.call(withArguments: [$0]) }
                                        } as @convention(block) (JSValue, JSValue) -> Void,
                                        to: AnyObject.self
                                    )
                                ])!
                            }

                            responseObj.setObject(
                                unsafeBitCast(textFn, to: AnyObject.self),
                                forKeyedSubscript: "text" as NSString
                            )
                            responseObj.setObject(
                                unsafeBitCast(jsonFn, to: AnyObject.self),
                                forKeyedSubscript: "json" as NSString
                            )
                            responseObj.setObject(true, forKeyedSubscript: "ok" as NSString)
                            responseObj.setObject(200, forKeyedSubscript: "status" as NSString)
                            responseObj.setObject(urlString, forKeyedSubscript: "url" as NSString)

                            resolve.call(withArguments: [responseObj])
                        }
                    } as @convention(block) (JSValue, JSValue) -> Void,
                    to: AnyObject.self
                )
            ])!
            return promise
        }

        context.setObject(
            unsafeBitCast(fetchBlock, to: AnyObject.self),
            forKeyedSubscript: "fetch" as NSString
        )
    }

    // MARK: - Protocol Methods

    func popularNovels(page: Int) async throws -> [PartialNovel] {
        let defaultFilters = jsQueue.sync { [weak self] in
            self?.pluginObject.forProperty("filters")
        }

        var options: [String: Any] = ["showLatestNovels": false]
        if let defaultFilters = defaultFilters, !defaultFilters.isUndefined, !defaultFilters.isNull {
            options["filters"] = defaultFilters
        }

        let result = try await callPluginFunction(
            "popularNovels",
            args: [page, options]
        )
        return parsePartialNovels(from: result)
    }

    func searchNovels(query: String, page: Int) async throws -> [PartialNovel] {
        let result = try await callPluginFunction("searchNovels", args: [query, page])
        return parsePartialNovels(from: result)
    }

    func parseNovel(path: String) async throws -> SourceNovel {
        let result = try await callPluginFunction("parseNovel", args: [path])
        return try parseSourceNovel(from: result)
    }

    func parseChapter(path: String) async throws -> String {
        let result = try await callPluginFunction("parseChapter", args: [path])

        guard let text = result.toString(), !text.isEmpty, text != "undefined" else {
            throw PluginError.invalidResult("parseChapter returned empty or undefined")
        }

        return text
    }

    // MARK: - JS Bridge

    /// Call a function on the plugin object, handling promises automatically.
    private func callPluginFunction(_ name: String, args: [Any]) async throws -> JSValue {
        print("🔌 [\(id)] Calling function '\(name)' with args: \(args)")
        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSValue, Error>) in
                jsQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: PluginError.contextCreationFailed)
                        return
                    }

                    guard let function = self.pluginObject.forProperty(name),
                          !function.isUndefined else {
                        continuation.resume(throwing: PluginError.functionNotFound(name))
                        return
                    }

                    let result = self.pluginObject.invokeMethod(name, withArguments: args)

                    // Check for JS exception
                    if let exception = self.context.exception {
                        let message = exception.toString() ?? "Unknown JS error"
                        self.context.exception = nil
                        continuation.resume(throwing: PluginError.jsException(message))
                        return
                    }

                    guard let jsResult = result, !jsResult.isUndefined else {
                        continuation.resume(
                            throwing: PluginError.invalidResult("\(name) returned undefined")
                        )
                        return
                    }

                    // Handle Promise results
                    if Self.isPromise(jsResult) {
                        self.resolvePromise(jsResult) { resolved in
                            continuation.resume(returning: resolved)
                        } onError: { error in
                            continuation.resume(throwing: PluginError.jsException(error))
                        }
                    } else {
                        continuation.resume(returning: jsResult)
                    }
                }
            }
            print("✅ [\(id)] Function '\(name)' succeeded")
            return result
        } catch {
            print("❌ [\(id)] Function '\(name)' failed with error: \(error)")
            throw error
        }
    }

    /// Check if a JSValue is a Promise (has a `.then` method).
    private static func isPromise(_ value: JSValue) -> Bool {
        guard let then = value.forProperty("then") else { return false }
        return !then.isUndefined
    }

    /// Resolve a JS Promise by attaching `.then` and `.catch` handlers.
    private func resolvePromise(
        _ promise: JSValue,
        onSuccess: @escaping (JSValue) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let thenBlock: @convention(block) (JSValue) -> Void = { value in
            onSuccess(value)
        }

        let catchBlock: @convention(block) (JSValue) -> Void = { error in
            onError(error.toString() ?? "Unknown promise rejection")
        }

        promise.invokeMethod("then", withArguments: [
            unsafeBitCast(thenBlock, to: AnyObject.self)
        ])?.invokeMethod("catch", withArguments: [
            unsafeBitCast(catchBlock, to: AnyObject.self)
        ])
    }

    // MARK: - Result Parsing

    /// Parse a JSValue array into `[PartialNovel]`.
    private func parsePartialNovels(from value: JSValue) -> [PartialNovel] {
        guard let array = value.toArray() as? [[String: Any]] else {
            // Try to extract from a wrapper object with a "novels" key
            if let novelsValue = value.forProperty("novels"),
               let array = novelsValue.toArray() as? [[String: Any]] {
                return array.compactMap(parsePartialNovel)
            }
            return []
        }
        return array.compactMap(parsePartialNovel)
    }

    private func parsePartialNovel(from dict: [String: Any]) -> PartialNovel? {
        guard let name = dict["name"] as? String,
              let path = dict["path"] as? String else {
            return nil
        }
        return PartialNovel(
            name: name,
            path: path,
            cover: dict["cover"] as? String
        )
    }

    /// Parse a JSValue into a `SourceNovel`.
    private func parseSourceNovel(from value: JSValue) throws -> SourceNovel {
        guard let dict = value.toDictionary() as? [String: Any] else {
            throw PluginError.invalidResult("parseNovel did not return an object")
        }

        guard let name = dict["name"] as? String,
              let path = dict["path"] as? String else {
            throw PluginError.invalidResult("Novel missing required 'name' or 'path'")
        }

        let chapters: [SourceChapter]
        if let chaptersArray = dict["chapters"] as? [[String: Any]] {
            chapters = chaptersArray.compactMap(parseSourceChapter)
        } else {
            chapters = []
        }

        return SourceNovel(
            name: name,
            path: path,
            cover: dict["cover"] as? String,
            genres: dict["genres"] as? String,
            summary: dict["summary"] as? String,
            author: dict["author"] as? String,
            artist: dict["artist"] as? String,
            status: dict["status"] as? String,
            chapters: chapters,
            totalPages: dict["totalPages"] as? Int
        )
    }

    private func parseSourceChapter(from dict: [String: Any]) -> SourceChapter? {
        guard let name = dict["name"] as? String,
              let path = dict["path"] as? String else {
            return nil
        }

        let chapterNumber: Double?
        if let num = dict["chapterNumber"] as? Double {
            chapterNumber = num
        } else if let numStr = dict["chapterNumber"] as? String {
            chapterNumber = Double(numStr)
        } else {
            chapterNumber = nil
        }

        return SourceChapter(
            name: name,
            path: path,
            chapterNumber: chapterNumber,
            releaseTime: dict["releaseTime"] as? String,
            page: dict["page"] as? String
        )
    }
}
