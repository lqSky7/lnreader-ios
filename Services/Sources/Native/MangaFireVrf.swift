// MangaFireVrf.swift - MangaFire's `vrf` request signature, ported byte for byte from VrfSigner.kt.
//
// Three substitution stages over the path plus its sorted query string, then URL-safe base64.
// The tables and keys are upstream's constants, not a secret.

import Foundation

enum MangaFireVrf {

    private struct Stage {
        let table: [UInt8]
        let key: [UInt8]
        let iv: UInt8

        init(table: String, key: String, iv: UInt8) {
            self.table = [UInt8](Data(base64Encoded: table) ?? Data())
            self.key = [UInt8](Data(base64Encoded: key) ?? Data())
            self.iv = iv
        }

        func encrypt(_ data: [UInt8]) -> [UInt8] {
            var previous = iv
            return data.enumerated().map { index, byte in
                previous = table[Int(byte ^ key[index % key.count] ^ previous)]
                return previous
            }
        }
    }

    private static let stages = [
        Stage(
            table: "yINlmUNho8VYJT+ibTIP+9ESiULpVEtMOoD6U6lRE0R/xwXo/Xp9NrUgC4cw/Lmo33vUyjUE40kUoEWIr/fxfNNcq2s79ShQ5NhNrFnJ4hXPwOu/SuXzIbuTQKGFvfm08E9jvCfqAtoDqvQq3dVWPQFmJjgvkISBeXY3BgANR+yVnjGbcxZ47d6kLNfZPIayTq3/YGySb1KuVZodWp/WGNAO5pfMcpaK53Hhs0allBszaMaxuouOwdxbwgxIw6YunSsXjI05Yi0j9j4eHKfSXR8Ifo/Od+8iamRfCXTyvm7NGRGYdcQ0ywcK/u6RXhrbcCm4t2eCtrDgQVecJGkQ+A==",
            key: "0Ec58JOY3uBzJK9m3zqIOpdlF7UFiax9DmA=", iv: 0x5A
        ),
        Stage(
            table: "IUFltCxD3Oc2cwCgkJffthaOg9cgPUb0LgW6H/VtfcF0kc5F25t+aWj6JH9VOhOaY0rAFdUxlDnl5BLNvwEJvQtP5qcw7vdb/K+chnbwnspSHT8mz5lqwz41TezG0hkO06FTjJZhsyNuFLDpD2ZZxQj/QIRcF90zpmQ7Byu483WsQqUE0C342HL+JXngRB6fRzxRyVTaKu83h7UYTJ0QMt6ixFh6S3F8gqkKwrGTL3jHNBsD45UnifK8+RGtishQV2K3rujLKEkiZxpr2dYcudFW4oFsDKhad3CLBvuyTqsCo4B7mL5IKQ1vXo/MOOvq1I1d8ar9X6Ttu5KF4fZgiA==",
            key: "AAdjb1iPY8CiDmq9H34tKTBF8a3oDQ==", iv: 0x35
        ),
        Stage(
            table: "NQHlu1/wVO5EmkwQymF810qqY2xG1k2obcas4Z9mCsPEIFl9pRIjFxbJ7ybMHbBckT5Ton85E0FOeHezbh/mjlEYpmpnlXOS8dgrqeq2KfxImTh1YK9y0PeMNhzA1OQzSY9brYOJq/l2QnE/hwOeZIhPixVSKIUlDb5vLcH6RWKxkIEMuP0bDwIqQ71AJJaEaMJL7A6YtyIwoRT+L5v4aZzodN/0+3nOGsfblFjgxSfPzVDjNFeNl5P26+kEC/8AHgdrpAbt3hHz3HrRN1Y6e+JHgF7ncFWnoF0y3THL1S71WgWGCa6KtSzTCCG58n68nTyj2T3Sshk7utqCtMi/ZQ==",
            key: "DELOJgPsVaCcblDtTGMdHzM=", iv: 0xBA
        ),
    ]

    static func sign(_ path: String) -> String {
        let data = stages.reduce([UInt8](path.utf8)) { $1.encrypt($0) }
        return Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The query string for an `/api/<path>` request: the sorted params percent-encoded, then `vrf`.
    ///
    /// The signed string uses raw values, and numbers each run of a `key[]` as `key[0]`, `key[1]`, ...
    /// while the wire keeps `key[]`, as the upstream interceptor does.
    static func query(path: String, sortedParams: [(String, String)]) -> String {
        var lastKey = ""
        var index = 0
        let signed = sortedParams.map { key, value -> String in
            guard key.hasSuffix("[]") else { return "\(key)=\(value)" }
            if lastKey != key { index = 0 }
            lastKey = key
            defer { index += 1 }
            return "\(key.replacingOccurrences(of: "[]", with: "[\(index)]"))=\(value)"
        }.joined(separator: "&")

        let wire = sortedParams.map { "\(escape($0.0))=\(escape($0.1))" }
        let vrf = "vrf=" + sign(path + (signed.isEmpty ? "" : "?" + signed))
        return (wire + [vrf]).joined(separator: "&")
    }

    private static func escape(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()[]")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
