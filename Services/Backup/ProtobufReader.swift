// ProtobufReader.swift - Just enough protobuf wire format to read a Mihon backup.
//
// A `.tachibk` file is a gzipped protobuf message. The schema is small and
// frozen, and the project has no SwiftProtobuf dependency, so fields are read
// straight off the wire. Unknown fields are skipped, which is also how Mihon
// itself tolerates fields from newer forks.

import Foundation

struct ProtobufReader {

    enum ReadError: LocalizedError {
        case truncated
        case malformed
        case unsupportedWireType(Int)

        var errorDescription: String? {
            switch self {
            case .truncated: "The backup ends in the middle of a record."
            case .malformed: "The backup contains data that is not valid."
            case .unsupportedWireType(let type): "The backup uses an unsupported field type (\(type))."
            }
        }
    }

    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case bytes(Data)
    }

    private let data: Data
    private var index: Int

    init(_ data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool { index >= data.endIndex }

    /// Next field number and its value, or `nil` at the end of the message.
    mutating func next() throws -> (field: Int, value: Value)? {
        guard !isAtEnd else { return nil }
        let key = try varint()
        let field = Int(truncatingIfNeeded: key >> 3)
        guard field > 0 else { throw ReadError.malformed }

        switch key & 7 {
        case 0: return (field, .varint(try varint()))
        case 1: return (field, .fixed64(try fixed(8)))
        case 2:
            let length = try varint()
            guard length <= UInt64(data.endIndex - index) else { throw ReadError.truncated }
            let end = index + Int(length)
            defer { index = end }
            return (field, .bytes(data[index..<end]))
        case 5: return (field, .fixed32(UInt32(truncatingIfNeeded: try fixed(4))))
        case let other: throw ReadError.unsupportedWireType(Int(other))
        }
    }

    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < data.endIndex else { throw ReadError.truncated }
            let byte = data[index]
            index += 1
            if shift < 64 { result |= UInt64(byte & 0x7f) << shift }
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 70 else { throw ReadError.malformed }
        }
    }

    private mutating func fixed(_ count: Int) throws -> UInt64 {
        guard index + count <= data.endIndex else { throw ReadError.truncated }
        var result: UInt64 = 0
        for offset in 0..<count { result |= UInt64(data[index + offset]) << UInt64(8 * offset) }
        index += count
        return result
    }
}

extension ProtobufReader.Value {

    var int64: Int64? {
        switch self {
        case .varint(let value), .fixed64(let value): Int64(bitPattern: value)
        case .fixed32(let value): Int64(Int32(bitPattern: value))
        case .bytes: nil
        }
    }

    var int: Int? { int64.flatMap { Int(exactly: $0) } }

    var bool: Bool? { int64.map { $0 != 0 } }

    var float: Float? {
        if case .fixed32(let bits) = self { return Float(bitPattern: bits) }
        return nil
    }

    var string: String? {
        if case .bytes(let data) = self { return String(data: data, encoding: .utf8) }
        return nil
    }

    var message: Data? {
        if case .bytes(let data) = self { return data }
        return nil
    }

    /// A repeated integer field, which writers emit either one varint per
    /// element or packed into one length-delimited blob.
    var integers: [Int64] {
        switch self {
        case .bytes(let data):
            var reader = ProtobufReader(data)
            var out: [Int64] = []
            while !reader.isAtEnd {
                guard let value = try? reader.varintValue() else { break }
                out.append(Int64(bitPattern: value))
            }
            return out
        default:
            return int64.map { [$0] } ?? []
        }
    }
}

private extension ProtobufReader {
    mutating func varintValue() throws -> UInt64 { try varint() }
}
