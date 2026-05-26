import CryptoKit
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
/// the JSContext with the required environment (module, require, fetch, crypto) and
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

    // MARK: Eagerly-parsed plugin capabilities

    private let _filters: [PluginFilter]
    private let _imageRequestInit: ImageRequestInit
    private let _webStorageUtilized: Bool
    private let _pluginSettings: [PluginSetting]
    private let _hasParsePage: Bool

    // MARK: Protocol extension overrides

    var filters: [PluginFilter] { _filters }
    var imageRequestInit: ImageRequestInit { _imageRequestInit }
    var webStorageUtilized: Bool { _webStorageUtilized }
    var pluginSettings: [PluginSetting] { _pluginSettings }
    var hasParsePage: Bool { _hasParsePage }

    // MARK: - Init

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

        // Set up the JS environment and evaluate the plugin code.
        self.pluginObject = try Self.setupContext(
            ctx, jsCode: jsCode, pluginID: id, queue: self.jsQueue)

        // Capture into locals so the closures below don't reference `self` before
        // all stored properties are initialised.
        let po = pluginObject
        let jq = jsQueue

        // Parse static plugin capabilities from JS (runs on jsQueue to safely read JSValues).
        self._filters = Self.parseFilters(from: po, queue: jq)
        self._imageRequestInit = Self.parseImageRequestInit(from: po, queue: jq)
        self._webStorageUtilized = jq.sync {
            po.forProperty("webStorageUtilized")?.toBool() ?? false
        }
        self._pluginSettings = Self.parsePluginSettings(from: po, queue: jq)
        self._hasParsePage = jq.sync {
            guard let fn = po.forProperty("parsePage"), !fn.isUndefined else {
                return false
            }
            return true
        }
    }

    // MARK: - Context Setup

    /// Configure the JSContext with CommonJS environment and evaluate the plugin.
    private static func setupContext(
        _ context: JSContext,
        jsCode: String,
        pluginID: String,
        queue: DispatchQueue
    ) throws -> JSValue {

        // MARK: Byte-array helpers (used by AES-GCM bridge below)

        /// Convert a JSValue (Uint8Array or plain Array) to [UInt8].
        func jsValueToBytes(_ val: JSValue) -> [UInt8]? {
            guard let arr = val.toArray() else { return nil }
            return arr.compactMap { item -> UInt8? in
                guard let n = item as? NSNumber else { return nil }
                return UInt8(n.intValue & 0xFF)
            }
        }

        /// Convert [UInt8] to a Uint8Array JSValue (falls back to plain Array).
        func bytesToJSValue(_ bytes: [UInt8]) -> JSValue {
            if let ctor = context.objectForKeyedSubscript("Uint8Array"),
                !ctor.isUndefined, !ctor.isNull
            {
                let jsArr = bytes.map { NSNumber(value: $0) }
                if let result = ctor.construct(withArguments: [jsArr]) {
                    return result
                }
            }
            let jsArr = bytes.map { NSNumber(value: $0) }
            return JSValue(object: jsArr, in: context)!
        }

        // MARK: Exception handler

        var lastException: String?
        context.exceptionHandler = { _, exception in
            lastException = exception?.toString()
        }

        // MARK: console.log / warn / error

        let consoleLog: @convention(block) (String) -> Void = { message in
            print("🔌 [\(pluginID)] \(message)")
        }
        let console = JSValue(newObjectIn: context)!
        console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        console.setObject(consoleLog, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        // MARK: module / exports (CommonJS)

        let module = JSValue(newObjectIn: context)!
        let exports = JSValue(newObjectIn: context)!
        module.setObject(exports, forKeyedSubscript: "exports" as NSString)
        context.setObject(module, forKeyedSubscript: "module" as NSString)
        context.setObject(exports, forKeyedSubscript: "exports" as NSString)

        // MARK: Native Storage bridges → UserDefaults

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

        // MARK: Native Timer bridges

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

        // Expose pluginID to JS shims
        context.setObject(pluginID, forKeyedSubscript: "pluginID" as NSString)

        // MARK: fetch → URLSession bridge

        setupFetch(in: context, pluginID: pluginID)

        // MARK: AES-GCM bridge (CryptoKit)

        let nativeGCMCreate: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = {
            keyVal, nonceVal, aadVal in
            guard let keyBytes = jsValueToBytes(keyVal),
                let nonceBytes = jsValueToBytes(nonceVal)
            else {
                return JSValue(undefinedIn: context)!
            }

            let keyData = Data(keyBytes)
            let nonceData = Data(nonceBytes)
            let aadData: Data
            if aadVal.isNull || aadVal.isUndefined {
                aadData = Data()
            } else if let aadBytes = jsValueToBytes(aadVal) {
                aadData = Data(aadBytes)
            } else {
                aadData = Data()
            }

            let gcmObj = JSValue(newObjectIn: context)!

            let encryptFn: @convention(block) (JSValue) -> JSValue = { plaintextVal in
                guard let plaintextBytes = jsValueToBytes(plaintextVal) else {
                    return JSValue(undefinedIn: context)!
                }
                do {
                    let key = SymmetricKey(data: keyData)
                    let nonce = try AES.GCM.Nonce(data: nonceData)
                    let sealedBox: AES.GCM.SealedBox
                    if aadData.isEmpty {
                        sealedBox = try AES.GCM.seal(Data(plaintextBytes), using: key, nonce: nonce)
                    } else {
                        sealedBox = try AES.GCM.seal(
                            Data(plaintextBytes), using: key, nonce: nonce, authenticating: aadData
                        )
                    }
                    // Output = ciphertext ++ tag (tag is always 16 bytes)
                    let output = [UInt8](sealedBox.ciphertext) + [UInt8](sealedBox.tag)
                    return bytesToJSValue(output)
                } catch {
                    print("⚠️ [\(pluginID)] AES-GCM encrypt failed: \(error)")
                    return JSValue(undefinedIn: context)!
                }
            }

            let decryptFn: @convention(block) (JSValue) -> JSValue = { ciphertextVal in
                guard let allBytes = jsValueToBytes(ciphertextVal), allBytes.count > 16 else {
                    return JSValue(undefinedIn: context)!
                }
                let tagBytes = Array(allBytes.suffix(16))
                let cipherBytes = Array(allBytes.dropLast(16))
                do {
                    let key = SymmetricKey(data: keyData)
                    let nonce = try AES.GCM.Nonce(data: nonceData)
                    let box = try AES.GCM.SealedBox(
                        nonce: nonce,
                        ciphertext: Data(cipherBytes),
                        tag: Data(tagBytes)
                    )
                    let plaintext: Data
                    if aadData.isEmpty {
                        plaintext = try AES.GCM.open(box, using: key)
                    } else {
                        plaintext = try AES.GCM.open(box, using: key, authenticating: aadData)
                    }
                    return bytesToJSValue([UInt8](plaintext))
                } catch {
                    print("⚠️ [\(pluginID)] AES-GCM decrypt failed: \(error)")
                    return JSValue(undefinedIn: context)!
                }
            }

            gcmObj.setObject(
                unsafeBitCast(encryptFn, to: AnyObject.self),
                forKeyedSubscript: "encrypt" as NSString
            )
            gcmObj.setObject(
                unsafeBitCast(decryptFn, to: AnyObject.self),
                forKeyedSubscript: "decrypt" as NSString
            )
            return gcmObj
        }
        context.setObject(
            unsafeBitCast(nativeGCMCreate, to: AnyObject.self),
            forKeyedSubscript: "_nativeGCMCreate" as NSString
        )

        // MARK: Encoding-aware fetch text bridge

        let nativeFetchTextWithEncoding: @convention(block) (String, JSValue?, String?) -> JSValue =
            {
                urlString, options, encoding in

                let promiseConstructor = context.objectForKeyedSubscript("Promise")!
                let promise = promiseConstructor.construct(withArguments: [
                    unsafeBitCast(
                        { (resolve: JSValue, reject: JSValue) in
                            DispatchQueue.global(qos: .userInitiated).async {
                                guard let url = URL(string: urlString) else {
                                    reject.call(withArguments: ["Invalid URL: \(urlString)"])
                                    return
                                }

                                var request = URLRequest(url: url)
                                request.timeoutInterval = 30
                                request.setValue(
                                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                                    forHTTPHeaderField: "User-Agent"
                                )
                                request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                                request.setValue("*/*", forHTTPHeaderField: "Accept")
                                request.setValue(
                                    "gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
                                request.setValue("*", forHTTPHeaderField: "Accept-Language")
                                request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
                                request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")

                                if let opts = options, !opts.isUndefined, !opts.isNull {
                                    if let method = opts.forProperty("method"), !method.isUndefined
                                    {
                                        request.httpMethod = method.toString()
                                    }
                                    if let headers = opts.forProperty("headers"),
                                        !headers.isUndefined
                                    {
                                        if let headerDict = headers.toDictionary()
                                            as? [String: String]
                                        {
                                            for (k, v) in headerDict {
                                                request.setValue(v, forHTTPHeaderField: k)
                                            }
                                        }
                                    }
                                    if let body = opts.forProperty("body"), !body.isUndefined {
                                        request.httpBody = body.toString().data(using: .utf8)
                                    }
                                }

                                print("📡 [\(pluginID)] [encoding-fetch] \(request.httpMethod ?? "GET") \(urlString)")
                                if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                                    print("   Headers: \(headers)")
                                }
                                if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                                    print("   Body: \(bodyStr)")
                                }

                                let semaphore = DispatchSemaphore(value: 0)
                                var responseData: Data?
                                var responseError: Error?
                                var statusCode = 0

                                let task = URLSession.shared.dataTask(with: request) {
                                    data, response, error in
                                    responseData = data
                                    responseError = error
                                    if let httpResponse = response as? HTTPURLResponse {
                                        statusCode = httpResponse.statusCode
                                    }
                                    semaphore.signal()
                                }
                                task.resume()
                                semaphore.wait()

                                if let error = responseError {
                                    print("❌ [\(pluginID)] [encoding-fetch] Failed: \(error.localizedDescription)")
                                    reject.call(withArguments: [error.localizedDescription])
                                    return
                                }

                                print("📥 [\(pluginID)] [encoding-fetch] Completed (status: \(statusCode), size: \(responseData?.count ?? 0) bytes)")

                                let data = responseData ?? Data()
                                let text: String

                                if let encodingStr = encoding, !encodingStr.isEmpty {
                                    let cfEncoding = CFStringConvertIANACharSetNameToEncoding(
                                        encodingStr as CFString
                                    )
                                    if cfEncoding != kCFStringEncodingInvalidId {
                                        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(
                                            cfEncoding)
                                        let stringEncoding = String.Encoding(rawValue: nsEncoding)
                                        text =
                                            String(data: data, encoding: stringEncoding)
                                            ?? String(data: data, encoding: .utf8)
                                            ?? ""
                                    } else {
                                        text = String(data: data, encoding: .utf8) ?? ""
                                    }
                                } else {
                                    text = String(data: data, encoding: .utf8) ?? ""
                                }

                                resolve.call(withArguments: [text])
                            }
                        } as @convention(block) (JSValue, JSValue) -> Void,
                        to: AnyObject.self
                    )
                ])!
                return promise
            }
        context.setObject(
            unsafeBitCast(nativeFetchTextWithEncoding, to: AnyObject.self),
            forKeyedSubscript: "_nativeFetchTextWithEncoding" as NSString
        )

        // MARK: Evaluate shims + plugin

        context.evaluateScript(PluginShims.jsCode, withSourceURL: URL(string: "plugin://shims"))
        if let exception = lastException {
            print("⚠️ [\(pluginID)] Shims setup exception: \(exception)")
            lastException = nil
        }

        context.evaluateScript(jsCode, withSourceURL: URL(string: "plugin://\(pluginID)"))
        if let exception = lastException {
            throw PluginError.jsEvaluationFailed(exception)
        }

        // MARK: Extract module.exports (prefer .default)

        guard let exportsObj = module.forProperty("exports"),
            !exportsObj.isUndefined,
            !exportsObj.isNull
        else {
            throw PluginError.jsEvaluationFailed("module.exports is empty")
        }

        if let defaultProp = exportsObj.forProperty("default"),
            !defaultProp.isUndefined,
            !defaultProp.isNull
        {
            return defaultProp
        }
        return exportsObj
    }

    // MARK: - Fetch Setup

    /// Set up a `fetch` polyfill bridged to URLSession.
    ///
    /// Returns a Promise that resolves to a Response-like object with
    /// `.text()`, `.json()`, `.ok`, `.status`, `.url`, and `.headers.get(key)`.
    private static func setupFetch(in context: JSContext, pluginID: String) {
        let fetchBlock: @convention(block) (String, JSValue?) -> JSValue = { urlString, options in
            let promiseConstructor = context.objectForKeyedSubscript("Promise")!
            let promise = promiseConstructor.construct(withArguments: [
                unsafeBitCast(
                    { (resolve: JSValue, reject: JSValue) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            guard let url = URL(string: urlString) else {
                                reject.call(withArguments: ["Invalid URL: \(urlString)"])
                                return
                            }

                            var request = URLRequest(url: url)
                            request.timeoutInterval = 30

                            // Default headers matching mobile Safari
                            request.setValue(
                                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                                forHTTPHeaderField: "User-Agent"
                            )
                            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
                            request.setValue("*/*", forHTTPHeaderField: "Accept")
                            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
                            request.setValue("*", forHTTPHeaderField: "Accept-Language")
                            request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
                            request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")

                            // Apply options (method, headers, body)
                            if let opts = options, !opts.isUndefined {
                                if let method = opts.forProperty("method"), !method.isUndefined {
                                    request.httpMethod = method.toString()
                                }
                                if let headers = opts.forProperty("headers"), !headers.isUndefined {
                                    if let headerDict = headers.toDictionary() as? [String: String]
                                    {
                                        for (key, value) in headerDict {
                                            request.setValue(value, forHTTPHeaderField: key)
                                        }
                                    }
                                }
                                if let body = opts.forProperty("body"), !body.isUndefined {
                                    request.httpBody = body.toString().data(using: .utf8)
                                }
                            }

                            print("📡 [\(pluginID)] [fetch] \(request.httpMethod ?? "GET") \(urlString)")
                            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                                print("   Headers: \(headers)")
                            }
                            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                                print("   Body: \(bodyStr)")
                            }

                            let semaphore = DispatchSemaphore(value: 0)
                            var responseData: Data?
                            var responseError: Error?
                            var httpResponse: HTTPURLResponse?

                            let task = URLSession.shared.dataTask(with: request) {
                                data, response, error in
                                responseData = data
                                responseError = error
                                httpResponse = response as? HTTPURLResponse
                                semaphore.signal()
                            }
                            task.resume()
                            semaphore.wait()

                            if let error = responseError {
                                print("❌ [\(pluginID)] [fetch] Failed: \(error.localizedDescription)")
                                reject.call(withArguments: [error.localizedDescription])
                                return
                            }

                            let statusCode = httpResponse?.statusCode ?? 200
                            print("📥 [\(pluginID)] [fetch] Completed (status: \(statusCode), size: \(responseData?.count ?? 0) bytes)")

                            let isOk = (200...299).contains(statusCode)
                            let text = String(data: responseData ?? Data(), encoding: .utf8) ?? ""

                            let responseObj = JSValue(newObjectIn: context)!

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

                            // Response headers with case-insensitive .get(key)
                            let rawHeaders = httpResponse?.allHeaderFields ?? [:]
                            let headersObj = JSValue(newObjectIn: context)!
                            let headersGetFn: @convention(block) (String) -> String? = { key in
                                let lKey = key.lowercased()
                                for (k, v) in rawHeaders {
                                    if let kStr = k as? String, kStr.lowercased() == lKey {
                                        return v as? String
                                    }
                                }
                                return nil
                            }
                            headersObj.setObject(
                                unsafeBitCast(headersGetFn, to: AnyObject.self),
                                forKeyedSubscript: "get" as NSString
                            )

                            responseObj.setObject(
                                unsafeBitCast(textFn, to: AnyObject.self),
                                forKeyedSubscript: "text" as NSString
                            )
                            responseObj.setObject(
                                unsafeBitCast(jsonFn, to: AnyObject.self),
                                forKeyedSubscript: "json" as NSString
                            )
                            responseObj.setObject(isOk, forKeyedSubscript: "ok" as NSString)
                            responseObj.setObject(
                                statusCode, forKeyedSubscript: "status" as NSString)
                            responseObj.setObject(urlString, forKeyedSubscript: "url" as NSString)
                            responseObj.setObject(
                                headersObj, forKeyedSubscript: "headers" as NSString)

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

    // MARK: - Plugin Property Parsing

    /// Parse the plugin's `filters` JS object into typed `[PluginFilter]`.
    private static func parseFilters(from pluginObject: JSValue, queue: DispatchQueue)
        -> [PluginFilter]
    {
        return queue.sync {
            guard let filtersVal = pluginObject.forProperty("filters"),
                !filtersVal.isUndefined, !filtersVal.isNull,
                let filtersDict = filtersVal.toDictionary()
            else {
                return []
            }

            var filters: [PluginFilter] = []
            for (rawKey, rawValue) in filtersDict {
                guard let key = rawKey as? String,
                    let filterConfig = rawValue as? [String: Any],
                    let type = filterConfig["type"] as? String,
                    let label = filterConfig["label"] as? String
                else {
                    continue
                }

                let optionsArray = parseFilterOptions(from: filterConfig)

                switch type {
                case "Text":
                    let defaultValue = filterConfig["value"] as? String ?? ""
                    filters.append(.textInput(key: key, label: label, defaultValue: defaultValue))

                case "Picker":
                    let defaultValue = filterConfig["value"] as? String ?? ""
                    filters.append(
                        .picker(
                            key: key, label: label, defaultValue: defaultValue,
                            options: optionsArray)
                    )

                case "Checkbox":
                    var defaultValues: [String] = []
                    if let arr = filterConfig["value"] as? [Any] {
                        defaultValues = arr.compactMap { $0 as? String }
                    }
                    filters.append(
                        .checkboxGroup(
                            key: key, label: label, defaultValues: defaultValues,
                            options: optionsArray
                        )
                    )

                case "Switch":
                    let defaultValue: Bool
                    if let b = filterConfig["value"] as? Bool {
                        defaultValue = b
                    } else if let n = filterConfig["value"] as? NSNumber {
                        defaultValue = n.boolValue
                    } else {
                        defaultValue = false
                    }
                    filters.append(
                        .switchFilter(key: key, label: label, defaultValue: defaultValue))

                case "XCheckbox":
                    var defaultInclude: [String] = []
                    var defaultExclude: [String] = []
                    if let valueDict = filterConfig["value"] as? [String: Any] {
                        if let incArr = valueDict["include"] as? [Any] {
                            defaultInclude = incArr.compactMap { $0 as? String }
                        }
                        if let excArr = valueDict["exclude"] as? [Any] {
                            defaultExclude = excArr.compactMap { $0 as? String }
                        }
                    }
                    filters.append(
                        .excludableCheckboxGroup(
                            key: key,
                            label: label,
                            defaultInclude: defaultInclude,
                            defaultExclude: defaultExclude,
                            options: optionsArray
                        )
                    )

                default:
                    break
                }
            }
            return filters
        }
    }

    /// Parse the plugin's `imageRequestInit` JS object.
    private static func parseImageRequestInit(
        from pluginObject: JSValue,
        queue: DispatchQueue
    ) -> ImageRequestInit {
        return queue.sync {
            guard let initVal = pluginObject.forProperty("imageRequestInit"),
                !initVal.isUndefined, !initVal.isNull
            else {
                return .default
            }

            let methodStr = initVal.forProperty("method")?.toString()
            let method: String? =
                (methodStr == nil || methodStr == "undefined") ? nil : methodStr

            var headers: [String: String] = [:]
            if let headersVal = initVal.forProperty("headers"),
                !headersVal.isUndefined, !headersVal.isNull,
                let headersDict = headersVal.toDictionary() as? [String: String]
            {
                headers = headersDict
            }

            return ImageRequestInit(method: method, headers: headers)
        }
    }

    /// Parse the plugin's `pluginSettings` JS object into typed `[PluginSetting]`.
    private static func parsePluginSettings(
        from pluginObject: JSValue,
        queue: DispatchQueue
    ) -> [PluginSetting] {
        return queue.sync {
            guard let settingsVal = pluginObject.forProperty("pluginSettings"),
                !settingsVal.isUndefined, !settingsVal.isNull,
                let settingsDict = settingsVal.toDictionary()
            else {
                return []
            }

            var settings: [PluginSetting] = []
            for (rawKey, rawValue) in settingsDict {
                guard let key = rawKey as? String,
                    let settingConfig = rawValue as? [String: Any],
                    let type = settingConfig["type"] as? String,
                    let label = settingConfig["label"] as? String
                else {
                    continue
                }

                let optionsArray = parseFilterOptions(from: settingConfig)

                switch type {
                case "Text":
                    let value = settingConfig["value"] as? String ?? ""
                    settings.append(.text(key: key, label: label, value: value))

                case "Switch":
                    let value: Bool
                    if let b = settingConfig["value"] as? Bool {
                        value = b
                    } else if let n = settingConfig["value"] as? NSNumber {
                        value = n.boolValue
                    } else {
                        value = false
                    }
                    settings.append(.switchSetting(key: key, label: label, value: value))

                case "Select":
                    let value = settingConfig["value"] as? String ?? ""
                    settings.append(
                        .select(key: key, label: label, value: value, options: optionsArray)
                    )

                case "CheckboxGroup":
                    var values: [String] = []
                    if let arr = settingConfig["value"] as? [Any] {
                        values = arr.compactMap { $0 as? String }
                    }
                    settings.append(
                        .checkboxGroup(
                            key: key, label: label, values: values, options: optionsArray)
                    )

                default:
                    break
                }
            }
            return settings
        }
    }

    /// Shared helper — parse `options` array from a filter/setting config dict.
    private static func parseFilterOptions(from config: [String: Any]) -> [FilterOption] {
        guard let optsRaw = config["options"] as? [Any] else { return [] }
        return optsRaw.compactMap { item -> FilterOption? in
            // NSDictionary bridges to [String: Any] or [AnyHashable: Any]
            let label: String?
            let value: String?
            if let d = item as? [String: Any] {
                label = d["label"] as? String
                value = d["value"] as? String
            } else if let d = item as? [AnyHashable: Any] {
                label = d["label"] as? String
                value = d["value"] as? String
            } else {
                return nil
            }
            guard let l = label, let v = value else { return nil }
            return FilterOption(label: l, value: v)
        }
    }

    // MARK: - Protocol Methods

    func popularNovels(
        page: Int,
        showLatest: Bool,
        filterValues: FilterValues?
    ) async throws -> [PartialNovel] {
        var options: [String: Any] = ["showLatestNovels": showLatest]

        if let filterValues, !filterValues.isEmpty {
            options["filters"] = serializeFilterValues(filterValues)
        } else {
            // Pass the plugin's own default filters object through untouched
            let defaultFilters = jsQueue.sync { [weak self] in
                self?.pluginObject.forProperty("filters")
            }
            if let defaultFilters, !defaultFilters.isUndefined, !defaultFilters.isNull {
                options["filters"] = defaultFilters
            }
        }

        let result = try await callPluginFunction("popularNovels", args: [page, options])
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

    func parsePage(path: String, page: String) async throws -> SourcePage {
        print("📄 [\(id)] parsePage: path=\(path), page=\(page)")
        let result = try await callPluginFunction("parsePage", args: [path, page])

        let chapters: [SourceChapter]
        if let array = castToDictArray(result.toArray()) {
            print("📄 [\(id)] parsePage result: top-level array with \(array.count) items")
            chapters = array.compactMap(parseSourceChapter)
        } else if let chaptersVal = result.forProperty("chapters"),
            let array = castToDictArray(chaptersVal.toArray())
        {
            print("📄 [\(id)] parsePage result: object with 'chapters' array (\(array.count) items)")
            chapters = array.compactMap(parseSourceChapter)
        } else {
            print("📄 [\(id)] parsePage result: could not parse chapters. isObject=\(result.isObject), isArray=\(!result.isUndefined && result.toArray() != nil)")
            if let raw = result.toDictionary() {
            }
            chapters = []
        }
        print("📄 [\(id)] parsePage returning \(chapters.count) parsed chapters")
        return SourcePage(chapters: chapters)
    }

    func resolveUrl(path: String, isNovel: Bool) -> String {
        // Attempt to call the plugin's own resolveUrl if it exposes one.
        let jsResult = jsQueue.sync { [weak self] () -> String? in
            guard let self else { return nil }
            guard let fn = self.pluginObject.forProperty("resolveUrl"),
                !fn.isUndefined, !fn.isNull
            else {
                return nil
            }
            let result = self.pluginObject.invokeMethod(
                "resolveUrl", withArguments: [path, isNovel])
            if let str = result?.toString(), !str.isEmpty, str != "undefined" {
                return str
            }
            return nil
        }

        if let jsResult {
            return jsResult
        }

        // Fallback: same logic as the protocol extension default.
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("//") {
            return path
        }
        let base = siteURL.hasSuffix("/") ? String(siteURL.dropLast()) : siteURL
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        return base + suffix
    }

    // MARK: - JS Bridge

    /// Call a function on the plugin object, handling Promises automatically.
    private func callPluginFunction(_ name: String, args: [Any]) async throws -> JSValue {
        print("🔌 [\(id)] Calling function '\(name)' with args: \(args)")
        do {
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<JSValue, Error>) in
                jsQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: PluginError.contextCreationFailed)
                        return
                    }

                    guard let function = self.pluginObject.forProperty(name),
                        !function.isUndefined
                    else {
                        continuation.resume(throwing: PluginError.functionNotFound(name))
                        return
                    }

                    let result = self.pluginObject.invokeMethod(name, withArguments: args)

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

        promise.invokeMethod(
            "then",
            withArguments: [
                unsafeBitCast(thenBlock, to: AnyObject.self)
            ])?.invokeMethod(
                "catch",
                withArguments: [
                    unsafeBitCast(catchBlock, to: AnyObject.self)
                ])
    }

    // MARK: - Filter Serialization

    /// Convert Swift `FilterValues` to the JS dict shape each plugin expects.
    private func serializeFilterValues(_ values: FilterValues) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in values {
            switch value {
            case .text(let s):
                result[key] = ["type": "Text", "value": s]
            case .picker(let s):
                result[key] = ["type": "Picker", "value": s]
            case .checkbox(let arr):
                result[key] = ["type": "Checkbox", "value": arr]
            case .switchVal(let b):
                result[key] = ["type": "Switch", "value": b]
            case .excludable(let inc, let exc):
                result[key] = ["type": "XCheckbox", "value": ["include": inc, "exclude": exc]]
            }
        }
        return result
    }

    // MARK: - Result Parsing

    /// Safely cast Any? to [[String: Any]], handling strict Swift NSDictionary/Any type conversion.
    private func castToDictArray(_ val: Any?) -> [[String: Any]]? {
        guard let arr = val as? [Any] else { return nil }
        return arr.compactMap { item in
            if let dict = item as? [String: Any] {
                return dict
            } else if let nsDict = item as? NSDictionary {
                var swiftDict: [String: Any] = [:]
                for (k, v) in nsDict {
                    if let keyStr = k as? String {
                        swiftDict[keyStr] = v
                    }
                }
                return swiftDict
            }
            return nil
        }
    }

    /// Parse a JSValue array into `[PartialNovel]`.
    private func parsePartialNovels(from value: JSValue) -> [PartialNovel] {
        guard let array = castToDictArray(value.toArray()) else {
            if let novelsValue = value.forProperty("novels"),
                let array = castToDictArray(novelsValue.toArray())
            {
                return array.compactMap(parsePartialNovel)
            }
            return []
        }
        return array.compactMap(parsePartialNovel)
    }

    private func parsePartialNovel(from dict: [String: Any]) -> PartialNovel? {
        guard let name = dict["name"] as? String,
            let path = dict["path"] as? String
        else {
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
            let path = dict["path"] as? String
        else {
            throw PluginError.invalidResult("Novel missing required 'name' or 'path'")
        }

        // Genres: some plugins return a String, others an Array<String>.
        let genres: String?
        if let g = dict["genres"] as? String {
            genres = g
        } else if let arr = dict["genres"] as? [Any] {
            genres = arr.compactMap { $0 as? String }.joined(separator: ", ")
        } else {
            genres = nil
        }

        let chapters: [SourceChapter]
        if let chaptersArray = castToDictArray(dict["chapters"]) {
            chapters = chaptersArray.compactMap(parseSourceChapter)
        } else {
            chapters = []
        }

        let totalPages: Int?
        let rawTotalPages = dict["totalPages"]
        print("📖 [\(id)] parseSourceNovel: rawTotalPages=\(String(describing: rawTotalPages)), type=\(type(of: rawTotalPages as Any))")
        if let num = rawTotalPages as? Int {
            totalPages = num
        } else if let numDouble = rawTotalPages as? Double {
            totalPages = Int(numDouble)
        } else if let numStr = rawTotalPages as? String {
            totalPages = Int(numStr)
        } else if let numNS = rawTotalPages as? NSNumber {
            totalPages = numNS.intValue
        } else {
            totalPages = nil
        }
        print("📖 [\(id)] parseSourceNovel: totalPages=\(String(describing: totalPages)), chapters=\(chapters.count)")

        return SourceNovel(
            name: name,
            path: path,
            cover: dict["cover"] as? String,
            genres: genres,
            summary: dict["summary"] as? String,
            author: dict["author"] as? String,
            artist: dict["artist"] as? String,
            status: dict["status"] as? String,
            chapters: chapters,
            totalPages: totalPages
        )
    }

    private func parseSourceChapter(from dict: [String: Any]) -> SourceChapter? {
        guard let name = dict["name"] as? String,
            let path = dict["path"] as? String
        else {
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
